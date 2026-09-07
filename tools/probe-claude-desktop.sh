#!/bin/bash
#
# probe-claude-desktop.sh: answer the questions agent-profile cannot answer
# from documentation, on a real Mac.
#
# Run this on macOS, then paste the whole output back and update docs/FACTS.md.
# Re-run it after a Claude Desktop update.
#
# Safety: this script creates a throwaway config root and app data directory
# under a temporary directory and removes them at the end. It never touches a
# real config root, never reads credential content, and never calls security
# with -g.

set -u

PROBE_VERSION="1"

say()  { printf '%s\n' "$*"; }
head2() { printf '\n== %s ==\n' "$*"; }
kv()   { printf '  %-28s %s\n' "$1" "$2"; }

if [ "$(uname -s)" != "Darwin" ]; then
    say "This probe only means anything on macOS. Nothing was run."
    exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-probe.XXXXXX") || exit 1
PROBE_ROOT="$TMP/root"
PROBE_APPDATA="$TMP/appdata"
mkdir -p "$PROBE_ROOT" "$PROBE_APPDATA"
chmod 700 "$PROBE_ROOT"

cleanup() {
    rm -rf "$TMP"
}
trap cleanup EXIT
trap 'INTERRUPTED=1' INT
INTERRUPTED=0

say "agent-profile desktop probe, format $PROBE_VERSION"
say "date         $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "macOS        $(sw_vers -productVersion 2>/dev/null)"
say "throwaway    $TMP"

# ---------------------------------------------------------------------------
# F05: where the app binary is, and whether an update moved it
# ---------------------------------------------------------------------------

head2 "F05  Claude Desktop binary"

APP="/Applications/Claude.app"
BIN="$APP/Contents/MacOS/Claude"

if [ -d "$APP" ]; then
    kv "bundle" "$APP"
    kv "CFBundleShortVersionString" \
        "$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)"
    kv "CFBundleVersion" \
        "$(defaults read "$APP/Contents/Info.plist" CFBundleVersion 2>/dev/null)"
    kv "CFBundleExecutable" \
        "$(defaults read "$APP/Contents/Info.plist" CFBundleExecutable 2>/dev/null)"
    if [ -x "$BIN" ]; then
        kv "binary" "$BIN"
        kv "inode" "$(stat -f '%i' "$BIN" 2>/dev/null)"
        kv "size" "$(stat -f '%z' "$BIN" 2>/dev/null)"
    else
        kv "binary" "NOT FOUND at the expected path"
        say "  Look for it under $APP/Contents/MacOS:"
        # shellcheck disable=SC2012  # a human-readable listing with modes is the point
        ls -la "$APP/Contents/MacOS" 2>/dev/null | sed 's/^/    /'
    fi
    say ""
    say "  Compare inode and version against the previous run. If the path moved,"
    say "  generated .app bundles need a version-independent way to find it."
else
    kv "bundle" "NOT FOUND at $APP"
    say "  Searching for other copies:"
    mdfind -name 'Claude.app' 2>/dev/null | head -5 | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# F10: does the state file move inside a pinned root?
# ---------------------------------------------------------------------------

head2 "F10  Does .claude.json move inside a pinned root?"

if command -v claude >/dev/null 2>&1; then
    kv "claude version" "$(claude --version 2>/dev/null | head -1)"
    CLAUDE_CONFIG_DIR="$PROBE_ROOT" claude --version >/dev/null 2>&1
    CLAUDE_CONFIG_DIR="$PROBE_ROOT" claude mcp list >/dev/null 2>&1
    say "  After running the CLI pinned to the throwaway root:"
    if [ -n "$(ls -A "$PROBE_ROOT" 2>/dev/null)" ]; then
        # shellcheck disable=SC2012  # a human-readable listing with modes is the point
        ls -la "$PROBE_ROOT" | sed 's/^/    /'
    else
        say "    (root is still empty; the CLI may not write on these commands)"
    fi
    if [ -f "$PROBE_ROOT/.claude.json" ]; then
        say "  ANSWER: yes, .claude.json is written inside the pinned root."
    else
        say "  ANSWER: inconclusive from these commands. Run an interactive session"
        say "          pinned to the root and re-check, or trust the direct"
        say "          observation of two .claude.json files on this machine."
    fi
else
    kv "claude" "not on PATH; skipped"
fi

# ---------------------------------------------------------------------------
# F01: does the desktop app's embedded Claude Code honour CLAUDE_CONFIG_DIR?
#
# This is the gating question for the whole desktop half.
# ---------------------------------------------------------------------------

head2 "F01  Does the desktop app honour CLAUDE_CONFIG_DIR?"

if [ ! -x "$BIN" ]; then
    say "  SKIPPED: the app binary was not found, so nothing could be launched."
else
    BEFORE=$(find "$PROBE_ROOT" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    say "  Launching the app binary directly (not via open, which dispatches"
    say "  through launchd and would drop the environment entirely)."
    say ""
    say "  DO THIS, or the result means nothing:"
    say "    1. When the app opens, click the Code tab."
    say "    2. Start one local session and let it load."
    say "    3. Come back here."
    say ""
    say "  The embedded Claude Code writes nothing until a session actually runs,"
    say "  so quitting early looks identical to the app ignoring the variable."
    say ""

    CLAUDE_CONFIG_DIR="$PROBE_ROOT" "$BIN" --user-data-dir="$PROBE_APPDATA" >/dev/null 2>&1 &
    PROBE_PID=$!
    say "  Launched as pid $PROBE_PID. Waiting up to 300s, or until the root changes."

    WAITED=0
    while [ "$WAITED" -lt 300 ]; do
        sleep 5
        WAITED=$((WAITED + 5))
        [ "$INTERRUPTED" = "1" ] && break
        NOW=$(find "$PROBE_ROOT" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
        [ "$NOW" -gt "$BEFORE" ] && break
        kill -0 "$PROBE_PID" 2>/dev/null || break
    done

    AFTER=$(find "$PROBE_ROOT" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    APPDATA_ENTRIES=$(find "$PROBE_APPDATA" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')

    say ""
    kv "entries in root before" "$BEFORE"
    kv "entries in root after" "$AFTER"
    kv "entries in app data dir" "$APPDATA_ENTRIES"
    say ""

    if [ "$AFTER" -gt "$BEFORE" ]; then
        say "  ANSWER: YES. The app's embedded Claude Code wrote to the pinned root."
        say "  What appeared:"
        find "$PROBE_ROOT" -mindepth 1 -maxdepth 2 | sed 's/^/    /'
        kill "$PROBE_PID" 2>/dev/null
    else
        # Nothing was written. That is only a NO if a session really ran, so
        # ask rather than guess. Reporting a false NO here would send the whole
        # desktop design down the wrong road.
        RAN=""
        if [ -r /dev/tty ]; then
            printf '  Did you start a Code session in the app before coming back? [y/N] ' > /dev/tty
            read -r RAN < /dev/tty
        fi
        kill "$PROBE_PID" 2>/dev/null

        case "$RAN" in
            [yY]*)
                if [ "$APPDATA_ENTRIES" -gt 0 ]; then
                    say ""
                    say "  ANSWER: NO. A Code session ran and the pinned root stayed empty,"
                    say "  while --user-data-dir populated its directory, so the app started"
                    say "  fine and simply does not take CLAUDE_CONFIG_DIR from its process"
                    say "  environment."
                    say ""
                    say "  F02 is now the route. In the app, with this app data dir:"
                    say "    environment dropdown -> hover Local -> gear icon"
                    say "    set CLAUDE_CONFIG_DIR=$PROBE_ROOT"
                    say "  then re-run this probe and answer y again."
                else
                    say ""
                    say "  ANSWER: INCONCLUSIVE. The app data dir is empty too, so the app"
                    say "  never really started and this run says nothing about F01."
                fi
                ;;
            *)
                say ""
                say "  ANSWER: INCONCLUSIVE. No Code session ran, and the embedded Claude"
                say "  Code writes nothing until one does. This is not evidence either way."
                say "  Re-run and start a session before returning."
                ;;
        esac
    fi
fi

# ---------------------------------------------------------------------------
# F03: Keychain naming for a non-default config root
#
# Metadata only. Never dump_keychain -g, never read a secret.
# ---------------------------------------------------------------------------

head2 "F03  Keychain entry naming"

say "  Entries whose service or account mentions Claude (metadata only, no"
say "  secrets are read):"
say ""
security dump-keychain 2>/dev/null \
    | grep -E '"(svce|acct|desc|labl)"' \
    | grep -i claude \
    | sort -u \
    | sed 's/^/    /' \
    | head -40

say ""
say "  Look for an entry whose service or account embeds a config root path."
say "  That naming is what doctor's D05 needs in order to check the Keychain"
say "  rather than only checking for a .credentials.json file."

# ---------------------------------------------------------------------------
# F04: the Claude Code URL handler
# ---------------------------------------------------------------------------

head2 "F04  Claude Code URL handler"

HANDLER="$HOME/Applications/Claude Code URL Handler.app"
if [ -d "$HANDLER" ]; then
    kv "bundle" "$HANDLER"
    kv "CFBundleIdentifier" \
        "$(defaults read "$HANDLER/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)"
    say "  URL schemes it claims:"
    plutil -p "$HANDLER/Contents/Info.plist" 2>/dev/null \
        | grep -A6 CFBundleURLTypes | sed 's/^/    /'
    say "  What it executes:"
    for f in "$HANDLER/Contents/MacOS"/* "$HANDLER/Contents/Resources/script"; do
        [ -f "$f" ] || continue
        kv "file" "$f"
        file "$f" | sed 's/^/      /'
        if file "$f" | grep -qi text; then
            sed 's/^/      /' "$f" | head -30
        fi
    done
    say ""
    say "  If it cannot carry a config root, claude-cli:// links are a leak path"
    say "  and doctor should grow a rule for them."
else
    kv "bundle" "not present at $HANDLER"
fi

head2 "Done"
say "Paste this whole output back, and update docs/FACTS.md from it."
