#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# update-homebrew-formula.sh: point the Homebrew formula at a published
# release, and pin that release's sha256.
#
# The formula pins one tarball's sum, and Homebrew refuses to unpack anything
# that does not match it. That sum cannot exist before the release is built,
# so it used to be read out of SHA256SUMS and pasted in by hand afterwards.
# The work is mechanical, which is exactly why it is worth automating: it is
# easy to forget and easy to get subtly wrong. A new url with an old sum
# installs nothing at all, and a truncated sum fails in a way that reads like
# a corrupted download rather than like a typo.
#
# Two checks have to agree before anything is written:
#
#   1. The row for agent-profile-<version>.tar.gz in the release's own
#      SHA256SUMS, matched on the file name exactly. A missing row is a
#      failure, never an empty sum.
#   2. The tarball downloaded from the same release, hashed here. A swapped or
#      corrupted SHA256SUMS therefore cannot propagate into the formula: the
#      file it claims to describe is checked against it.
#
# And a third when cosign is installed: the Sigstore signature on both, which
# ties them to this repository's release workflow and to the tag.
# tools/install.sh makes the same check for the same reason, and says as
# loudly as this does when it cannot.
#
# url, version and sha256 are written together or not at all. A formula
# carrying a new url and an old sum is worse than one carrying neither,
# because it fails every install instead of installing the previous release.
#
# What this deliberately does not do is decide anything. It does not commit,
# it does not push, and it knows nothing about the tap repository. The
# workflow that runs it after a release opens a pull request, and a person
# reads that. The pin is worth having because somebody looked.
#
# Needs curl, awk, sed and shasum or sha256sum. Nothing else.
#
# Usage:
#   tools/update-homebrew-formula.sh 0.9.0             # rewrite the formula
#   tools/update-homebrew-formula.sh v0.9.0 --sum-only # print the sum only
#   tools/update-homebrew-formula.sh 0.9.0 --formula FILE

set -u

# Overridable so the test suite can serve a release from a local directory
# over a file:// URL, and so a fork can update its own formula. Whatever this
# names is both where the tarball is fetched from and what the formula's url
# is built from, so those two can never disagree. The url that gets written is
# printed before the script exits.
: "${AGENT_PROFILE_RELEASE_BASE_URL:=https://github.com/mmsge/agent-profile-manager/releases}"
: "${AGENT_PROFILE_COSIGN:=cosign}"
: "${AGENT_PROFILE_COSIGN_IDENTITY:=^https://github\.com/mmsge/agent-profile-manager/\.github/workflows/release\.yml@refs/tags/}"
: "${AGENT_PROFILE_COSIGN_ISSUER:=https://token.actions.githubusercontent.com}"

ME=$(basename "$0")
ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)

FORMULA="$ROOT/packaging/homebrew/agpin.rb"
VERSION=""
SUM_ONLY=""
WORKDIR=""

usage() {
    cat <<USAGE
usage: tools/update-homebrew-formula.sh VERSION [--formula FILE] [--sum-only]

  VERSION         the published release, with or without the leading v
  --formula FILE  the formula to rewrite (default: packaging/homebrew/agpin.rb)
  --sum-only      print the verified sum and write nothing

Reads the sum from the release's own SHA256SUMS, verifies it against the
tarball downloaded from that release, verifies the Sigstore signatures when
cosign is installed, and then sets url, version and sha256 together.
USAGE
}

say() {
    printf '%s\n' "$*"
}

fail() {
    printf '%s: %s\n' "$ME" "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || fail "required command '$1' not found"
}

cleanup() {
    [ -n "$WORKDIR" ] && rm -rf "$WORKDIR"
    WORKDIR=""
}

# sha256_of <file>: the hex digest, computed here rather than trusted. shasum
# is what a stock macOS has and sha256sum is what most Linux images have; the
# one that exists is the one used.
sha256_of() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    else
        sha256sum "$1" | awk '{ print $1 }'
    fi
}

# verify_signature <dir> <file>: check one Sigstore bundle, the same way
# install.sh checks it. Called only when cosign is really installed, so a
# non-zero result always means a failed check rather than a missing one.
verify_signature() {
    "$AGENT_PROFILE_COSIGN" verify-blob \
        --bundle "$1/$2.sigstore" \
        --certificate-identity-regexp "$AGENT_PROFILE_COSIGN_IDENTITY" \
        --certificate-oidc-issuer "$AGENT_PROFILE_COSIGN_ISSUER" \
        "$1/$2" >/dev/null 2>&1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --formula)  shift; [ $# -gt 0 ] || fail "--formula needs a value"; FORMULA="$1" ;;
        --sum-only) SUM_ONLY=1 ;;
        -h|--help)  usage; exit 0 ;;
        -*)         printf 'unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
        *)
            [ -z "$VERSION" ] || { printf 'give one version, not two\n' >&2; usage >&2; exit 2; }
            VERSION="$1"
            ;;
    esac
    shift
done

[ -n "$VERSION" ] || { usage >&2; exit 2; }

# The version reaches a URL and a file name, and on the automated path it came
# from a release payload rather than from a person. Refuse anything that is
# not a version, so a surprising tag cannot become a surprising path.
VERSION="${VERSION#v}"
case "$VERSION" in
    ""|*[!0-9.]*) fail "'$VERSION' is not a version like 0.9.0" ;;
esac

need curl
need awk
need sed
if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    fail "neither shasum nor sha256sum is installed, so nothing could be verified"
fi

if [ -z "$SUM_ONLY" ] && [ ! -f "$FORMULA" ]; then
    fail "no formula at $FORMULA"
fi

TAG="v$VERSION"
TARBALL="agent-profile-$VERSION.tar.gz"
BASE="$AGENT_PROFILE_RELEASE_BASE_URL/download/$TAG"
URL="$BASE/$TARBALL"

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-formula.XXXXXX") \
    || fail "could not make a temporary directory"
trap cleanup EXIT INT TERM

curl -fsSL -o "$WORKDIR/SHA256SUMS" "$BASE/SHA256SUMS" \
    || fail "could not download $BASE/SHA256SUMS"

# Match the name exactly. A substring match would happily take the row for
# agent-profile-0.9.0.tar.gz.sigstore, or for a neighbouring version, and pin
# the sum of a file nobody is installing. The leading asterisk is what the
# binary-mode form of this format writes, so strip it before comparing.
SUM=$(awk -v want="$TARBALL" '
    { name = $2; sub(/^\*/, "", name); if (name == want) print $1 }
' "$WORKDIR/SHA256SUMS")

if [ -z "$SUM" ]; then
    fail "SHA256SUMS for $TAG has no row for $TARBALL, so there is no sum to pin.
The release is either incomplete or not the one you meant. Nothing was written."
fi
if [ "$(printf '%s\n' "$SUM" | wc -l | tr -d ' ')" != "1" ]; then
    fail "SHA256SUMS for $TAG has more than one row for $TARBALL.
Refusing to guess which of them describes the file. Nothing was written."
fi
# A partial sum is the failure worth naming separately: it looks like a sum,
# it survives a careless glance, and Homebrew then rejects every download
# against it.
case "$SUM" in
    *[!0-9a-f]*) fail "the sum for $TARBALL in SHA256SUMS is not lowercase hex: '$SUM'" ;;
esac
if [ "${#SUM}" -ne 64 ]; then
    fail "the sum for $TARBALL in SHA256SUMS is ${#SUM} characters, not 64: '$SUM'"
fi

curl -fsSL -o "$WORKDIR/$TARBALL" "$URL" || fail "could not download $URL"

ACTUAL=$(sha256_of "$WORKDIR/$TARBALL")
if [ "$ACTUAL" != "$SUM" ]; then
    fail "the tarball published as $TARBALL does not match the sum published beside it.
SHA256SUMS says $SUM
the download is $ACTUAL
Nothing was written. Do not pin either number until you know why."
fi

if command -v "$AGENT_PROFILE_COSIGN" >/dev/null 2>&1; then
    curl -fsSL -o "$WORKDIR/$TARBALL.sigstore" "$URL.sigstore" \
        || fail "cosign is installed but $TAG publishes no signature bundle for $TARBALL."
    curl -fsSL -o "$WORKDIR/SHA256SUMS.sigstore" "$BASE/SHA256SUMS.sigstore" \
        || fail "cosign is installed but $TAG publishes no signature bundle for SHA256SUMS."
    verify_signature "$WORKDIR" "$TARBALL" \
        || fail "the Sigstore signature on $TARBALL did not verify.
Expected an identity matching $AGENT_PROFILE_COSIGN_IDENTITY
issued by $AGENT_PROFILE_COSIGN_ISSUER. Nothing was written."
    verify_signature "$WORKDIR" "SHA256SUMS" \
        || fail "the Sigstore signature on SHA256SUMS did not verify. Nothing was written."
    SIGNED="verified: built by the release workflow, from tag $TAG"
else
    SIGNED="not checked: cosign is not installed"
fi

if [ -n "$SUM_ONLY" ]; then
    say "$SUM"
    exit 0
fi

# Rewritten with awk rather than sed so the new values stay data the whole way
# through: a url full of slashes needs no escaping, and a replacement cannot
# be read as part of a pattern. The END block is the check that the formula
# still has the shape this expects, so a renamed or duplicated field fails
# here rather than producing a file missing one of the three.
awk -v url="$URL" -v ver="$VERSION" -v sum="$SUM" '
    /^  url "/     { print "  url \"" url "\""; urls++; next }
    /^  version "/ { print "  version \"" ver "\""; vers++; next }
    /^  sha256 "/  { print "  sha256 \"" sum "\""; sums++; next }
                   { print }
    END {
        if (urls != 1 || vers != 1 || sums != 1) {
            printf "found %d url, %d version and %d sha256 lines; expected one of each\n", \
                urls, vers, sums > "/dev/stderr"
            exit 3
        }
    }
' "$FORMULA" > "$WORKDIR/agpin.rb" \
    || fail "$FORMULA is not shaped the way this expects, so it was left alone"

# Read back what was written rather than trusting that the write went in.
# Cheap, and it is the one assertion that covers the whole job.
for _check in "  url \"$URL\"" "  version \"$VERSION\"" "  sha256 \"$SUM\""; do
    grep -qxF "$_check" "$WORKDIR/agpin.rb" \
        || fail "the rewritten formula does not contain the line: $_check"
done

cat "$WORKDIR/agpin.rb" > "$FORMULA" || fail "could not write $FORMULA"

say "Release   $TAG"
say "Tarball   $TARBALL"
say "url       $URL"
say "version   $VERSION"
say "sha256    $SUM"
say "Checked   the row in the release's own SHA256SUMS, and that sum against"
say "          the tarball downloaded from the same release"
say "Signature $SIGNED"
say "Formula   $FORMULA"
