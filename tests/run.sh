#!/bin/bash
# shellcheck disable=SC2317  # helpers are called from the sourced case files
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
    printf '%s\n' "$_nh"
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

# fixture_account <root> <email> <org>
fixture_account() {
    printf '{"oauthAccount":{"emailAddress":"%s","organizationUuid":"%s"}}\n' "$2" "$3" \
        > "$1/.claude.json"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

run_case() {
    CURRENT="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
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
