# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# The launch surfaces the applets exist to replace: the app's own icon in the
# Dock (D17) and the app data directory an unpinned launch writes to (D18).
#
# A stand-in defaults(1) and AGENT_PROFILE_PLATFORM let both run anywhere, so
# the two macOS-only rules are exercised in CI rather than shipped unrun.
# Nothing here reads the running machine's Dock: every path the tool can reach
# is inside the throwaway HOME, and the stand-in defaults answers one query
# and exits 1 for everything else.

# AUDIT_BUNDLE: the app bundle a case wants pinned. Empty means the fixture's
# own, which is the usual case.
AUDIT_BUNDLE=""

# audit: run agent-profile as if on macOS, against the fixture's stand-ins.
audit() {
    PATH="$HOME/fakebin:$PATH" \
    AGENT_PROFILE_PLATFORM=Darwin \
    AGENT_PROFILE_APP_BUNDLE="${AUDIT_BUNDLE:-$HOME/Claude.app}" \
    AGENT_PROFILE_APPLET_DIRS="$HOME/Applications:$HOME/Desktop" \
        "$AP" "$@"
}

# audit_elsewhere: the same fixture, on a platform that is not macOS. Both
# rules must be silent there and say in the document that they did not run.
audit_elsewhere() {
    PATH="$HOME/fakebin:$PATH" \
    AGENT_PROFILE_PLATFORM=test-not-darwin \
    AGENT_PROFILE_APP_BUNDLE="${AUDIT_BUNDLE:-$HOME/Claude.app}" \
    AGENT_PROFILE_APPLET_DIRS="$HOME/Applications:$HOME/Desktop" \
        "$AP" "$@"
}

# audit_fixture [dock-mode]: a throwaway HOME with one healthy profile and
# every stand-in tool.
#
# The stand-in security(1) is not optional. These cases pin the platform to
# Darwin, and on a real Mac that would send doctor at the runner's own
# Keychain. It is given tide's own service, so the Keychain-backed rules are
# quiet and a D17 assertion is testing D17.
audit_fixture() {
    HOME=$(new_home); export HOME
    AUDIT_BUNDLE=""
    mkdir -p "$HOME/Claude.app"
    fake_osa "$HOME/fakebin"
    "$AP" new tide >/dev/null 2>&1
    fixture_account "$HOME/.claude-tide" "m@tide.no" "org-t"
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-tide")"
    fake_defaults "$HOME/fakebin" "${1:-applets}"
}

# default_app_data: the directory the desktop app uses when no applet put a
# --user-data-dir in front of it.
default_app_data() {
    printf '%s\n' "$HOME/Library/Application Support/Claude"
}

# fixture_unpinned_app_data: that directory, as an unpinned launch leaves it.
# Only names are ever read, so a marker file is as good as the real contents.
fixture_unpinned_app_data() {
    mkdir -p "$(default_app_data)/claude-code/2.1.258"
    printf 'stand-in\n' > "$(default_app_data)/config.json"
}

# audit_json <expression>: one value out of a doctor document produced on the
# macOS path.
audit_json() {
    audit doctor --json 2>/dev/null | python3 -c '
import json, sys
value = eval(sys.argv[1], {"d": json.load(sys.stdin)})
print("" if value is None else value)
' "$1"
}

# ---------------------------------------------------------------------------
# D17: the real app in the Dock
# ---------------------------------------------------------------------------

case_d17_reports_the_app_in_the_dock() {
    audit_fixture app
    out=$(audit doctor 2>&1); status=$?
    assert_status 2 "$status" "$out" || return
    assert_contains "$out" "D17" || return
    assert_contains "$out" "desktop app itself is in the Dock" || return
    assert_contains "$out" "$HOME/Claude.app"
}

case_d17_quiet_when_only_the_applets_are_pinned() {
    # The healthy machine: applets in the Dock, the app itself out of it.
    audit_fixture applets
    out=$(audit doctor 2>&1)
    assert_not_contains "$out" "D17"
}

case_d17_quiet_on_an_empty_dock() {
    audit_fixture empty
    out=$(audit doctor 2>&1)
    assert_not_contains "$out" "D17"
}

# A Dock tile stores the path as a percent-encoded file:// URL, so a bundle
# under a directory with a space in it only matches once the URL is really
# decoded. Comparing the raw URL would make this rule silent on any Mac whose
# applications are not at a path of bare ASCII.
case_d17_decodes_a_percent_encoded_tile() {
    audit_fixture applets
    AUDIT_BUNDLE="$HOME/My Applications/Claude Desktop.app"
    mkdir -p "$AUDIT_BUNDLE"
    fake_defaults "$HOME/fakebin" app "$AUDIT_BUNDLE"
    out=$(audit doctor 2>&1)
    assert_contains "$out" "D17" || return
    assert_contains "$out" "$AUDIT_BUNDLE"
}

# A Dock that cannot be read is a "could not look", not a "nothing wrong".
case_d17_reports_an_unreadable_dock_as_not_run() {
    audit_fixture fails
    out=$(audit doctor 2>&1)
    assert_not_contains "$out" "D17" || return
    assert_equals "not_run" \
        "$(audit_json '[r for r in d["rules"] if r["rule"] == "D17"][0]["status"]')" || return
    assert_contains \
        "$(audit_json '[r for r in d["rules"] if r["rule"] == "D17"][0]["reason"]')" \
        "the Dock could not be read"
}

case_d17_is_silent_off_macos() {
    audit_fixture app
    out=$(audit_elsewhere doctor 2>&1)
    assert_not_contains "$out" "D17"
}

# The login items are the half of this rule that cannot run without root or a
# consent dialogue, so D17 is never a plain pass on macOS. docs/FACTS.md F22.
case_d17_says_the_login_items_were_not_checked() {
    audit_fixture applets
    assert_equals "limited" \
        "$(audit_json '[r for r in d["rules"] if r["rule"] == "D17"][0]["status"]')" || return
    assert_contains \
        "$(audit_json '[r for r in d["rules"] if r["rule"] == "D17"][0]["reason"]')" \
        "login items"
}

# ---------------------------------------------------------------------------
# The hint
# ---------------------------------------------------------------------------

case_d17_prints_the_hint_after_the_finding() {
    audit_fixture app
    out=$(audit doctor 2>&1)
    assert_contains "$out" "Drag the applets into the Dock" || return
    # After the finding, not before it: the hint is what to do about the line
    # above it.
    before=${out%%Drag the applets into the Dock*}
    assert_contains "$before" "D17"
}

case_the_hint_is_absent_when_the_dock_is_clean() {
    audit_fixture applets
    out=$(audit doctor 2>&1)
    assert_not_contains "$out" "Drag the applets into the Dock"
}

# --quiet is for a cron entry: it drops the advice and keeps the finding.
case_quiet_keeps_the_finding_and_drops_the_hint() {
    audit_fixture app
    out=$(audit doctor --quiet 2>&1)
    assert_contains "$out" "D17" || return
    assert_not_contains "$out" "Drag the applets into the Dock"
}

# ---------------------------------------------------------------------------
# D18: the default app data directory
# ---------------------------------------------------------------------------

case_d18_reports_the_default_app_data_directory() {
    audit_fixture applets
    fixture_unpinned_app_data
    out=$(audit doctor 2>&1); status=$?
    assert_status 2 "$status" "$out" || return
    assert_contains "$out" "D18" || return
    assert_contains "$out" "$(default_app_data)" || return
    assert_contains "$out" "last modified: "
}

# The timestamp is the whole answer in the branch where no account is stored,
# so a rule that printed an empty one would be reporting nothing.
case_d18_reports_a_real_timestamp() {
    audit_fixture applets
    fixture_unpinned_app_data
    out=$(audit doctor 2>&1)
    stamp=$(printf '%s\n' "$out" | sed -n 's/^ *last modified: //p' | head -1)
    case "$stamp" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
        *) fail "D18 did not print a UTC timestamp" "got: $stamp" ;;
    esac
}

# If the app ever does store an identity the way a config root does, the rule
# names it rather than reporting a path, the same way list names an account.
case_d18_names_an_account_when_one_is_stored() {
    audit_fixture applets
    fixture_unpinned_app_data
    fixture_account "$(default_app_data)" "stranger@example.com" "org-x"
    out=$(audit doctor 2>&1)
    assert_contains "$out" "D18" || return
    assert_contains "$out" "account: stranger@example.com" || return
    assert_not_contains "$out" "last modified: "
}

case_d18_quiet_when_the_directory_is_empty() {
    # Created by something and never written to is not evidence of a launch.
    audit_fixture applets
    mkdir -p "$(default_app_data)"
    out=$(audit doctor 2>&1)
    assert_not_contains "$out" "D18"
}

case_d18_quiet_when_there_is_no_such_directory() {
    audit_fixture applets
    out=$(audit doctor 2>&1)
    assert_not_contains "$out" "D18"
}

# A profile is allowed to claim that directory. Then it is somebody's profile
# rather than a stray, and D07 and D13 audit it like any other.
case_d18_quiet_when_a_profile_claims_the_directory() {
    audit_fixture applets
    fixture_unpinned_app_data
    "$AP" new desk --app-data "$(default_app_data)" >/dev/null 2>&1
    fixture_account "$HOME/.claude-desk" "m@desk.no" "org-d"
    fake_keychain "$HOME/fakebin" \
        "$(cred_service_for "$HOME/.claude-tide")" \
        "$(cred_service_for "$HOME/.claude-desk")"
    out=$(audit doctor 2>&1)
    assert_not_contains "$out" "D18"
}

case_d18_is_silent_off_macos() {
    audit_fixture applets
    fixture_unpinned_app_data
    out=$(audit_elsewhere doctor 2>&1)
    assert_not_contains "$out" "D18"
}

# ---------------------------------------------------------------------------
# The document
# ---------------------------------------------------------------------------

case_json_lists_both_new_rules() {
    audit_fixture applets
    out=$(audit doctor --json 2>/dev/null)
    printf '%s\n' "$out" | python3 -m json.tool >/dev/null 2>&1 || {
        fail "doctor --json is not valid JSON" "$out"; return
    }
    assert_equals "18" "$(audit_json 'len(d["rules"])')" || return
    assert_equals "D18" "$(audit_json 'd["rules"][-1]["rule"]')" || return
    assert_contains "$(audit_json '[r for r in d["rules"] if r["rule"] == "D17"][0]["title"]')" \
        "Dock"
}

case_json_reports_both_as_fail_when_they_fire() {
    audit_fixture app
    fixture_unpinned_app_data
    out=$(audit doctor --json 2>/dev/null)
    printf '%s\n' "$out" | python3 -m json.tool >/dev/null 2>&1 || {
        fail "doctor --json is not valid JSON" "$out"; return
    }
    assert_equals "fail" \
        "$(audit_json '[r for r in d["rules"] if r["rule"] == "D17"][0]["status"]')" || return
    assert_equals "fail" \
        "$(audit_json '[r for r in d["rules"] if r["rule"] == "D18"][0]["status"]')" || return
    # The subject is the offender itself, which is what a consumer acts on.
    assert_equals "$HOME/Claude.app" \
        "$(audit_json '[f for f in d["findings"] if f["rule"] == "D17"][0]["subject"]')" || return
    assert_equals "$(default_app_data)" \
        "$(audit_json '[f for f in d["findings"] if f["rule"] == "D18"][0]["subject"]')"
}

# The document is where a clean run on the wrong platform stops looking like a
# clean run on the right one.
case_json_marks_both_not_run_off_macos() {
    audit_fixture app
    fixture_unpinned_app_data
    out=$(PATH="$HOME/fakebin:$PATH" AGENT_PROFILE_PLATFORM=test-not-darwin \
        AGENT_PROFILE_APPLET_DIRS="$HOME/Applications:$HOME/Desktop" \
        "$AP" doctor --json 2>/dev/null)
    printf '%s\n' "$out" | python3 -m json.tool >/dev/null 2>&1 || {
        fail "doctor --json is not valid JSON" "$out"; return
    }
    for _rule in D17 D18; do
        _got=$(printf '%s\n' "$out" | python3 -c '
import json, sys
rule = [r for r in json.load(sys.stdin)["rules"] if r["rule"] == sys.argv[1]][0]
print("%s|%s" % (rule["status"], rule["reason"] or ""))
' "$_rule")
        case "$_got" in
            not_run\|*test-not-darwin*) ;;
            *) fail "$_rule should be not_run naming the platform" "got: $_got" ;;
        esac
    done
}

run_case "D17 reports the app itself in the Dock"      case_d17_reports_the_app_in_the_dock
run_case "D17 quiet when only applets are pinned"      case_d17_quiet_when_only_the_applets_are_pinned
run_case "D17 quiet on an empty Dock"                  case_d17_quiet_on_an_empty_dock
run_case "D17 decodes a percent-encoded tile"          case_d17_decodes_a_percent_encoded_tile
run_case "D17 reports an unreadable Dock as not_run"   case_d17_reports_an_unreadable_dock_as_not_run
run_case "D17 is silent off macOS"                     case_d17_is_silent_off_macos
run_case "D17 says the login items were not checked"   case_d17_says_the_login_items_were_not_checked
run_case "the D17 hint follows the finding"            case_d17_prints_the_hint_after_the_finding
run_case "no hint when the Dock is clean"              case_the_hint_is_absent_when_the_dock_is_clean
run_case "--quiet keeps the finding, drops the hint"   case_quiet_keeps_the_finding_and_drops_the_hint
run_case "D18 reports the default app data directory"  case_d18_reports_the_default_app_data_directory
run_case "D18 prints a real timestamp"                 case_d18_reports_a_real_timestamp
run_case "D18 names an account when one is stored"     case_d18_names_an_account_when_one_is_stored
run_case "D18 quiet when the directory is empty"       case_d18_quiet_when_the_directory_is_empty
run_case "D18 quiet when there is no such directory"   case_d18_quiet_when_there_is_no_such_directory
run_case "D18 quiet when a profile claims it"          case_d18_quiet_when_a_profile_claims_the_directory
run_case "D18 is silent off macOS"                     case_d18_is_silent_off_macos
run_case "doctor --json lists D17 and D18"             case_json_lists_both_new_rules
run_case "doctor --json reports both as fail"          case_json_reports_both_as_fail_when_they_fire
run_case "doctor --json marks both not_run off macOS"  case_json_marks_both_not_run_off_macos
