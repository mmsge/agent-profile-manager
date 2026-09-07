#!/bin/bash
#
# probe-claude-desktop.sh: answer the questions agent-profile cannot answer
# from documentation, on a real Mac.
#
# Run this on macOS, then paste the whole output back and update docs/FACTS.md.
# Re-run it after a Claude Desktop update, and note that "after an update" is
# per profile rather than per machine: each desktop profile carries its own
# copy of Claude Code and updates on its own schedule (F17).
#
# Safety: this script creates a throwaway config root and app data directory
# under a temporary directory and removes them at the end. It never touches a
# real config root, never reads credential content, and never calls security
# with -g.

set -u

PROBE_VERSION="2"

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
    say "  Compare inode and version against the previous run."
    say ""
    say "  This matters less than it used to. Launchers now run open -n -a on the"
    say "  bundle rather than a binary inside it, so nothing hard-codes an"
    say "  executable path. The reading is kept so a bundle that moves is noticed."
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
# F13: does this open(1) still take --env?
#
# The entire desktop half rests on this one flag. Cheap to read, and worth
# reading first, because a NO here invalidates everything below it.
# ---------------------------------------------------------------------------

head2 "F13  open --env"

if open --help 2>&1 | grep -q -- '--env'; then
    kv "open --env" "supported"
    open --help 2>&1 | grep -A2 -- '--env' | sed 's/^/    /'
else
    kv "open --env" "NOT SUPPORTED"
    say "  Every generated applet on this machine launches unpinned. Stop and"
    say "  fix this before trusting any of them: agent-profile verify will say"
    say "  the same thing."
fi

# ---------------------------------------------------------------------------
# F01: does the desktop app's embedded Claude Code honour CLAUDE_CONFIG_DIR?
#
# Answered yes during the Tide and Highsoft migrations. This is a
# re-confirmation after an update, not an open question, so it launches the
# way the tool actually launches: open --env, never the binary directly.
# Running the binary from a shell kills it when the shell exits (F15).
# ---------------------------------------------------------------------------

head2 "F01  Does the desktop app still honour CLAUDE_CONFIG_DIR?"

if [ ! -d "$APP" ]; then
    say "  SKIPPED: the app bundle was not found, so nothing could be launched."
else
    BEFORE=$(find "$PROBE_ROOT" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    say "  Launching with open --env, which is exactly how agent-profile desktop"
    say "  and every applet it generates launch the app."
    say ""
    say "  DO THIS, or the result means nothing:"
    say "    1. When the app opens, click the Code tab."
    say "    2. Start one local session and let it load."
    say "    3. Come back here."
    say ""
    say "  The embedded Claude Code writes nothing until a session actually runs,"
    say "  so quitting early looks identical to the app ignoring the variable."
    say ""

    open -n -a "$APP" \
        --env "CLAUDE_CONFIG_DIR=$PROBE_ROOT" \
        --args --user-data-dir="$PROBE_APPDATA" >/dev/null 2>&1

    say "  Launched. Waiting up to 300s, or until the root changes."

    WAITED=0
    while [ "$WAITED" -lt 300 ]; do
        sleep 5
        WAITED=$((WAITED + 5))
        [ "$INTERRUPTED" = "1" ] && break
        NOW=$(find "$PROBE_ROOT" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
        [ "$NOW" -gt "$BEFORE" ] && break
    done

    AFTER=$(find "$PROBE_ROOT" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    APPDATA_ENTRIES=$(find "$PROBE_APPDATA" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')

    say ""
    kv "entries in root before" "$BEFORE"
    kv "entries in root after" "$AFTER"
    kv "entries in app data dir" "$APPDATA_ENTRIES"
    say ""

    if [ "$AFTER" -gt "$BEFORE" ]; then
        say "  ANSWER: YES, still. The embedded Claude Code wrote to the pinned root."
        say "  What appeared:"
        find "$PROBE_ROOT" -mindepth 1 -maxdepth 2 | sed 's/^/    /'
    else
        # Nothing written is only a NO if a session really ran. Ask rather than
        # guess: a false NO here would reopen a question that is settled and
        # send the desktop design back down a road that does not work.
        RAN=""
        if [ -r /dev/tty ]; then
            printf '  Did you start a Code session in the app before coming back? [y/N] ' > /dev/tty
            read -r RAN < /dev/tty
        fi

        case "$RAN" in
            [yY]*)
                if [ "$APPDATA_ENTRIES" -gt 0 ]; then
                    say ""
                    say "  ANSWER: NO. This is a REGRESSION against docs/FACTS.md F01."
                    say "  A Code session ran, --user-data-dir populated its directory, so"
                    say "  the app started fine and no longer takes CLAUDE_CONFIG_DIR from"
                    say "  its process environment."
                    say ""
                    say "  Every applet on this machine is now decorative. Say so in F01"
                    say "  before anyone trusts one, and reopen F02: the app's local"
                    say "  environment editor becomes the route again."
                    say "    environment dropdown -> hover Local -> gear icon"
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

    say ""
    say "  The same check, against a real profile rather than this throwaway root:"
    say "    agent-profile desktop <name>   # start a Code session, then"
    # shellcheck disable=SC2016  # literal help text; the user types this
    say '    find "$HOME"/.claude* -name "*.jsonl" -mmin -3'
fi

# ---------------------------------------------------------------------------
# F17: each desktop profile carries its own Claude Code
# ---------------------------------------------------------------------------

head2 "F17  Claude Code version per profile"

kv "CLI on PATH" "$(command -v claude >/dev/null 2>&1 && claude --version 2>/dev/null | head -1 || echo 'not installed')"

FOUND_ANY=""
for D in "$HOME/Library/Application Support/"Claude*; do
    [ -d "$D/claude-code" ] || continue
    FOUND_ANY=1
    kv "$(basename "$D")" \
        "$(find "$D/claude-code" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null \
            | sort | tr '\n' ' ')"
done
[ -n "$FOUND_ANY" ] || say "  No app profile has downloaded a Claude Code yet."
say ""
say "  These update independently of each other and of the CLI, so there is no"
say "  single agent version for this machine. An assumption can break for one"
say "  profile while holding for the rest."

# ---------------------------------------------------------------------------
# F03: Keychain naming for a non-default config root
#
# Metadata only. Never dump_keychain -g, never read a secret.
# ---------------------------------------------------------------------------

head2 "F03  Keychain entry naming"

# F03 was established in a session that ran in parallel with the migrations,
# and the migration notes still list the naming as unknown. Rather than pick a
# winner between two records, re-derive the expected name for every registered
# root and say whether the Keychain agrees. That reconciles them on the machine
# where both claims were made.
say "  Expected entry per registered root, and whether it is really there."
say "  Existence only: find-generic-password without -g, output discarded."
say ""

REG="$HOME/.config/agent-profiles"
CHECKED=0
for CONF in "$REG"/*.conf; do
    [ -f "$CONF" ] || continue
    NAME=$(basename "$CONF" .conf)
    ROOT=$(sed -n 's/^root=//p' "$CONF" | head -1)
    [ -n "$ROOT" ] || continue
    CHECKED=$((CHECKED + 1))
    HASH=$(python3 -c '
import hashlib, sys, unicodedata
print(hashlib.sha256(unicodedata.normalize("NFC", sys.argv[1]).encode()).hexdigest()[:8])
' "$ROOT")
    SVC="Claude Code-credentials-$HASH"
    if security find-generic-password -s "$SVC" -a "${USER:-}" >/dev/null 2>&1; then
        kv "$NAME" "$SVC  PRESENT"
    else
        kv "$NAME" "$SVC  absent (this root may simply not be signed in)"
    fi
done
[ "$CHECKED" -gt 0 ] || say "  No profiles registered, so nothing could be re-derived."

say ""
say "  A root that IS signed in but shows absent means the naming in F03 has"
say "  changed, and doctor's D05 is reporting false findings on every profile."
say ""
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
    say "  A Mach-O binary here confirms F04: LaunchServices launches it with no"
    say "  environment from any shell, and a URL has nowhere to carry one, so a"
    say "  claude-cli:// link opens against the default root whatever this tool"
    say "  has configured. doctor reports it as D09. There is no fix from here."
    say ""
    say "  Note this is not an argument against open(1). open --env injects a"
    say "  variable explicitly (F13), which is why the launchers use it."
else
    kv "bundle" "not present at $HANDLER"
fi

head2 "Done"
say "Paste this whole output back, and update docs/FACTS.md from it."
