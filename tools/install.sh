#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install.sh: put agent-profile on your PATH.
#
# Two modes, and the default is the safe one.
#
# Release mode downloads a tagged release, checks it against the SHA256SUMS
# published beside it, checks the Sigstore signature when cosign is installed,
# and installs a copy under ~/.local/share/agent-profile/<version>/. What runs
# in your shell then only changes when you run this script again.
#
# --dev is the old behaviour: a symlink straight into a git checkout. It is
# right for working on the tool and wrong everywhere else, because the
# installed command becomes whatever the checkout happens to hold, and
# 'eval "$(agpin guard)"' runs it at every shell start.
#
# Idempotent, and it says which of "installed" and "already installed"
# happened, because those must not look the same.
#
# Needs nothing beyond a stock macOS: curl, shasum, tar. cosign is optional,
# and when it is missing the script says exactly what went unverified rather
# than staying quiet about it.

set -u

SHORT_NAME="agpin"
LONG_NAME="agent-profile"

ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
DEV_TARGET="$ROOT/bin/$LONG_NAME"

# Overridable so the test suite can serve a release from a local directory over
# a file:// URL, and so someone can install from a fork without editing this
# file. The defaults are the only place the project's own URLs appear.
: "${AGENT_PROFILE_RELEASE_BASE_URL:=https://github.com/mmsge/agent-profile-manager/releases}"
: "${AGENT_PROFILE_RELEASE_API_URL:=https://api.github.com/repos/mmsge/agent-profile-manager/releases/latest}"
: "${AGENT_PROFILE_SHARE_DIR:=$HOME/.local/share/agent-profile}"
: "${AGENT_PROFILE_COSIGN:=cosign}"

# What the Sigstore certificate must say. The identity is the workflow that
# built the release, tied to a tag; the issuer is GitHub's OIDC provider. A
# tarball signed by anything else fails, which is the point: a checksum only
# says the bytes are intact, and this says who produced them.
: "${AGENT_PROFILE_COSIGN_IDENTITY:=^https://github\.com/mmsge/agent-profile-manager/\.github/workflows/release\.yml@refs/tags/}"
: "${AGENT_PROFILE_COSIGN_ISSUER:=https://token.actions.githubusercontent.com}"

PREFIX=""
UNINSTALL=""
MODE="release"
VERSION=""
TARGET=""
WORKDIR=""

usage() {
    cat <<USAGE
usage: tools/install.sh [--version vX.Y.Z] [--dev] [--prefix DIR] [--name NAME]
                        [--uninstall]

  --version TAG  install this release instead of the newest one
  --dev          link a git checkout rather than installing a release, so the
                 command runs whatever that checkout holds at the time
  --prefix DIR   where to put the links (default: the first writable of
                 ~/.local/bin, /usr/local/bin)
  --name NAME    the short command name (default: $SHORT_NAME)
  --uninstall    remove links this script created, and nothing else

By default this downloads the newest tagged release, verifies its checksum,
verifies its Sigstore signature when cosign is installed, and unpacks it into
$AGENT_PROFILE_SHARE_DIR/<version>/.

Both '$SHORT_NAME' and '$LONG_NAME' are linked, so scripts and muscle memory
can use either. The tool names itself by whichever you invoke.
USAGE
}

say() {
    printf '%s\n' "$*"
}

fail() {
    printf 'install.sh: %s\n' "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || fail "required command '$1' not found"
}

cleanup() {
    [ -n "$WORKDIR" ] && rm -rf "$WORKDIR"
    WORKDIR=""
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)    shift; [ $# -gt 0 ] || fail "--prefix needs a value"; PREFIX="$1" ;;
        --name)      shift; [ $# -gt 0 ] || fail "--name needs a value"; SHORT_NAME="$1" ;;
        --version)   shift; [ $# -gt 0 ] || fail "--version needs a value"; VERSION="$1" ;;
        --dev)       MODE="dev" ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "unknown option '$1'" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

case "$SHORT_NAME" in
    ""|*[!A-Za-z0-9_-]*) fail "invalid --name '$SHORT_NAME'" ;;
esac

if [ "$MODE" = "dev" ] && [ -n "$VERSION" ]; then
    fail "--dev installs a checkout and --version installs a release; pick one"
fi

# A tag names a release, so it may only look like one. Refusing here keeps a
# stray argument out of a URL and out of a path under the share directory.
if [ -n "$VERSION" ]; then
    case "${VERSION#v}" in
        ""|*[!0-9.]*) fail "invalid --version '$VERSION' (expected something like v0.7.1)" ;;
    esac
fi

# Pick a prefix. ~/.local/bin first: no sudo, and it is the conventional place
# for a single user's tools.
if [ -z "$PREFIX" ]; then
    for _cand in "$HOME/.local/bin" "/usr/local/bin"; do
        if [ -d "$_cand" ] && [ -w "$_cand" ]; then PREFIX="$_cand"; break; fi
    done
    [ -n "$PREFIX" ] || PREFIX="$HOME/.local/bin"
fi

# ---------------------------------------------------------------------------
# Ownership
#
# A link is ours when it points into this checkout or into a release copy we
# unpacked. Anything else keeping the same name belongs to somebody else, and
# uninstall leaves it alone rather than guessing.
# ---------------------------------------------------------------------------

is_ours() {
    [ "$1" = "$DEV_TARGET" ] && return 0
    case "$1" in
        "$AGENT_PROFILE_SHARE_DIR"/*/bin/"$LONG_NAME") return 0 ;;
    esac
    return 1
}

if [ -n "$UNINSTALL" ]; then
    removed=0
    for _n in "$SHORT_NAME" "$LONG_NAME"; do
        _link="$PREFIX/$_n"
        if [ -L "$_link" ] && is_ours "$(readlink "$_link")"; then
            rm -f "$_link" && printf 'Removed %s\n' "$_link"
            removed=$((removed + 1))
        elif [ -e "$_link" ]; then
            printf 'Left %s alone: it is not a link this installer made.\n' "$_link"
        fi
    done
    [ "$removed" -gt 0 ] || printf 'Nothing of ours was installed in %s.\n' "$PREFIX"
    # The unpacked releases are left where they are. Removing a link cannot
    # lose anything; deleting a directory tree can, so that stays a decision
    # you make rather than one this script makes for you.
    if [ "$removed" -gt 0 ] && [ -d "$AGENT_PROFILE_SHARE_DIR" ]; then
        printf '\n'
        printf 'The unpacked releases are still in %s.\n' "$AGENT_PROFILE_SHARE_DIR"
        printf 'Remove them when you are done with them:  rm -rf %s\n' "$AGENT_PROFILE_SHARE_DIR"
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Release mode
# ---------------------------------------------------------------------------

# latest_tag: the newest release's tag, from the GitHub API.
#
# Read with sed rather than python3 deliberately. python3 on a fresh Mac opens
# the Command Line Tools dialog, and an installer is the worst place to meet
# that. tag_name is a plain string and the API emits it before the release
# body, so the first match is the field and not something quoted inside prose.
latest_tag() {
    _lt_json=$(curl -fsSL "$AGENT_PROFILE_RELEASE_API_URL" 2>/dev/null) || return 1
    printf '%s\n' "$_lt_json" \
        | tr ',' '\n' \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -1
}

fetch() {
    curl -fsSL -o "$2" "$1"
}

# verify_signature <dir> <file>: check one Sigstore bundle. Called only when
# cosign is actually installed, so a non-zero result always means a real
# failure rather than a check that could not be made.
verify_signature() {
    _vs_dir="$1"
    _vs_file="$2"
    "$AGENT_PROFILE_COSIGN" verify-blob \
        --bundle "$_vs_dir/$_vs_file.sigstore" \
        --certificate-identity-regexp "$AGENT_PROFILE_COSIGN_IDENTITY" \
        --certificate-oidc-issuer "$AGENT_PROFILE_COSIGN_ISSUER" \
        "$_vs_dir/$_vs_file" >/dev/null 2>&1
}

install_release() {
    need curl
    need shasum
    need tar

    _tag="$VERSION"
    if [ -z "$_tag" ]; then
        say "Asking which release is newest..."
        _tag=$(latest_tag) || fail "could not reach $AGENT_PROFILE_RELEASE_API_URL
Check your network, or pass --version vX.Y.Z to install a named release."
        [ -n "$_tag" ] || fail "no release found at $AGENT_PROFILE_RELEASE_API_URL"
    fi
    case "$_tag" in
        v*) ;;
        *) _tag="v$_tag" ;;
    esac
    _version="${_tag#v}"
    # The tag reaches a URL and a path under the share directory, and on this
    # path it came from the network rather than from the reader. Refuse
    # anything that is not a version, so a surprising answer cannot become a
    # surprising path.
    case "$_version" in
        ""|*[!0-9.]*) fail "the release channel answered with a tag this installer will not use: '$_tag'" ;;
    esac
    _tarball="agent-profile-$_version.tar.gz"
    _base="$AGENT_PROFILE_RELEASE_BASE_URL/download/$_tag"

    WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-install.XXXXXX") \
        || fail "could not make a temporary directory"
    trap cleanup EXIT INT TERM

    say "Downloading $_tarball"
    fetch "$_base/$_tarball" "$WORKDIR/$_tarball" \
        || fail "could not download $_base/$_tarball"
    fetch "$_base/SHA256SUMS" "$WORKDIR/SHA256SUMS" \
        || fail "could not download $_base/SHA256SUMS"

    # Check only the line for the file we actually downloaded. Handing the
    # whole SHA256SUMS to shasum would fail on every other file in the release,
    # which reads as a checksum failure and is not one.
    awk -v want="$_tarball" '
        { name = $2; sub(/^\*/, "", name); if (name == want) print }
    ' "$WORKDIR/SHA256SUMS" > "$WORKDIR/SHA256SUMS.wanted"
    if [ ! -s "$WORKDIR/SHA256SUMS.wanted" ]; then
        fail "SHA256SUMS for $_tag does not mention $_tarball, so there is nothing to verify against"
    fi
    if ! (cd "$WORKDIR" && shasum -a 256 -c SHA256SUMS.wanted) >/dev/null 2>&1; then
        fail "checksum mismatch for $_tarball
The download does not match the SHA256SUMS published with $_tag.
Nothing was installed. Try again, and if it keeps failing do not install it."
    fi
    say "Checksum matches SHA256SUMS for $_tag."

    if command -v "$AGENT_PROFILE_COSIGN" >/dev/null 2>&1; then
        fetch "$_base/$_tarball.sigstore" "$WORKDIR/$_tarball.sigstore" \
            || fail "cosign is installed but $_tag publishes no signature bundle for $_tarball.
Refusing to install it. Falling back to the checksum here would make an
unverified install look like a verified one, which is the failure this whole
path exists to prevent."
        fetch "$_base/SHA256SUMS.sigstore" "$WORKDIR/SHA256SUMS.sigstore" \
            || fail "cosign is installed but $_tag publishes no signature bundle for SHA256SUMS."
        verify_signature "$WORKDIR" "$_tarball" \
            || fail "the Sigstore signature on $_tarball did not verify.
Expected an identity matching $AGENT_PROFILE_COSIGN_IDENTITY
issued by $AGENT_PROFILE_COSIGN_ISSUER.
Nothing was installed."
        verify_signature "$WORKDIR" "SHA256SUMS" \
            || fail "the Sigstore signature on SHA256SUMS did not verify. Nothing was installed."
        say "Signature verified: built by the release workflow, from tag $_tag."
    else
        printf '\n'
        printf 'WARNING: cosign is not installed, so the signature was NOT checked.\n'
        printf '         The checksum proves the download is intact. It does not prove\n'
        printf '         who produced it: whoever served SHA256SUMS also served the\n'
        printf '         tarball, so a swap of both would pass both checks.\n'
        printf '         Run brew install cosign and this script again to check the\n'
        printf '         Sigstore signature, which ties the file to the tag and to\n'
        printf '         the workflow that built it.\n'
        printf '\n'
    fi

    mkdir -p "$WORKDIR/unpacked" || fail "could not unpack $_tarball"
    tar -xzf "$WORKDIR/$_tarball" -C "$WORKDIR/unpacked" \
        || fail "could not unpack $_tarball"
    _unpacked="$WORKDIR/unpacked/agent-profile-$_version"
    [ -x "$_unpacked/bin/$LONG_NAME" ] \
        || fail "$_tarball does not contain agent-profile-$_version/bin/$LONG_NAME"

    _dest="$AGENT_PROFILE_SHARE_DIR/$_version"
    mkdir -p "$AGENT_PROFILE_SHARE_DIR" || fail "could not create $AGENT_PROFILE_SHARE_DIR"
    # Move the verified tree into place in one step, after everything that can
    # fail has failed. A half-written version directory would be a version that
    # looks installed and is not.
    rm -rf "$_dest.incoming" "$_dest.previous"
    mv "$_unpacked" "$_dest.incoming" || fail "could not write $_dest.incoming"
    if [ -e "$_dest" ]; then
        mv "$_dest" "$_dest.previous" || fail "could not replace $_dest"
    fi
    if ! mv "$_dest.incoming" "$_dest"; then
        [ -e "$_dest.previous" ] && mv "$_dest.previous" "$_dest"
        fail "could not write $_dest"
    fi
    rm -rf "$_dest.previous"
    cleanup
    trap - EXIT INT TERM

    TARGET="$_dest/bin/$LONG_NAME"
    say "Unpacked $_tag into $_dest"
    printf '\n'
}

if [ "$MODE" = "dev" ]; then
    [ -x "$DEV_TARGET" ] || fail "cannot find an executable at $DEV_TARGET
--dev installs from a git checkout. Drop --dev to install a release instead."
    TARGET="$DEV_TARGET"
else
    install_release
fi

mkdir -p "$PREFIX" || fail "could not create $PREFIX"
[ -w "$PREFIX" ] || fail "$PREFIX is not writable. Try --prefix, or sudo."

changed=0
for _n in "$SHORT_NAME" "$LONG_NAME"; do
    _link="$PREFIX/$_n"
    if [ -L "$_link" ] && [ "$(readlink "$_link")" = "$TARGET" ]; then
        printf 'Already installed: %s\n' "$_link"
        continue
    fi
    if [ -e "$_link" ] && [ ! -L "$_link" ]; then
        printf 'Refusing to replace %s: it exists and is not a symlink.\n' "$_link" >&2
        printf 'Move it aside, or choose another name with --name.\n' >&2
        exit 1
    fi
    ln -sf "$TARGET" "$_link" || fail "could not link $_link"
    printf 'Installed %s -> %s\n' "$_link" "$TARGET"
    changed=$((changed + 1))
done

printf '\n'
if [ "$changed" -eq 0 ]; then
    printf 'Nothing changed. That is what an install looks like on a second run;\n'
    printf 'it is not the same as one that never worked.\n'
fi

if [ "$MODE" = "dev" ]; then
    printf 'This is a development install. The command is a link into\n'
    printf '%s, so it runs whatever that checkout holds,\n' "$ROOT"
    printf 'and a git pull changes it under you.\n'
    printf 'Drop --dev for an install that only changes when you say so.\n'
    printf '\n'
fi

# A link nobody can reach is worse than no link, so check rather than assume.
case ":$PATH:" in
    *":$PREFIX:"*) printf '%s is on your PATH.\n' "$PREFIX" ;;
    *)
        printf 'WARNING: %s is not on your PATH, so the command will not be found.\n' "$PREFIX"
        printf 'Add this to your shell rc file:\n'
        # shellcheck disable=SC2016  # literal rc-file text; the user pastes this
        printf '  export PATH="%s:$PATH"\n' "$PREFIX"
        ;;
esac

printf '\n'
printf 'Next:\n'
printf '  %s help\n' "$SHORT_NAME"
printf '  %s doctor\n' "$SHORT_NAME"
printf '  %s version --check\n' "$SHORT_NAME"
printf '\n'
printf 'Worth adding to your shell rc file:\n'
# shellcheck disable=SC2016  # literal rc-file text; the user pastes this
printf '  eval "$(%s guard)"      # refuse to run the agent unpinned\n' "$SHORT_NAME"
# shellcheck disable=SC2016  # literal rc-file text; the user pastes this
printf '  eval "$(%s completion bash)"  # tab-complete commands and profile names\n' "$SHORT_NAME"
# shellcheck disable=SC2016  # literal rc-file text; the user pastes this
printf '  PROMPT='"'"'$(%s which --label 2>/dev/null) %%~ %%# '"'"'\n' "$SHORT_NAME"
