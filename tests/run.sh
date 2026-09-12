#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317,SC2329  # helpers are called from the sourced case files
# shellcheck disable=SC2016  # fake_keychain generates script text; it must not expand here
#
# tests/run.sh: dependency-free test harness.
#
# No bats, no brew, nothing but bash and coreutils, so it runs on a stock macOS
# under bash 3.2 exactly as CI runs it.
#
# Every test gets its own throwaway HOME. Nothing here ever touches a real
# config root: the script resolves every path it uses from HOME or from an
# AGENT_PROFILE_* variable, and the harness redirects all of them.

set -u


ROOT=$(cd "$(dirname "$0")/.." && pwd)

# Run the script under the same interpreter this harness is running under,
# rather than under its shebang. Without this the bash 3.2 CI job would run the
# harness under 3.2 but every agent-profile call under whatever /bin/bash is,
# and would prove nothing about the script itself.
AP_SHIM_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-shim.XXXXXX")
AP="$AP_SHIM_DIR/agent-profile"
{
    printf '#!/bin/sh\n'
    printf 'exec %s %s "$@"\n' "${BASH:-/bin/bash}" "$ROOT/bin/agent-profile"
} > "$AP"
chmod +x "$AP"
trap 'rm -rf "$AP_SHIM_DIR"' EXIT INT TERM

# Pin the platform so the suite never consults the host's real Keychain and
# gives the same answer on every machine. Without this the macOS-only rules
# query the running machine's credentials, so the same commit passes on Linux
# and fails on a Mac. 60-credentials opts back into the macOS paths
# deliberately, against a stand-in security(1).
AGENT_PROFILE_PLATFORM=test-not-darwin
export AGENT_PROFILE_PLATFORM

TESTS_RUN=0
TESTS_FAILED=0
CURRENT=""

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL  %s\n' "$CURRENT"
    for _f in "$@"; do printf '        %s\n' "$_f"; done
}

pass() {
    printf '  ok    %s\n' "$CURRENT"
}

# assert_status <expected> <actual> [context]
assert_status() {
    if [ "$1" != "$2" ]; then
        fail "expected exit $1, got $2" "${3:-}"
        return 1
    fi
    return 0
}

# assert_contains <haystack> <needle>
assert_contains() {
    case "$1" in
        *"$2"*) return 0 ;;
        *) fail "expected output to contain: $2" "got: $1"; return 1 ;;
    esac
}

# assert_not_contains <haystack> <needle>
assert_not_contains() {
    case "$1" in
        *"$2"*) fail "expected output NOT to contain: $2" "got: $1"; return 1 ;;
        *) return 0 ;;
    esac
}

# assert_equals <expected> <actual>
assert_equals() {
    if [ "$1" != "$2" ]; then
        fail "expected: $1" "got:      $2"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# new_home: a fresh throwaway HOME, echoed. Registered for cleanup.
new_home() {
    _nh=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-test.XXXXXX")
    # TMPDIR ends in a slash on macOS, so the result contains "//". That is a
    # genuinely different path string, and doctor is right to flag it, so give
    # the fixtures a canonical home rather than teaching the rule to ignore it.
    (cd "$_nh" && pwd)
}

# file_mode <path>: portable. GNU stat -f succeeds and reports the filesystem
# rather than failing, so check the shape of the answer rather than the status.
file_mode() {
    _fm=$(stat -f '%Lp' "$1" 2>/dev/null)
    case "$_fm" in
        ''|*[!0-9]*) _fm=$(stat -c '%a' "$1" 2>/dev/null) ;;
    esac
    printf '%s\n' "$_fm"
}

# fixture_transcript <root> <encoded-dir> <cwd>
fixture_transcript() {
    mkdir -p "$1/projects/$2"
    printf '{"type":"user","cwd":"%s","version":"2.1.263","sessionId":"s1"}\n' "$3" \
        > "$1/projects/$2/s1.jsonl"
}

# fixture_transcript_nocwd <root> <encoded-dir>: simulates a future version
# that stopped recording cwd, which is what would silently break doctor's D03.
fixture_transcript_nocwd() {
    mkdir -p "$1/projects/$2"
    printf '{"type":"user","version":"9.9.9","sessionId":"s1"}\n' > "$1/projects/$2/s1.jsonl"
}

# fake_keychain <bindir> <service>...: a stand-in security(1) that knows only
# the services named. Lets the macOS-only audit rules run on any platform,
# paired with AGENT_PROFILE_PLATFORM=Darwin.
fake_keychain() {
    _fk_dir="$1"; shift
    mkdir -p "$_fk_dir"
    {
        printf '#!/bin/sh\n'
        printf 'KNOWN=$(cat <<KCEOF\n'
        for _fk_svc in ${1+"$@"}; do printf '%s\n' "$_fk_svc"; done
        printf 'KCEOF\n)\n'
        printf 'case "$1" in\n'
        printf '  find-generic-password) shift; svc=""\n'
        printf '    while [ $# -gt 0 ]; do [ "$1" = "-s" ] && { shift; svc="$1"; }; shift; done\n'
        printf '    printf "%%s\\n" "$KNOWN" | grep -qxF "$svc" && exit 0 || exit 44 ;;\n'
        printf '  dump-keychain) printf "%%s\\n" "$KNOWN" | sed \x27s/^/    "svce"<blob>="/; s/$/"/\x27 ;;\n'
        printf 'esac\n'
    } > "$_fk_dir/security"
    chmod +x "$_fk_dir/security"
}

# cred_service_for <root>: the Keychain service name the agent uses for a root.
cred_service_for() {
    printf 'Claude Code-credentials-%s\n' "$(python3 -c '
import hashlib, sys, unicodedata
print(hashlib.sha256(unicodedata.normalize("NFC", sys.argv[1]).encode()).hexdigest()[:8])
' "$1")"
}

# reg_applet_of <name>: the applet recorded in a profile's registry entry.
reg_applet_of() {
    sed -n 's/^applet=//p' "$HOME/.config/agent-profiles/$1.conf" 2>/dev/null | head -1
}

# reg_root_of <name>: the root recorded in a profile's registry entry.
reg_root_of() {
    sed -n 's/^root=//p' "$HOME/.config/agent-profiles/$1.conf" | head -1
}

# fixture_account <root> <email> <org>
fixture_account() {
    printf '{"oauthAccount":{"emailAddress":"%s","organizationUuid":"%s"}}\n' "$2" "$3" \
        > "$1/.claude.json"
}

# fake_osa <bindir>: stand-in osacompile and osadecompile.
#
# osacompile stores the -e lines verbatim; osadecompile prints them back. That
# is enough to exercise the round trip the applet machinery actually depends
# on, which is that a launch line written into a bundle can be read back out.
fake_osa() {
    mkdir -p "$1"
    cat > "$1/osacompile" <<'OSAEOF'
#!/bin/sh
lines=""; out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -e) shift; lines="$lines$1
" ;;
        -o) shift; out="$1" ;;
    esac
    shift
done
[ -n "$out" ] || exit 1
mkdir -p "$out/Contents/Resources/Scripts" || exit 1
printf '%s' "$lines" > "$out/Contents/Resources/Scripts/main.scpt"
OSAEOF
    cat > "$1/osadecompile" <<'OSDEOF'
#!/bin/sh
[ -f "$1" ] || exit 1
cat "$1"
OSDEOF
    chmod +x "$1/osacompile" "$1/osadecompile"
}

# fake_open <bindir> <env|noenv>: an open(1) that does or does not take --env.
# The "noenv" form is how the suite exercises the guard that refuses to launch
# an app it cannot pin.
fake_open() {
    mkdir -p "$1"
    if [ "$2" = "env" ]; then
        cat > "$1/open" <<'OPENEOF'
#!/bin/sh
[ "$1" = "--help" ] && { echo "--env VAR      Add an enviroment variable to the launched process"; exit 0; }
echo "open: $*"
OPENEOF
    else
        cat > "$1/open" <<'OPENEOF'
#!/bin/sh
[ "$1" = "--help" ] && { echo "usage: open [-e] [-t] [-f] [-W] file"; exit 0; }
echo "open: $*"
OPENEOF
    fi
    chmod +x "$1/open"
}

# fake_defaults <bindir> <mode> [app-bundle]: a stand-in defaults(1) that
# answers `read com.apple.dock persistent-apps` and nothing else.
#
# The output is the shape the real one prints: an old-style plist, one
# dictionary per Dock tile, with the application's path in a percent-encoded
# `file://` URL under `_CFURLString`. One tile always carries a space in its
# path, so the percent-decoding is exercised rather than assumed.
#
# Modes:
#   app        the real Claude.app is pinned, which is what D17 reports
#   applets    only the applets are pinned, which is the healthy machine
#   empty      an empty Dock
#   fails      defaults exits non-zero, as it does when the key is absent
#
# The third argument is the bundle the "app" mode pins, so a case can pin one
# whose path only survives the round trip if the URL is really decoded. It
# defaults to the fixture bundle the desktop cases use.
fake_defaults() {
    _fd_dir="$1"
    _fd_mode="$2"
    _fd_bundle="${3:-$HOME/Claude.app}"
    mkdir -p "$_fd_dir"
    {
        printf '#!/bin/sh\n'
        printf '[ "$1" = "read" ] || exit 1\n'
        printf '[ "$2" = "com.apple.dock" ] || exit 1\n'
        printf '[ "$3" = "persistent-apps" ] || exit 1\n'
        if [ "$_fd_mode" = "fails" ]; then
            printf 'echo "Domain com.apple.dock does not exist" >&2\n'
            printf 'exit 1\n'
        else
            printf "cat <<'DOCKEOF'\n"
            printf '(\n'
            if [ "$_fd_mode" != "empty" ]; then
                printf '        {\n'
                printf '        GUID = 1105742130;\n'
                printf '        "tile-data" =         {\n'
                printf '            book = {length = 620, bytes = 0x626f6f6b6c02 ... 00000000};\n'
                printf '            "bundle-identifier" = "com.apple.finder";\n'
                printf '            "file-data" =             {\n'
                printf '                "_CFURLString" = "file:///System/Library/CoreServices/Finder.app/";\n'
                printf '                "_CFURLStringType" = 15;\n'
                printf '            };\n'
                printf '            "file-label" = Finder;\n'
                printf '        };\n'
                printf '        "tile-type" = "file-tile";\n'
                printf '    },\n'
                printf '        {\n'
                printf '        GUID = 1105742131;\n'
                printf '        "tile-data" =         {\n'
                printf '            "file-data" =             {\n'
                printf '                "_CFURLString" = "file:///Applications/Some%%20Other%%20App.app/";\n'
                printf '                "_CFURLStringType" = 15;\n'
                printf '            };\n'
                printf '            "file-label" = "Some Other App";\n'
                printf '        };\n'
                printf '        "tile-type" = "file-tile";\n'
                printf '    },\n'
            fi
            if [ "$_fd_mode" = "app" ]; then
                printf '        {\n'
                printf '        GUID = 1105742132;\n'
                printf '        "tile-data" =         {\n'
                printf '            "bundle-identifier" = "com.anthropic.claudefordesktop";\n'
                printf '            "file-data" =             {\n'
                printf '                "_CFURLString" = "file://%s/";\n' "$(url_encode "$_fd_bundle")"
                printf '                "_CFURLStringType" = 15;\n'
                printf '            };\n'
                printf '            "file-label" = Claude;\n'
                printf '        };\n'
                printf '        "tile-type" = "file-tile";\n'
                printf '    },\n'
            fi
            if [ "$_fd_mode" != "empty" ]; then
                printf '        {\n'
                printf '        GUID = 1105742133;\n'
                printf '        "tile-data" =         {\n'
                printf '            "file-data" =             {\n'
                printf '                "_CFURLString" = "file://%s/";\n' "$(url_encode "$HOME/Applications/Claude-Tide.app")"
                printf '                "_CFURLStringType" = 15;\n'
                printf '            };\n'
                printf '            "file-label" = "Claude-Tide";\n'
                printf '        };\n'
                printf '        "tile-type" = "file-tile";\n'
                printf '    }\n'
            fi
            printf ')\n'
            printf 'DOCKEOF\n'
        fi
    } > "$_fd_dir/defaults"
    chmod +x "$_fd_dir/defaults"
}

# url_encode <path>: percent-encode a path the way the Dock stores one, so a
# fixture under a HOME with a space in it is still the shape the real Dock
# prints rather than a simpler one this tool would parse by accident.
url_encode() {
    python3 -c '
import sys
from urllib.parse import quote
print(quote(sys.argv[1]))
' "$1"
}

# fake_icon_tools <bindir>: stand-in sips and iconutil that only write markers.
fake_icon_tools() {
    mkdir -p "$1"
    cat > "$1/sips" <<'SIPSEOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do case "$1" in --out) shift; out="$1" ;; esac; shift; done
[ -n "$out" ] || exit 1
mkdir -p "$(dirname "$out")" && printf 'resized\n' > "$out"
SIPSEOF
    cat > "$1/iconutil" <<'ICONEOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do case "$1" in -o) shift; out="$1" ;; esac; shift; done
[ -n "$out" ] || exit 1
printf 'generated-icns\n' > "$out"
ICONEOF
    chmod +x "$1/sips" "$1/iconutil"
}

# fixture_release <dir> <version>: a release laid out the way GitHub lays one
# out, under <dir>/download/v<version>/. curl reaches it over a file:// URL, so
# the installer's real download, checksum and unpack path runs rather than a
# simulation of it. The tarball holds this checkout, so what gets installed is
# the script under test.
fixture_release() {
    _fr_dir="$1/download/v$2"
    mkdir -p "$_fr_dir"
    _fr_stage=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-release.XXXXXX")
    _fr_top="$_fr_stage/agent-profile-$2"
    mkdir -p "$_fr_top"
    cp -R "$ROOT/bin" "$ROOT/tools" "$ROOT/docs" "$_fr_top/"
    cp "$ROOT/README.md" "$_fr_top/"
    tar -czf "$_fr_dir/agent-profile-$2.tar.gz" -C "$_fr_stage" "agent-profile-$2"
    rm -rf "$_fr_stage"
    ( cd "$_fr_dir" && shasum -a 256 "agent-profile-$2.tar.gz" > SHA256SUMS )
    # Stand-in bundles. Only a stand-in cosign ever reads them; what matters is
    # that they are fetched and handed over, not what is inside.
    printf 'stand-in bundle\n' > "$_fr_dir/agent-profile-$2.tar.gz.sigstore"
    printf 'stand-in bundle\n' > "$_fr_dir/SHA256SUMS.sigstore"
}

# fixture_release_api <path> <tag>: the shape of the GitHub releases API
# answer. Its body quotes a tag_name of its own, because the real API puts the
# field before the body and the parser takes the first match; this fixture is
# what pins that prose cannot be read as the answer.
fixture_release_api() {
    {
        printf '{\n'
        printf '  "html_url": "https://example.invalid/releases/tag/%s",\n' "$2"
        printf '  "id": 1,\n'
        printf '  "tag_name": "%s",\n' "$2"
        printf '  "name": "%s",\n' "$2"
        printf '  "draft": false,\n'
        printf '  "prerelease": false,\n'
        printf '  "body": "An older note said \\"tag_name\\": \\"v0.0.1\\" in prose."\n'
        printf '}\n'
    } > "$1"
}

# fake_cosign <bindir> <exit-status>: a stand-in cosign, so the signature path
# runs on a machine that has no cosign and the refusal path runs at all. It
# checks the shape of the call rather than any cryptography: that a bundle, an
# identity and an issuer were passed, and that the blob it was asked about is
# really there.
fake_cosign() {
    mkdir -p "$1"
    cat > "$1/cosign" <<'COSEOF'
#!/bin/sh
[ "$1" = "verify-blob" ] || { echo "cosign: unexpected subcommand $1" >&2; exit 64; }
shift
bundle=""; identity=""; issuer=""; blob=""
while [ $# -gt 0 ]; do
    case "$1" in
        --bundle) shift; bundle="$1" ;;
        --certificate-identity-regexp) shift; identity="$1" ;;
        --certificate-oidc-issuer) shift; issuer="$1" ;;
        -*) ;;
        *) blob="$1" ;;
    esac
    shift
done
[ -f "$bundle" ] || { echo "cosign: no bundle at $bundle" >&2; exit 65; }
[ -f "$blob" ] || { echo "cosign: no blob at $blob" >&2; exit 66; }
[ -n "$identity" ] || { echo "cosign: no --certificate-identity-regexp" >&2; exit 67; }
[ -n "$issuer" ] || { echo "cosign: no --certificate-oidc-issuer" >&2; exit 68; }
COSEOF
    printf 'exit %s\n' "$2" >> "$1/cosign"
    chmod +x "$1/cosign"
}

# fixture_launch_line <bundle> <root> <app-data>: the generated form, verbatim.
fixture_launch_line() {
    printf 'do shell script "open -n -a \\"%s\\" --env \\"CLAUDE_CONFIG_DIR=%s\\" --args --user-data-dir=\\"%s\\" > /dev/null 2>&1 &"\n' \
        "$1" "$2" "$3"
}

# fixture_applet <applet> <launch-line>: an applet holding exactly that line.
fixture_applet() {
    mkdir -p "$1/Contents/Resources/Scripts"
    printf '%s\n' "$2" > "$1/Contents/Resources/Scripts/main.scpt"
}

# applet_line_of <applet>: the launch line an applet currently holds.
applet_line_of() {
    sed -n '/^do shell script /p' "$1/Contents/Resources/Scripts/main.scpt" 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

run_case() {
    CURRENT="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    # A missing function must fail loudly. Without this check a typo in a case
    # name reports ok, because nothing ran and so nothing failed.
    if ! type "$2" >/dev/null 2>&1; then
        fail "the case function '$2' is not defined"
        return
    fi
    _before="$TESTS_FAILED"
    "$2"
    [ "$TESTS_FAILED" -eq "$_before" ] && pass
}

printf 'agent-profile test suite\n'
printf '  bash    %s\n' "$BASH_VERSION"
printf '  script  %s\n\n' "$ROOT/bin/agent-profile"

for _case in "$ROOT"/tests/cases/*.sh; do
    [ -f "$_case" ] || continue
    printf '%s\n' "$(basename "$_case" .sh)"
    # shellcheck source=/dev/null
    . "$_case"
    printf '\n'
done

printf '%s test(s), %s failure(s)\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
exit 0
