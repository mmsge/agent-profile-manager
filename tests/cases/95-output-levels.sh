# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# Output levels: --quiet and --explain (issue #24). Default output is short;
# --explain (or AGENT_PROFILE_EXPLAIN=1) restores the long form new, app,
# desktop and which always used to print, and doctor's and verify's --quiet
# silences a clean run for cron and shell hooks. None of this may change a
# document: doctor --json, list --json, verify --json and doctor --report
# must read the same at every level.

# ol_clean_profile: one profile, signed in, with a transcript. A clean audit.
ol_clean_profile() {
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
}

# strip_generated_at <json>: a document's own timestamp is the one field two
# runs of the same scenario are not required to agree on.
strip_generated_at() {
    printf '%s\n' "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
d.pop("generated_at", None)
print(json.dumps(d, indent=2, sort_keys=True))
'
}

# ol_json_tool <json>: python3 -m json.tool, the same parser the reviewer runs
# by hand. Fails loudly rather than merely comparing strings that might both
# happen to be malformed the same way.
ol_json_tool() {
    printf '%s\n' "$1" | python3 -m json.tool >/dev/null
}

# ---------------------------------------------------------------------------
# doctor --quiet
# ---------------------------------------------------------------------------

case_doctor_quiet_is_silent_on_a_clean_run() {
    HOME=$(new_home); export HOME
    ol_clean_profile
    out=$("$AP" doctor --quiet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "" "$out"
}

case_doctor_quiet_is_silent_with_no_profiles_either() {
    HOME=$(new_home); export HOME
    out=$("$AP" doctor --quiet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "" "$out"
}

case_doctor_quiet_still_prints_a_finding() {
    HOME=$(new_home); export HOME
    ol_clean_profile
    chmod 755 "$HOME/.claude-bouvet"
    out=$("$AP" doctor --quiet 2>&1); status=$?
    assert_status 2 "$status" || return
    assert_contains "$out" "D07" || return
    assert_contains "$out" "finding(s)."
}

case_doctor_quiet_rejects_nothing_new() {
    # --quiet is a real option, not a typo that happens to fall through.
    HOME=$(new_home); export HOME
    out=$("$AP" doctor --bogus 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "--quiet"
}

# ---------------------------------------------------------------------------
# doctor --explain / AGENT_PROFILE_EXPLAIN
# ---------------------------------------------------------------------------

case_doctor_explain_does_not_hide_or_add_findings() {
    # Findings are the product and already print in full by default, so
    # --explain changes nothing observable here -- it is accepted rather than
    # rejected, which is what a genuinely global flag has to do.
    HOME=$(new_home); export HOME
    ol_clean_profile
    chmod 755 "$HOME/.claude-bouvet"
    plain=$("$AP" doctor 2>&1); pstatus=$?
    explained=$("$AP" doctor --explain 2>&1); estatus=$?
    assert_equals "$pstatus" "$estatus" || return
    assert_equals "$plain" "$explained"
}

case_doctor_explain_env_var_works_like_the_flag() {
    HOME=$(new_home); export HOME
    ol_clean_profile
    flag=$("$AP" doctor --explain 2>&1)
    env=$(AGENT_PROFILE_EXPLAIN=1 "$AP" doctor 2>&1)
    assert_equals "$flag" "$env"
}

# ---------------------------------------------------------------------------
# --quiet wins over --explain, either order
# ---------------------------------------------------------------------------

case_quiet_wins_over_explain_before_it() {
    HOME=$(new_home); export HOME
    ol_clean_profile
    out=$("$AP" doctor --explain --quiet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "" "$out"
}

case_quiet_wins_over_explain_after_it() {
    HOME=$(new_home); export HOME
    ol_clean_profile
    out=$("$AP" doctor --quiet --explain 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "" "$out"
}

# ---------------------------------------------------------------------------
# verify --quiet / --explain
#
# The suite runs with AGENT_PROFILE_PLATFORM=test-not-darwin, so a fully
# clean verify (every macOS-only fact checked and holding) is not reachable
# here without a real Mac; 40-verify.sh's own cases confirm the same thing.
# What is tested here instead is the mechanism itself: --quiet drops the
# routine "ok" and "note" lines and the opening banner, while whatever made
# the run not clean -- broken or unchecked -- still prints in full, same as
# the exit code.
# ---------------------------------------------------------------------------

case_verify_quiet_drops_routine_lines_but_keeps_unchecked() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"

    plain=$("$AP" verify 2>&1)
    assert_contains "$plain" "Checking the assumptions" || return
    assert_contains "$plain" "ok        F07" || return

    out=$("$AP" verify --quiet 2>&1); status=$?
    assert_status 4 "$status" "$out" || return
    assert_not_contains "$out" "Checking the assumptions" || return
    assert_not_contains "$out" "ok        F07" || return
    assert_contains "$out" "not running on macOS" || return
    assert_contains "$out" "could not be checked"
}

case_verify_quiet_still_prints_when_broken() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new highsoft >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_account "$HOME/.claude-highsoft" "m@highsoft.no" "org-h"
    fixture_transcript_nocwd "$HOME/.claude-bouvet" "-Users-m-dev-shared"
    fixture_transcript_nocwd "$HOME/.claude-highsoft" "-Users-m-dev-shared"

    out=$("$AP" verify --quiet 2>&1); status=$?
    assert_status 3 "$status" "$out" || return
    assert_contains "$out" "BROKEN    F11" || return
    assert_contains "$out" "Fix the tool before trusting doctor." || return
    assert_not_contains "$out" "Checking the assumptions"
}

case_verify_explain_does_not_change_the_verdict() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
    plain=$("$AP" verify 2>&1); pstatus=$?
    explained=$("$AP" verify --explain 2>&1); estatus=$?
    assert_equals "$pstatus" "$estatus" || return
    assert_equals "$plain" "$explained"
}

case_verify_rejects_nothing_new() {
    HOME=$(new_home); export HOME
    out=$("$AP" verify --bogus 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "--quiet"
}

# ---------------------------------------------------------------------------
# Documents are unaffected: doctor --json, verify --json, list --json and
# doctor --report must read the same at every level. --quiet and --explain
# are about the terminal, never about the document.
# ---------------------------------------------------------------------------

case_doctor_json_is_identical_at_every_level() {
    HOME=$(new_home); export HOME
    ol_clean_profile
    chmod 755 "$HOME/.claude-bouvet"

    raw_plain=$("$AP" doctor --json 2>/dev/null)
    raw_quiet=$("$AP" doctor --json --quiet 2>/dev/null)
    raw_explained=$("$AP" doctor --json --explain 2>/dev/null)
    ol_json_tool "$raw_plain" || { fail "doctor --json is not valid JSON" "$raw_plain"; return; }
    ol_json_tool "$raw_quiet" || { fail "doctor --json --quiet is not valid JSON" "$raw_quiet"; return; }
    ol_json_tool "$raw_explained" || { fail "doctor --json --explain is not valid JSON" "$raw_explained"; return; }

    plain=$(strip_generated_at "$raw_plain")
    quiet=$(strip_generated_at "$raw_quiet")
    explained=$(strip_generated_at "$raw_explained")

    assert_equals "$plain" "$quiet" || return
    assert_equals "$plain" "$explained"
}

case_verify_json_is_identical_at_every_level() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"

    raw_plain=$("$AP" verify --json 2>/dev/null)
    raw_quiet=$("$AP" verify --json --quiet 2>/dev/null)
    raw_explained=$("$AP" verify --json --explain 2>/dev/null)
    ol_json_tool "$raw_plain" || { fail "verify --json is not valid JSON" "$raw_plain"; return; }
    ol_json_tool "$raw_quiet" || { fail "verify --json --quiet is not valid JSON" "$raw_quiet"; return; }
    ol_json_tool "$raw_explained" || { fail "verify --json --explain is not valid JSON" "$raw_explained"; return; }

    plain=$(strip_generated_at "$raw_plain")
    quiet=$(strip_generated_at "$raw_quiet")
    explained=$(strip_generated_at "$raw_explained")

    assert_equals "$plain" "$quiet" || return
    assert_equals "$plain" "$explained"
}

case_list_json_is_identical_under_agent_profile_explain() {
    # list has no --quiet or --explain of its own, but a standing
    # AGENT_PROFILE_EXPLAIN=1 in the environment must not leak into it either.
    HOME=$(new_home); export HOME
    ol_clean_profile
    raw_plain=$("$AP" list --json 2>/dev/null)
    raw_explained=$(AGENT_PROFILE_EXPLAIN=1 "$AP" list --json 2>/dev/null)
    ol_json_tool "$raw_plain" || { fail "list --json is not valid JSON" "$raw_plain"; return; }
    ol_json_tool "$raw_explained" || { fail "list --json under EXPLAIN is not valid JSON" "$raw_explained"; return; }
    assert_equals "$(strip_generated_at "$raw_plain")" "$(strip_generated_at "$raw_explained")"
}

case_doctor_report_is_identical_at_every_level() {
    HOME=$(new_home); export HOME
    ol_clean_profile
    chmod 755 "$HOME/.claude-bouvet"

    base="$HOME/plain"; "$AP" doctor --report "$base" >/dev/null 2>&1
    base_q="$HOME/quiet"; "$AP" doctor --report "$base_q" --quiet >/dev/null 2>&1
    base_e="$HOME/explained"; "$AP" doctor --report "$base_e" --explain >/dev/null 2>&1

    raw_plain=$(cat "$base.json")
    raw_quiet=$(cat "$base_q.json")
    raw_explained=$(cat "$base_e.json")
    ol_json_tool "$raw_plain" || { fail "the --report .json is not valid JSON" "$raw_plain"; return; }
    ol_json_tool "$raw_quiet" || { fail "the --quiet --report .json is not valid JSON" "$raw_quiet"; return; }
    ol_json_tool "$raw_explained" || { fail "the --explain --report .json is not valid JSON" "$raw_explained"; return; }

    plain=$(strip_generated_at "$raw_plain")
    quiet=$(strip_generated_at "$raw_quiet")
    explained=$(strip_generated_at "$raw_explained")

    assert_equals "$plain" "$quiet" || return
    assert_equals "$plain" "$explained"
}

# ---------------------------------------------------------------------------
# new: short default, --explain restores the long form
# ---------------------------------------------------------------------------

case_new_default_is_short() {
    HOME=$(new_home); export HOME
    out=$("$AP" new bouvet 2>&1)
    lines=$(printf '%s\n' "$out" | grep -c '')
    if [ "$lines" -gt 3 ]; then
        fail "expected at most 3 lines, got $lines" "$out"
        return
    fi
    assert_contains "$out" "Created profile bouvet" || return
    assert_contains "$out" "Next:"
}

case_new_default_omits_the_field_block() {
    HOME=$(new_home); export HOME
    out=$("$AP" new bouvet 2>&1)
    assert_not_contains "$out" "  agent     claude"
}

case_new_explain_restores_the_field_block() {
    HOME=$(new_home); export HOME
    out=$("$AP" new bouvet --explain 2>&1)
    assert_contains "$out" "  agent     claude" || return
    assert_contains "$out" "  root      " || return
    assert_contains "$out" "  app data  "
}

# ---------------------------------------------------------------------------
# app: short default, --explain restores the field block and confirm hint
# ---------------------------------------------------------------------------

case_app_default_omits_pins_and_rationale() {
    desktop_fixture
    out=$(desk app tide 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Created" || return
    assert_not_contains "$out" "  pins" || return
    assert_not_contains "$out" "Confirm it actually pins"
}

case_app_explain_restores_pins_and_confirm_hint() {
    desktop_fixture
    desk app tide >/dev/null 2>&1
    out=$(desk app tide --explain 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "  pins" || return
    assert_contains "$out" "Nothing to do" || return
    assert_contains "$out" "Confirm it actually pins"
}

# ---------------------------------------------------------------------------
# which: short default when unpinned, --explain restores the rationale
# ---------------------------------------------------------------------------

case_which_unpinned_default_is_short() {
    HOME=$(new_home); export HOME
    out=$(env -u CLAUDE_CONFIG_DIR "$AP" which 2>&1)
    assert_contains "$out" "Not pinned to any profile" || return
    assert_not_contains "$out" "This shell has none of these set"
}

case_which_unpinned_explain_restores_the_rationale() {
    HOME=$(new_home); export HOME
    out=$(env -u CLAUDE_CONFIG_DIR "$AP" which --explain 2>&1)
    assert_contains "$out" "This shell has none of these set" || return
    assert_contains "$out" "doctor reports as a leak"
}

case_which_pinned_output_is_unaffected_by_explain() {
    # The pinned branch already states facts only, so --explain changes
    # nothing there; it must still be accepted rather than rejected.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    plain=$(CLAUDE_CONFIG_DIR="$HOME/.claude-bouvet" "$AP" which)
    explained=$(CLAUDE_CONFIG_DIR="$HOME/.claude-bouvet" "$AP" which --explain)
    assert_equals "$plain" "$explained"
}

run_case "doctor --quiet is silent on a clean run"        case_doctor_quiet_is_silent_on_a_clean_run
run_case "doctor --quiet is silent with no profiles"      case_doctor_quiet_is_silent_with_no_profiles_either
run_case "doctor --quiet still prints a finding"          case_doctor_quiet_still_prints_a_finding
run_case "doctor --quiet is a real option"                case_doctor_quiet_rejects_nothing_new
run_case "doctor --explain does not hide or add findings" case_doctor_explain_does_not_hide_or_add_findings
run_case "doctor AGENT_PROFILE_EXPLAIN matches the flag"  case_doctor_explain_env_var_works_like_the_flag
run_case "--quiet wins over a preceding --explain"        case_quiet_wins_over_explain_before_it
run_case "--quiet wins over a following --explain"        case_quiet_wins_over_explain_after_it
run_case "verify --quiet drops routine lines, keeps unchecked" case_verify_quiet_drops_routine_lines_but_keeps_unchecked
run_case "verify --quiet still prints when broken"        case_verify_quiet_still_prints_when_broken
run_case "verify --explain does not change the verdict"   case_verify_explain_does_not_change_the_verdict
run_case "verify --quiet is a real option"                case_verify_rejects_nothing_new
run_case "doctor --json is identical at every level"      case_doctor_json_is_identical_at_every_level
run_case "verify --json is identical at every level"      case_verify_json_is_identical_at_every_level
run_case "list --json ignores AGENT_PROFILE_EXPLAIN"      case_list_json_is_identical_under_agent_profile_explain
run_case "doctor --report is identical at every level"    case_doctor_report_is_identical_at_every_level
run_case "new's default output is short"                  case_new_default_is_short
run_case "new's default omits the field block"            case_new_default_omits_the_field_block
run_case "new --explain restores the field block"         case_new_explain_restores_the_field_block
run_case "app's default omits pins and rationale"         case_app_default_omits_pins_and_rationale
run_case "app --explain restores pins and confirm hint"   case_app_explain_restores_pins_and_confirm_hint
run_case "which's unpinned default is short"              case_which_unpinned_default_is_short
run_case "which --explain restores the unpinned rationale" case_which_unpinned_explain_restores_the_rationale
run_case "which's pinned output is unaffected by --explain" case_which_pinned_output_is_unaffected_by_explain
