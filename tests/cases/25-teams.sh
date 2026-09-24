# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# teams: the per-profile agent teams switch, and where its export reaches.
#
# The switch is one line in the registry entry and one variable in the
# environment of what the launchers start (docs/FACTS.md F26). What these
# cases pin is the reach: run, shell and env carry it, the desktop launcher
# does not, and nothing is written inside the root for it. The IDE half of
# the reach is pinned in 75-ide.sh, beside the fixture it needs.

TEAMS_VAR="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"

case_teams_is_off_for_a_new_profile() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$("$AP" teams brygga 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Agent teams are off for brygga" || return
    assert_contains "$out" "teams brygga on"
}

case_teams_on_is_recorded_outside_the_root() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$("$AP" teams brygga on 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Agent teams on for brygga" || return
    assert_equals "on" "$(sed -n 's/^agent_teams=//p' "$HOME/.config/agent-profiles/brygga.conf")" || return
    # Nothing inside the root: the switch must never become a settings.json.
    assert_equals "" "$(ls -A "$HOME/.claude-brygga")"
}

case_teams_on_keeps_the_rest_of_the_entry() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    before=$(grep -v '^agent_teams=' "$HOME/.config/agent-profiles/brygga.conf")
    "$AP" teams brygga on >/dev/null 2>&1
    after=$(grep -v '^agent_teams=' "$HOME/.config/agent-profiles/brygga.conf")
    assert_equals "$before" "$after"
}

case_run_exports_the_variable_when_teams_is_on() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" run brygga --version 2>&1)
    assert_equals "CLAUDE_CONFIG_DIR=$HOME/.claude-brygga $TEAMS_VAR=1 claude --version" "$out"
}

case_run_does_not_export_it_when_teams_is_off() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" run brygga --version 2>&1)
    assert_not_contains "$out" "$TEAMS_VAR"
}

case_a_bare_profile_name_carries_it_too() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" brygga 2>&1)
    assert_contains "$out" "$TEAMS_VAR=1 claude"
}

case_shell_exports_the_variable_when_teams_is_on() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$(SHELL=/bin/zsh AGENT_PROFILE_DRY_RUN=1 "$AP" shell brygga 2>/dev/null)
    assert_equals "CLAUDE_CONFIG_DIR=$HOME/.claude-brygga $TEAMS_VAR=1 /bin/zsh" "$out"
}

case_env_prints_a_second_export_when_teams_is_on() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$("$AP" env brygga 2>&1)
    assert_contains "$out" "export CLAUDE_CONFIG_DIR='$HOME/.claude-brygga'" || return
    assert_contains "$out" "export $TEAMS_VAR=1"
}

case_env_prints_one_export_when_teams_is_off() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$("$AP" env brygga 2>&1)
    assert_equals "export CLAUDE_CONFIG_DIR='$HOME/.claude-brygga'" "$out"
}

# The exports env prints must be what a shell can eval, and after eval the
# agent must see both, which is what which reports from the environment.
case_env_output_evals_to_a_pinned_shell_with_teams() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    # shellcheck disable=SC2016  # the inner shell expands these, not this one
    out=$(env -u CLAUDE_CONFIG_DIR -u "$TEAMS_VAR" "${BASH:-/bin/bash}" -c \
        'eval "$("$1" env brygga)" && "$1" which' _ "$AP" 2>&1)
    assert_contains "$out" "Pinned to brygga" || return
    assert_contains "$out" "$TEAMS_VAR=1   (agent teams on)"
}

# which reads the environment, never the registry: a shell pinned before the
# switch was thrown has no such export, and which must not claim it has.
case_which_reports_teams_from_the_environment_not_the_registry() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$(env -u "$TEAMS_VAR" CLAUDE_CONFIG_DIR="$HOME/.claude-brygga" "$AP" which 2>&1)
    assert_contains "$out" "Pinned to brygga" || return
    assert_not_contains "$out" "agent teams"
}

case_which_label_is_unchanged_by_teams() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude-brygga" "$AP" which --label)
    assert_equals "brygga" "$out"
}

case_teams_off_stops_the_export() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$("$AP" teams brygga off 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Agent teams off for brygga" || return
    run=$(AGENT_PROFILE_DRY_RUN=1 "$AP" run brygga 2>&1)
    assert_equals "CLAUDE_CONFIG_DIR=$HOME/.claude-brygga claude" "$run" || return
    envout=$("$AP" env brygga 2>&1)
    assert_not_contains "$envout" "$TEAMS_VAR"
}

# A second run must say it changed nothing, so an already-on switch and one
# that never took cannot look the same, the way app reports a second run.
case_teams_on_twice_says_nothing_to_do() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$("$AP" teams brygga on 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "already on" || return
    assert_contains "$out" "Nothing to do"
}

case_teams_off_on_a_fresh_profile_says_nothing_to_do() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$("$AP" teams brygga off 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "already off"
}

case_teams_status_says_where_the_export_reaches() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$("$AP" teams brygga 2>&1)
    assert_contains "$out" "Agent teams are on for brygga" || return
    assert_contains "$out" "run, shell, env, code and idea"
}

# The desktop app has no agent teams, so the switch must not reach the
# desktop launcher: an applet line carrying a variable the app ignores would
# be a launcher claiming more than it does, and D13 audits that line.
case_desktop_launch_is_unchanged_by_teams() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    "$AP" teams brygga on >/dev/null 2>&1
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" desktop brygga 2>&1)
    assert_contains "$out" "--env CLAUDE_CONFIG_DIR=$HOME/.claude-brygga" || return
    assert_not_contains "$out" "$TEAMS_VAR"
}

case_teams_on_names_the_desktop_gap() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$("$AP" teams brygga on 2>&1)
    assert_contains "$out" "desktop app" || return
    assert_contains "$out" "desktop and app are unchanged"
}

case_teams_explain_names_the_fact() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$("$AP" teams brygga --explain 2>&1)
    assert_contains "$out" "docs/FACTS.md F26" || return
    assert_contains "$out" "claude -p"
}

case_teams_rejects_a_state_that_is_not_on_or_off() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$("$AP" teams brygga maybe 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "on or off, not 'maybe'" || return
    assert_equals "" "$(sed -n 's/^agent_teams=//p' "$HOME/.config/agent-profiles/brygga.conf")"
}

case_teams_rejects_an_unknown_profile() {
    HOME=$(new_home); export HOME
    out=$("$AP" teams nobody on 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "no such profile 'nobody'"
}

case_teams_needs_a_profile() {
    HOME=$(new_home); export HOME
    out=$("$AP" teams 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "usage:"
}

# An entry written before the switch existed has no agent_teams line and
# must read as off, and so must a value nobody wrote by hand.
case_a_registry_value_other_than_on_reads_as_off() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    printf 'agent_teams=yes\n' >> "$HOME/.config/agent-profiles/brygga.conf"
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" run brygga 2>&1)
    assert_not_contains "$out" "$TEAMS_VAR" || return
    assert_contains "$("$AP" teams brygga 2>&1)" "are off"
}

run_case "teams is off for a new profile"                  case_teams_is_off_for_a_new_profile
run_case "teams on is recorded outside the root"           case_teams_on_is_recorded_outside_the_root
run_case "teams on keeps the rest of the entry"            case_teams_on_keeps_the_rest_of_the_entry
run_case "run exports the variable when teams is on"       case_run_exports_the_variable_when_teams_is_on
run_case "run does not export it when teams is off"        case_run_does_not_export_it_when_teams_is_off
run_case "a bare profile name carries it too"              case_a_bare_profile_name_carries_it_too
run_case "shell exports the variable when teams is on"     case_shell_exports_the_variable_when_teams_is_on
run_case "env prints a second export when teams is on"     case_env_prints_a_second_export_when_teams_is_on
run_case "env prints one export when teams is off"         case_env_prints_one_export_when_teams_is_off
run_case "env output evals to a pinned shell with teams"   case_env_output_evals_to_a_pinned_shell_with_teams
run_case "which reports teams from the environment"        case_which_reports_teams_from_the_environment_not_the_registry
run_case "which --label is unchanged by teams"             case_which_label_is_unchanged_by_teams
run_case "teams off stops the export"                      case_teams_off_stops_the_export
run_case "teams on twice says nothing to do"               case_teams_on_twice_says_nothing_to_do
run_case "teams off on a fresh profile says nothing to do" case_teams_off_on_a_fresh_profile_says_nothing_to_do
run_case "teams status says where the export reaches"      case_teams_status_says_where_the_export_reaches
run_case "desktop launch is unchanged by teams"            case_desktop_launch_is_unchanged_by_teams
run_case "teams on names the desktop gap"                  case_teams_on_names_the_desktop_gap
run_case "teams --explain names the fact"                  case_teams_explain_names_the_fact
run_case "teams rejects a state that is not on or off"     case_teams_rejects_a_state_that_is_not_on_or_off
run_case "teams rejects an unknown profile"                case_teams_rejects_an_unknown_profile
run_case "teams needs a profile"                           case_teams_needs_a_profile
run_case "a registry value other than on reads as off"     case_a_registry_value_other_than_on_reads_as_off
