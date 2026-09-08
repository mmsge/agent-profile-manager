#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install.sh: put agent-profile on your PATH.
#
# Symlinks rather than copies, so a git pull updates the installed command and
# there is never a second copy to drift. Idempotent, and it says which of
# "installed" and "already installed" happened, because those must not look
# the same.

set -u

SHORT_NAME="agpin"
LONG_NAME="agent-profile"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET="$ROOT/bin/$LONG_NAME"

PREFIX=""
UNINSTALL=""

usage() {
    cat <<USAGE
usage: tools/install.sh [--prefix DIR] [--name NAME] [--uninstall]

  --prefix DIR   where to put the links (default: the first writable of
                 ~/.local/bin, /usr/local/bin)
  --name NAME    the short command name (default: $SHORT_NAME)
  --uninstall    remove links this script created, and nothing else

Both '$SHORT_NAME' and '$LONG_NAME' are linked, so scripts and muscle memory
can use either. The tool names itself by whichever you invoke.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)    shift; [ $# -gt 0 ] || { echo "--prefix needs a value" >&2; exit 1; }; PREFIX="$1" ;;
        --name)      shift; [ $# -gt 0 ] || { echo "--name needs a value" >&2; exit 1; }; SHORT_NAME="$1" ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "unknown option '$1'" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

case "$SHORT_NAME" in
    ""|*[!A-Za-z0-9_-]*) echo "invalid --name '$SHORT_NAME'" >&2; exit 1 ;;
esac

[ -x "$TARGET" ] || { echo "cannot find an executable at $TARGET" >&2; exit 1; }

# Pick a prefix. ~/.local/bin first: no sudo, and it is the conventional place
# for a single user's tools.
if [ -z "$PREFIX" ]; then
    for _cand in "$HOME/.local/bin" "/usr/local/bin"; do
        if [ -d "$_cand" ] && [ -w "$_cand" ]; then PREFIX="$_cand"; break; fi
    done
    [ -n "$PREFIX" ] || PREFIX="$HOME/.local/bin"
fi

if [ -n "$UNINSTALL" ]; then
    removed=0
    for _n in "$SHORT_NAME" "$LONG_NAME"; do
        _link="$PREFIX/$_n"
        # Only remove a link that points at this checkout. Never touch anything
        # else that happens to share the name.
        if [ -L "$_link" ] && [ "$(readlink "$_link")" = "$TARGET" ]; then
            rm -f "$_link" && printf 'Removed %s\n' "$_link"
            removed=$((removed + 1))
        elif [ -e "$_link" ]; then
            printf 'Left %s alone: it is not a link to this checkout.\n' "$_link"
        fi
    done
    [ "$removed" -gt 0 ] || printf 'Nothing of ours was installed in %s.\n' "$PREFIX"
    exit 0
fi

mkdir -p "$PREFIX" || { echo "could not create $PREFIX" >&2; exit 1; }
[ -w "$PREFIX" ] || { echo "$PREFIX is not writable. Try --prefix, or sudo." >&2; exit 1; }

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
    ln -sf "$TARGET" "$_link" || { echo "could not link $_link" >&2; exit 1; }
    printf 'Installed %s -> %s\n' "$_link" "$TARGET"
    changed=$((changed + 1))
done

printf '\n'
if [ "$changed" -eq 0 ]; then
    printf 'Nothing changed. That is what an install looks like on a second run;\n'
    printf 'it is not the same as one that never worked.\n'
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
printf '\n'
printf 'Worth adding to your shell rc file:\n'
# shellcheck disable=SC2016  # literal rc-file text; the user pastes this
printf '  eval "$(%s guard)"      # refuse to run the agent unpinned\n' "$SHORT_NAME"
# shellcheck disable=SC2016  # literal rc-file text; the user pastes this
printf '  PROMPT='"'"'$(%s which --label 2>/dev/null) %%~ %%# '"'"'\n' "$SHORT_NAME"
