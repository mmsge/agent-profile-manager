# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# The Keychain-backed rules. AGENT_PROFILE_PLATFORM plus a stand-in security(1)
# let these run anywhere, so the macOS-only paths are not shipped unrun.

mac() {
    PATH="$HOME/fakebin:$PATH" AGENT_PROFILE_PLATFORM=Darwin USER=tester "$AP" "$@"
}

signed_in_profile() {
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-U-m-b" "/U/m/b"
}

case_cred_hash_matches_the_verified_values() {
    # The three values confirmed against real Keychain entries on the target
    # machine. If this breaks, the naming in docs/FACTS.md F03 is wrong and
    # D05 will report false findings.
    assert_equals "Claude Code-credentials-1c128223" \
        "$(cred_service_for /Users/markus.mg/.claude)" || return
    assert_equals "Claude Code-credentials-2241c977" \
        "$(cred_service_for /Users/markus.mg/.claude-bouvet)" || return
    assert_equals "Claude Code-credentials-4c36052e" \
        "$(cred_service_for /Users/markus.mg/.claude-tide)"
}

case_a_trailing_slash_is_a_different_credential() {
    a=$(cred_service_for /Users/markus.mg/.claude-bouvet)
    b=$(cred_service_for /Users/markus.mg/.claude-bouvet/)
    if [ "$a" = "$b" ]; then
        fail "a trailing slash must key a different credential" "both were $a"
    fi
}

case_d05_quiet_when_the_keychain_has_the_entry() {
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-bouvet")"
    assert_not_contains "$(mac doctor 2>&1)" "D05"
}

case_d05_fires_when_the_keychain_lacks_the_entry() {
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin"
    out=$(mac doctor 2>&1)
    assert_contains "$out" "D05" || return
    assert_contains "$out" "has no credential"
}

case_d09_reports_the_url_handler() {
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-bouvet")"
    mkdir -p "$HOME/Applications/Claude Code URL Handler.app"
    out=$(mac doctor 2>&1)
    assert_contains "$out" "D09" || return
    assert_contains "$out" "claude-cli:// handler"
}

case_d09_quiet_without_a_handler() {
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-bouvet")"
    assert_not_contains "$(mac doctor 2>&1)" "D09"
}

case_d10_reports_a_non_canonical_root() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.config/agent-profiles" "$HOME/.claude-slashy"
    chmod 700 "$HOME/.claude-slashy"
    printf 'agent=claude\nroot=%s/.claude-slashy/\napp_data=%s/x\ncreated=2026-09-07\n' \
        "$HOME" "$HOME" > "$HOME/.config/agent-profiles/slashy.conf"
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-slashy")"
    out=$(mac doctor 2>&1)
    assert_contains "$out" "D10" || return
    assert_contains "$out" "trailing-slash"
}

case_d11_reports_a_credential_for_the_default_root() {
    # Only exists if the variable was set to the default path, which is a
    # different login from not pinning at all.
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" \
        "$(cred_service_for "$HOME/.claude-bouvet")" \
        "$(cred_service_for "$HOME/.claude")"
    out=$(mac doctor 2>&1)
    assert_contains "$out" "D11" || return
    assert_contains "$out" "ran pinned to it"
}

case_d11_quiet_without_that_entry() {
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-bouvet")"
    assert_not_contains "$(mac doctor 2>&1)" "D11"
}

case_d12_counts_orphaned_entries() {
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" \
        "$(cred_service_for "$HOME/.claude-bouvet")" \
        "Claude Code-credentials-deadbeef" \
        "Claude Code-credentials-cafef00d"
    out=$(mac doctor --keychain-scan 2>&1)
    assert_contains "$out" "D12" || return
    assert_contains "$out" "2 Keychain credential"
}

case_d12_quiet_when_every_entry_is_known() {
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-bouvet")"
    assert_not_contains "$(mac doctor --keychain-scan 2>&1)" "D12"
}

case_d12_not_checked_without_the_flag() {
    # D12 walks the whole Keychain, unlike D05 and D11 which query one named
    # service each. Without --keychain-scan it must not run, and doctor must
    # say plainly that it did not.
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" \
        "$(cred_service_for "$HOME/.claude-bouvet")" \
        "Claude Code-credentials-deadbeef"
    out=$(mac doctor 2>&1)
    assert_not_contains "$out" "belong to no known root" || return
    assert_contains "$out" "were not checked" || return
    assert_contains "$out" "--keychain-scan"
}

case_doctor_rejects_an_unknown_option() {
    HOME=$(new_home); export HOME
    out=$(mac doctor --bogus 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown option"
}

case_verify_checks_the_keychain_naming() {
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-bouvet")"
    assert_contains "$(mac verify 2>&1)" "ok        F03"
}

case_verify_catches_the_naming_changing() {
    # A future version that renames the service. D05 would report every
    # profile as having no credential, so verify must say so first.
    HOME=$(new_home); export HOME
    signed_in_profile
    fake_keychain "$HOME/fakebin" "Claude Code-secrets-v2-2241c977"
    out=$(mac verify 2>&1); status=$?
    assert_status 3 "$status" || return
    assert_contains "$out" "BROKEN    F03" || return
    assert_contains "$out" "naming has probably changed"
}

case_new_normalises_a_trailing_slash() {
    HOME=$(new_home); export HOME
    "$AP" new y --root "$HOME/roots/y/" >/dev/null 2>&1
    assert_equals "$HOME/roots/y" "$(reg_root_of y)"
}

case_new_rejects_a_relative_root() {
    HOME=$(new_home); export HOME
    out=$("$AP" new y --root "relative/path" 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "must be an absolute path"
}

case_new_canonicalises_a_doubled_slash() {
    # Reachable in ordinary use: $TMPDIR ends in a slash on macOS, so
    # --root "$TMPDIR/x" arrives with "//" in it. That is a different literal
    # string and so a different credential.
    HOME=$(new_home); export HOME
    "$AP" new y --root "$HOME//roots//y" >/dev/null 2>&1
    assert_equals "$HOME/roots/y" "$(reg_root_of y)"
}

case_new_canonicalises_a_dot_segment() {
    HOME=$(new_home); export HOME
    "$AP" new y --root "$HOME/roots/./y" >/dev/null 2>&1
    assert_equals "$HOME/roots/y" "$(reg_root_of y)"
}

case_doctor_flags_a_hand_written_doubled_slash() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.config/agent-profiles" "$HOME/.claude-dbl"
    chmod 700 "$HOME/.claude-dbl"
    printf 'agent=claude\nroot=%s//.claude-dbl\napp_data=%s/x\ncreated=2026-09-07\n' \
        "$HOME" "$HOME" > "$HOME/.config/agent-profiles/dbl.conf"
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME//.claude-dbl")"
    out=$(mac doctor 2>&1)
    assert_contains "$out" "D10" || return
    assert_contains "$out" "not-normalized"
}

run_case "new canonicalises a doubled slash"            case_new_canonicalises_a_doubled_slash
run_case "new canonicalises a dot segment"              case_new_canonicalises_a_dot_segment
run_case "D10 flags a hand-written doubled slash"       case_doctor_flags_a_hand_written_doubled_slash
run_case "the credential hash matches verified values"  case_cred_hash_matches_the_verified_values
run_case "a trailing slash is a different credential"   case_a_trailing_slash_is_a_different_credential
run_case "D05 quiet when the Keychain has the entry"    case_d05_quiet_when_the_keychain_has_the_entry
run_case "D05 fires when the Keychain lacks it"         case_d05_fires_when_the_keychain_lacks_the_entry
run_case "D09 reports the URL handler"                  case_d09_reports_the_url_handler
run_case "D09 quiet without a handler"                  case_d09_quiet_without_a_handler
run_case "D10 reports a non-canonical root"             case_d10_reports_a_non_canonical_root
run_case "D11 reports a default-root credential"        case_d11_reports_a_credential_for_the_default_root
run_case "D11 quiet without that entry"                 case_d11_quiet_without_that_entry
run_case "D12 counts orphaned entries"                  case_d12_counts_orphaned_entries
run_case "D12 quiet when every entry is known"          case_d12_quiet_when_every_entry_is_known
run_case "D12 not checked without the flag"             case_d12_not_checked_without_the_flag
run_case "doctor rejects an unknown option"             case_doctor_rejects_an_unknown_option
run_case "verify checks the Keychain naming"            case_verify_checks_the_keychain_naming
run_case "verify catches the naming changing"           case_verify_catches_the_naming_changing
run_case "new normalises a trailing slash"              case_new_normalises_a_trailing_slash
run_case "new rejects a relative root"                  case_new_rejects_a_relative_root
