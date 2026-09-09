# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# The machine-readable audit. Every document produced here is parsed with
# python3 -m json.tool, so output that merely looks like JSON fails.

# json_parses <text>: does this parse as one JSON document?
json_parses() {
    printf '%s\n' "$1" | python3 -m json.tool >/dev/null 2>&1
}

# json_get <text> <expression>: one value out of a document. The expression is
# python, with the parsed document bound to d, so a case can ask for exactly
# what it means rather than grepping the rendering.
json_get() {
    printf '%s\n' "$1" | python3 -c '
import json, sys
value = eval(sys.argv[1], {"d": json.load(sys.stdin)})
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
' "$2"
}

# assert_json <text>: fails with the offending output rather than silently.
assert_json() {
    if ! json_parses "$1"; then
        fail "output is not valid JSON" "$1"
        return 1
    fi
    return 0
}

# mac_json <args...>: the macOS-only rules, against a stand-in security(1).
mac_json() {
    PATH="$HOME/fakebin:$PATH" AGENT_PROFILE_PLATFORM=Darwin USER=tester "$AP" "$@"
}

# json_service_for <root>: the Keychain service name for a root, as the
# stand-in Keychain must be told about it.
json_service_for() {
    printf 'Claude Code-credentials-%s\n' "$(python3 -c '
import hashlib, sys, unicodedata
print(hashlib.sha256(unicodedata.normalize("NFC", sys.argv[1]).encode()).hexdigest()[:8])
' "$1")"
}

json_two_profiles() {
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new highsoft >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
}

case_doctor_json_is_one_document() {
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --json 2>/dev/null)
    assert_json "$out" || return
    assert_equals "agent-profile/doctor" "$(json_get "$out" 'd["schema"]')" || return
    assert_equals "1" "$(json_get "$out" 'd["schema_version"]')" || return
    assert_equals "doctor" "$(json_get "$out" 'd["command"]')"
}

case_doctor_json_says_when_and_where_it_was_produced() {
    # The header is what makes this evidence rather than a listing.
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --json 2>/dev/null)
    assert_json "$out" || return
    stamp=$(json_get "$out" 'd["generated_at"]')
    case "$stamp" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
        *) fail "generated_at is not a UTC timestamp" "got: $stamp"; return ;;
    esac
    want=$("${BASH:-/bin/bash}" "$ROOT/bin/agent-profile" version | awk '{print $2}')
    assert_equals "$want" "$(json_get "$out" 'd["tool_version"]')" || return
    [ -n "$(json_get "$out" 'd["verified_against"]')" ] || fail "no verified_against"
    [ -n "$(json_get "$out" 'd["hostname"]')" ] || fail "no hostname"
    assert_equals "1" "$(json_get "$out" 'len(d["agents"])')"
}

case_doctor_json_carries_the_profile_inventory() {
    # doctor's prose says nothing about a healthy profile. The document has to,
    # or a finding names a machine the reader cannot see.
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --json 2>/dev/null)
    assert_json "$out" || return
    assert_equals "2" "$(json_get "$out" 'len(d["profiles"])')" || return
    assert_equals "bouvet" "$(json_get "$out" 'd["profiles"][0]["name"]')" || return
    assert_equals "$HOME/.claude-bouvet" "$(json_get "$out" 'd["profiles"][0]["root"]')" || return
    assert_equals "true" "$(json_get "$out" 'd["profiles"][0]["root_exists"]')" || return
    assert_equals "m@bouvet.no" "$(json_get "$out" 'd["profiles"][0]["account"]')" || return
    assert_equals "org-b" "$(json_get "$out" 'd["profiles"][0]["organization"]')" || return
    assert_equals "1" "$(json_get "$out" 'd["profiles"][0]["sessions"]')" || return
    assert_contains "$(json_get "$out" 'd["profiles"][0]["app_data"]')" "Claude-Bouvet" || return
    # A profile that is not signed in is null, not a sentence.
    assert_equals "" "$(json_get "$out" 'd["profiles"][1]["account"]')"
}

case_doctor_json_findings_match_the_prose_fields() {
    HOME=$(new_home); export HOME
    json_two_profiles
    fixture_transcript "$HOME/.claude" "-Users-m-dev-leaked" "/Users/m/dev/leaked"
    out=$("$AP" doctor --json 2>/dev/null); status=$?
    assert_status 2 "$status" || return
    assert_json "$out" || return
    assert_equals "D01" "$(json_get "$out" '[f for f in d["findings"] if f["rule"] == "D01"][0]["rule"]')" || return
    assert_contains "$(json_get "$out" '[f for f in d["findings"] if f["rule"] == "D01"][0]["summary"]')" \
        "default claude root holds 1 session" || return
    assert_equals "$HOME/.claude" \
        "$(json_get "$out" '[f for f in d["findings"] if f["rule"] == "D01"][0]["subject"]')" || return
    assert_contains "$(json_get "$out" '" ".join([f for f in d["findings"] if f["rule"] == "D01"][0]["detail"])')" \
        "Something ran without a profile pinned"
}

case_doctor_json_keeps_the_exit_code() {
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --json 2>/dev/null); status=$?
    assert_status 2 "$status" || return
    assert_json "$out" || return
    assert_equals "2" "$(json_get "$out" 'd["summary"]["exit_code"]')" || return
    assert_equals "1" "$(json_get "$out" 'd["summary"]["findings"]')"
}

case_doctor_json_on_a_clean_machine() {
    HOME=$(new_home); export HOME
    json_two_profiles
    fixture_account "$HOME/.claude-highsoft" "m@highsoft.no" "org-h"
    out=$("$AP" doctor --json 2>/dev/null); status=$?
    assert_status 0 "$status" "$out" || return
    assert_json "$out" || return
    assert_equals "0" "$(json_get "$out" 'len(d["findings"])')" || return
    assert_equals "0" "$(json_get "$out" 'd["summary"]["exit_code"]')"
}

case_doctor_json_prints_no_prose() {
    # A document with a sentence in front of it parses nowhere.
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --json 2>/dev/null)
    case "$out" in
        "{"*) ;;
        *) fail "the document does not start with {" "$out"; return ;;
    esac
    assert_not_contains "$out" "finding(s)."
}

case_doctor_json_reports_a_missing_root_as_missing() {
    HOME=$(new_home); export HOME
    json_two_profiles
    rm -rf "$HOME/.claude-highsoft"
    out=$("$AP" doctor --json 2>/dev/null)
    assert_json "$out" || return
    assert_equals "false" "$(json_get "$out" 'd["profiles"][1]["root_exists"]')" || return
    assert_equals "fail" "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D04"][0]["status"]')"
}

case_doctor_json_lists_every_rule() {
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --json 2>/dev/null)
    assert_json "$out" || return
    assert_equals "16" "$(json_get "$out" 'len(d["rules"])')" || return
    assert_equals "D01" "$(json_get "$out" 'd["rules"][0]["rule"]')" || return
    assert_equals "D16" "$(json_get "$out" 'd["rules"][-1]["rule"]')" || return
    [ -n "$(json_get "$out" 'd["rules"][0]["title"]')" ] || fail "a rule has no title"
}

case_doctor_json_does_not_call_an_unrun_rule_passing() {
    # D12 is opt-in behind --keychain-scan. Reporting it as a pass would be
    # claiming a check that never ran, which is the whole risk of a document
    # that lists rules at all.
    HOME=$(new_home); export HOME
    json_two_profiles
    fake_keychain "$HOME/fakebin" \
        "$(json_service_for "$HOME/.claude-bouvet")" \
        "$(json_service_for "$HOME/.claude-highsoft")" \
        "Claude Code-credentials-deadbeef"
    out=$(mac_json doctor --json 2>/dev/null)
    assert_json "$out" || return
    assert_equals "not_run" "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D12"][0]["status"]')" || return
    assert_contains "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D12"][0]["reason"]')" \
        "--keychain-scan"
}

case_doctor_json_reports_d12_once_it_has_run() {
    HOME=$(new_home); export HOME
    json_two_profiles
    fake_keychain "$HOME/fakebin" \
        "$(json_service_for "$HOME/.claude-bouvet")" \
        "$(json_service_for "$HOME/.claude-highsoft")" \
        "Claude Code-credentials-deadbeef"
    out=$(mac_json doctor --json --keychain-scan 2>/dev/null)
    assert_json "$out" || return
    assert_equals "fail" "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D12"][0]["status"]')" || return
    assert_equals "" "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D12"][0]["reason"]')"
}

case_doctor_json_marks_the_keychain_rules_unrun_without_one() {
    # No Keychain to ask: D11 and D12 did not run, and D05 ran in a weaker
    # form. None of the three may be reported as passing.
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --json 2>/dev/null)
    assert_json "$out" || return
    assert_equals "not_run" "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D11"][0]["status"]')" || return
    assert_equals "not_run" "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D12"][0]["status"]')" || return
    assert_contains "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D05"][0]["reason"]')" \
        "no Keychain"
}

case_doctor_json_is_honest_about_the_desktop_rules() {
    # D13 and D14 read an applet by decompiling it, so what they can see
    # depends on osadecompile, which ships with macOS and exists on no Linux
    # box. Both answers are asserted here rather than one of them skipped: on a
    # machine that has it the rules must not claim they did not run, and on a
    # machine that does not they must not claim they passed.
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --json 2>/dev/null)
    assert_json "$out" || return
    d13=$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D13"][0]["status"]')
    d14=$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D14"][0]["status"]')
    if command -v osadecompile >/dev/null 2>&1; then
        [ "$d13" = "not_run" ] && fail "D13 says not_run though osadecompile is here"
        [ "$d14" = "not_run" ] && fail "D14 says not_run though osadecompile is here"
        return
    fi
    assert_equals "not_run" "$d13" || return
    assert_equals "not_run" "$d14" || return
    assert_contains "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D14"][0]["reason"]')" \
        "osadecompile"
}

case_doctor_json_runs_the_desktop_rules_when_it_can() {
    # The other half, made to hold everywhere: with a stand-in osadecompile on
    # PATH the rules can read an applet, so neither may report not_run.
    HOME=$(new_home); export HOME
    json_two_profiles
    fake_osa "$HOME/fakebin"
    out=$(PATH="$HOME/fakebin:$PATH" "$AP" doctor --json 2>/dev/null)
    assert_json "$out" || return
    assert_equals "pass" "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D13"][0]["status"]')" || return
    assert_equals "" "$(json_get "$out" '[r for r in d["rules"] if r["rule"] == "D13"][0]["reason"]')"
}

case_doctor_report_writes_both_files() {
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --report "$HOME/audit" 2>&1); status=$?
    assert_status 2 "$status" "$out" || return
    # The human output is still the human output.
    assert_contains "$out" "D05" || return
    assert_contains "$out" "finding(s)." || return
    assert_contains "$out" "Wrote $HOME/audit.json" || return
    [ -f "$HOME/audit.json" ] || { fail "no audit.json"; return; }
    [ -f "$HOME/audit.md" ] || { fail "no audit.md"; return; }
    assert_json "$(cat "$HOME/audit.json")" || return
    assert_equals "doctor" "$(json_get "$(cat "$HOME/audit.json")" 'd["command"]')" || return
    assert_contains "$(cat "$HOME/audit.md")" "# Isolation audit" || return
    assert_contains "$(cat "$HOME/audit.md")" "D05" || return
    assert_contains "$(cat "$HOME/audit.md")" "$(json_get "$(cat "$HOME/audit.json")" 'd["generated_at"]')"
}

case_doctor_report_does_not_double_the_extension() {
    HOME=$(new_home); export HOME
    json_two_profiles
    "$AP" doctor --report "$HOME/audit.json" >/dev/null 2>&1
    [ -f "$HOME/audit.json" ] || { fail "no audit.json"; return; }
    [ -f "$HOME/audit.md" ] || { fail "no audit.md"; return; }
    if [ -e "$HOME/audit.json.json" ]; then
        fail "the extension was doubled"
    fi
}

case_doctor_report_refuses_a_path_it_cannot_write() {
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" doctor --report "$HOME/nosuchdir/audit" 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "could not write"
}

case_doctor_report_needs_a_file() {
    HOME=$(new_home); export HOME
    out=$("$AP" doctor --report 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "--report needs a file"
}

case_list_json_is_one_document() {
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" list --json 2>/dev/null); status=$?
    assert_status 0 "$status" || return
    assert_json "$out" || return
    assert_equals "agent-profile/list" "$(json_get "$out" 'd["schema"]')" || return
    assert_equals "2" "$(json_get "$out" 'len(d["profiles"])')" || return
    assert_equals "m@bouvet.no" "$(json_get "$out" 'd["profiles"][0]["account"]')" || return
    assert_equals "2" "$(json_get "$out" 'd["summary"]["profiles"]')"
}

case_list_json_with_nothing_registered() {
    HOME=$(new_home); export HOME
    out=$("$AP" list --json 2>/dev/null); status=$?
    assert_status 0 "$status" || return
    assert_json "$out" || return
    assert_equals "0" "$(json_get "$out" 'len(d["profiles"])')" || return
    assert_equals "0" "$(json_get "$out" 'd["summary"]["profiles"]')"
}

case_verify_json_is_one_document() {
    HOME=$(new_home); export HOME
    json_two_profiles
    out=$("$AP" verify --json 2>/dev/null); status=$?
    assert_json "$out" || return
    assert_equals "agent-profile/verify" "$(json_get "$out" 'd["schema"]')" || return
    # Whatever verify concluded, the document says the same thing the process
    # exited with.
    assert_equals "$status" "$(json_get "$out" 'd["summary"]["exit_code"]')" || return
    [ "$(json_get "$out" 'len(d["checks"])')" -gt 0 ] || { fail "no checks in the document"; return; }
    assert_equals "0" \
        "$(json_get "$out" 'len([c for c in d["checks"] if c["status"] not in ("ok", "broken", "unchecked", "note")])')" || return
    assert_contains "$(json_get "$out" '[c for c in d["checks"] if c["fact"] == "F13"][0]["summary"]')" \
        "not running on macOS"
}

case_json_flags_are_rejected_where_they_are_not_offered() {
    HOME=$(new_home); export HOME
    out=$("$AP" list --bogus 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown option" || return
    out=$("$AP" verify --bogus 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown option"
}

run_case "doctor --json is one JSON document"          case_doctor_json_is_one_document
run_case "doctor --json says when and where"           case_doctor_json_says_when_and_where_it_was_produced
run_case "doctor --json carries the inventory"         case_doctor_json_carries_the_profile_inventory
run_case "doctor --json findings match the prose"      case_doctor_json_findings_match_the_prose_fields
run_case "doctor --json keeps the exit code"           case_doctor_json_keeps_the_exit_code
run_case "doctor --json on a clean machine"            case_doctor_json_on_a_clean_machine
run_case "doctor --json prints no prose"               case_doctor_json_prints_no_prose
run_case "doctor --json reports a missing root"        case_doctor_json_reports_a_missing_root_as_missing
run_case "doctor --json lists every rule"              case_doctor_json_lists_every_rule
run_case "doctor --json never calls D12 passing"       case_doctor_json_does_not_call_an_unrun_rule_passing
run_case "doctor --json reports D12 once it runs"      case_doctor_json_reports_d12_once_it_has_run
run_case "doctor --json marks D05, D11 and D12"        case_doctor_json_marks_the_keychain_rules_unrun_without_one
run_case "doctor --json is honest about D13 and D14"   case_doctor_json_is_honest_about_the_desktop_rules
run_case "doctor --json runs D13 when it can"          case_doctor_json_runs_the_desktop_rules_when_it_can
run_case "doctor --report writes both files"           case_doctor_report_writes_both_files
run_case "doctor --report keeps one extension"         case_doctor_report_does_not_double_the_extension
run_case "doctor --report refuses an unwritable path"  case_doctor_report_refuses_a_path_it_cannot_write
run_case "doctor --report needs a file"                case_doctor_report_needs_a_file
run_case "list --json is one JSON document"            case_list_json_is_one_document
run_case "list --json with nothing registered"         case_list_json_with_nothing_registered
run_case "verify --json is one JSON document"          case_verify_json_is_one_document
run_case "--json is rejected where not offered"        case_json_flags_are_rejected_where_they_are_not_offered
