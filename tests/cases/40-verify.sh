# shellcheck shell=bash
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# verify: the checks that catch the tool's own assumptions going stale.

case_verify_unchecked_exits_4() {
    # Nothing broken, but the macOS facts cannot be checked from anywhere else.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
    out=$("$AP" verify 2>&1); status=$?
    assert_status 4 "$status" "$out" || return
    assert_contains "$out" "not running on macOS" || return
    assert_contains "$out" "could not be checked"
}

case_verify_confirms_cwd_is_recorded() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
    out=$("$AP" verify 2>&1)
    assert_contains "$out" "ok        F11"
}

case_verify_catches_cwd_disappearing() {
    # This is the regression that matters most. doctor's D03 reads cwd from
    # transcript metadata, so if a future agent version stops recording it,
    # D03 finds nothing and reports a clean machine. verify must catch that,
    # because a silent pass is worse than a failure.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new highsoft >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_account "$HOME/.claude-highsoft" "m@highsoft.no" "org-h"
    fixture_transcript_nocwd "$HOME/.claude-bouvet" "-Users-m-dev-shared"
    fixture_transcript_nocwd "$HOME/.claude-highsoft" "-Users-m-dev-shared"

    out=$("$AP" verify 2>&1); status=$?
    assert_status 3 "$status" "$out" || return
    assert_contains "$out" "BROKEN    F11" || return
    assert_contains "$out" "Do not trust doctor" || return

    # And confirm the danger is real: doctor sees nothing wrong.
    dout=$("$AP" doctor 2>&1); dstatus=$?
    assert_status 0 "$dstatus" || return
    assert_contains "$dout" "No isolation problems found"
}

case_verify_catches_account_key_moving() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
    # A state file that no longer carries oauthAccount.emailAddress.
    printf '{"account":{"email":"m@bouvet.no"}}\n' > "$HOME/.claude-bouvet/.claude.json"
    out=$("$AP" verify 2>&1); status=$?
    assert_status 3 "$status" || return
    assert_contains "$out" "BROKEN    F07"
}

case_verify_reports_partial_cwd_coverage() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-a" "/Users/m/dev/a"
    fixture_transcript_nocwd "$HOME/.claude-bouvet" "-Users-m-dev-b"
    out=$("$AP" verify 2>&1); status=$?
    assert_status 3 "$status" || return
    assert_contains "$out" "only 1 of 2"
}

case_verify_unchecked_without_roots() {
    HOME=$(new_home); export HOME
    out=$("$AP" verify 2>&1); status=$?
    assert_status 4 "$status" || return
    assert_contains "$out" "no existing config root"
}

case_verify_notes_version_drift() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    # A fake claude that reports a version the facts were not checked against.
    mkdir -p "$HOME/fakebin"
    printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' > "$HOME/fakebin/claude"
    chmod +x "$HOME/fakebin/claude"
    out=$(PATH="$HOME/fakebin:$PATH" "$AP" verify 2>&1)
    assert_contains "$out" "claude is 9.9.9" || return
    assert_contains "$out" "facts were checked against"
}

run_case "verify exits 4 when only unchecked remain"  case_verify_unchecked_exits_4
run_case "verify confirms cwd is recorded"            case_verify_confirms_cwd_is_recorded
run_case "verify catches cwd disappearing (F11)"      case_verify_catches_cwd_disappearing
run_case "verify catches the account key moving"      case_verify_catches_account_key_moving
run_case "verify reports partial cwd coverage"        case_verify_reports_partial_cwd_coverage
run_case "verify is unchecked without any roots"      case_verify_unchecked_without_roots
run_case "verify notes agent version drift"           case_verify_notes_version_drift
