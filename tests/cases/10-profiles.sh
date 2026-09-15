# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# new, list, path, env: profile lifecycle.

case_new_creates_a_root_holding_only_its_registration() {
    HOME=$(new_home); export HOME
    out=$("$AP" new brygga 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    [ -d "$HOME/.claude-brygga" ] || { fail "root was not created"; return; }
    # Nothing is ever seeded or copied into the root. The one thing in it is
    # the state file the agent's CLI wrote the sessions server registration
    # into (docs/FACTS.md F23), and that is the whole listing.
    assert_equals ".claude.json" "$(ls -A "$HOME/.claude-brygga" 2>/dev/null)" || return
    assert_contains "$out" "Sessions server: on" || return
    [ -d "$HOME/Library/Application Support/Claude-Brygga" ] || \
        fail "app data dir was not created"
}

# Without the agent on PATH there is nothing to register with, and the root
# is then genuinely empty. new still succeeds, and says what to run later.
case_new_creates_an_empty_root_when_the_agent_is_absent() {
    HOME=$(new_home); export HOME
    out=$(AGENT_PROFILE_MCP_REGISTRAR="$HOME/no-such-claude" "$AP" new brygga 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    if [ -n "$(ls -A "$HOME/.claude-brygga" 2>/dev/null)" ]; then
        fail "root is not empty" "$(ls -A "$HOME/.claude-brygga")"
        return
    fi
    assert_contains "$out" "not registered, because claude is not on PATH" || return
    assert_contains "$out" "agent-profile mcp on brygga"
}

case_new_sets_mode_700() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    mode=$(file_mode "$HOME/.claude-brygga")
    assert_equals "700" "$mode"
}

case_new_sets_mode_700_on_the_app_data_dir() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    assert_equals "700" "$(file_mode "$HOME/Library/Application Support/Claude-Brygga")"
}

case_new_reports_tightening_the_app_data_mode() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/Library/Application Support/Claude-Torg"
    chmod 755 "$HOME/Library/Application Support/Claude-Torg"
    out=$("$AP" new torg 2>&1)
    assert_contains "$out" "app data directory was mode 755 and became 700" || return
    assert_equals "700" "$(file_mode "$HOME/Library/Application Support/Claude-Torg")"
}

case_new_writes_four_keys() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    conf="$HOME/.config/agent-profiles/brygga.conf"
    [ -f "$conf" ] || { fail "no registry entry at $conf"; return; }
    got=$(cut -d= -f1 < "$conf" | tr '\n' ' ')
    assert_equals "agent root app_data created " "$got"
}

case_new_is_idempotent() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    before=$(cat "$HOME/.config/agent-profiles/brygga.conf")
    out=$("$AP" new brygga 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "already registered" || return
    after=$(cat "$HOME/.config/agent-profiles/brygga.conf")
    assert_equals "$before" "$after"
}

case_new_refuses_to_repoint() {
    # Credentials are keyed to the root path, so repointing would silently
    # invalidate the login. It must refuse rather than do it.
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    out=$("$AP" new brygga --root "$HOME/elsewhere" 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "credentials are keyed to the root path" || return
    [ -d "$HOME/elsewhere" ] && fail "it created the new root anyway"
}

case_new_rejects_bad_names() {
    HOME=$(new_home); export HOME
    out=$("$AP" new "has space" 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "invalid profile name"
}

case_new_rejects_unknown_agent() {
    HOME=$(new_home); export HOME
    out=$("$AP" new x --agent ollama 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown agent"
}

case_new_warns_root_has_no_guardrails() {
    # The rationale for why an empty root has no guardrails is long-form now,
    # restored by --explain; the default form says only what happened.
    HOME=$(new_home); export HOME
    out=$("$AP" new brygga --explain 2>&1)
    assert_contains "$out" "no settings, no hooks"
}

case_list_reports_account_and_sessions() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    fixture_account "$HOME/.claude-brygga" "markus@brygga.no" "org-abc"
    fixture_transcript "$HOME/.claude-brygga" "-Users-markus-dev-a" "/Users/markus/dev/a"
    out=$("$AP" list 2>&1)
    assert_contains "$out" "markus@brygga.no" || return
    assert_contains "$out" "org-abc" || return
    assert_contains "$out" "sessions  1"
}

case_list_flags_missing_root() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    rm -rf "$HOME/.claude-brygga"
    out=$("$AP" list 2>&1)
    assert_contains "$out" "MISSING"
}

case_path_and_env() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    assert_equals "$HOME/.claude-brygga" "$("$AP" path brygga)" || return
    # Assert what eval produces, not the exact quoting, so the quoting can
    # change without the test caring.
    got=$(eval "$("$AP" env brygga)"; printf '%s' "$CLAUDE_CONFIG_DIR")
    assert_equals "$HOME/.claude-brygga" "$got"
}

case_env_survives_a_space_in_the_path() {
    # env output is fed straight to eval, and the conventional app data path
    # under ~/Library/Application Support contains a space.
    HOME=$(new_home); export HOME
    "$AP" new work --root "$HOME/My Roots/claude-work" >/dev/null 2>&1
    got=$(eval "$("$AP" env work)"; printf '%s' "$CLAUDE_CONFIG_DIR")
    assert_equals "$HOME/My Roots/claude-work" "$got"
}

case_env_survives_an_apostrophe_in_the_path() {
    HOME=$(new_home); export HOME
    "$AP" new tricky --root "$HOME/markus's roots" >/dev/null 2>&1
    got=$(eval "$("$AP" env tricky)"; printf '%s' "$CLAUDE_CONFIG_DIR")
    assert_equals "$HOME/markus's roots" "$got"
}

case_a_spaced_root_works_end_to_end() {
    HOME=$(new_home); export HOME
    "$AP" new work --root "$HOME/My Roots/claude-work" >/dev/null 2>&1
    fixture_account "$HOME/My Roots/claude-work" "m@example.com" "org-x"
    fixture_transcript "$HOME/My Roots/claude-work" "-Users-m-dev-a" "/Users/m/dev/a"
    assert_contains "$("$AP" list 2>&1)" "m@example.com" || return
    out=$("$AP" doctor 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    label=$(CLAUDE_CONFIG_DIR="$HOME/My Roots/claude-work" "$AP" which --label)
    assert_equals "claude-work" "$label"
}

case_unknown_profile_exits_1() {
    HOME=$(new_home); export HOME
    out=$("$AP" path nope 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "no such profile"
}

case_unknown_agent_in_registry_is_hard_error() {
    # An unknown agent= must never fall back to claude silently.
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.config/agent-profiles"
    printf 'agent=ollama\nroot=%s/x\n' "$HOME" > "$HOME/.config/agent-profiles/weird.conf"
    out=$("$AP" path weird 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown agent 'ollama'"
}

# Adopting a root that already holds data is the entry point for a machine
# that was set up by hand, so the two things it must never leave in doubt are
# whether the data survived and whether anything was seeded into it.
case_new_adopts_a_populated_root_without_touching_it() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.claude-torg/projects/-U-x-w"
    fixture_account "$HOME/.claude-torg" "m@torg.no" "org-t"
    fixture_transcript "$HOME/.claude-torg" "-U-x-w" "/U/x/w"
    printf '{"model":"opus","hooks":{"Stop":[]}}\n' > "$HOME/.claude-torg/settings.json"
    before=$(find "$HOME/.claude-torg" -type f | sort)

    out=$("$AP" new torg --explain 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "adopted rather than created" || return
    assert_contains "$out" "1 session(s)" || return

    # The claim in that message has to be true: the same files, the settings
    # byte for byte, and the one addition named as such, inside a file that
    # was already there.
    assert_equals "$before" "$(find "$HOME/.claude-torg" -type f | sort)" || return
    assert_equals '{"model":"opus","hooks":{"Stop":[]}}' \
        "$(cat "$HOME/.claude-torg/settings.json")" || return
    assert_contains "$out" "The one line added is the sessions server registration" || return
    assert_contains "$out" "Sessions server: on" || return
    # The account the adopted root already had is still there beside it.
    assert_contains "$("$AP" list 2>&1)" "m@torg.no"
}

# An adopted root may already carry a "sessions" server of its owner's own.
# That entry is not this tool's, so new leaves it alone and says so, and the
# adoption still succeeds.
case_new_leaves_a_foreign_sessions_entry_alone() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.claude-torg"
    printf '{"oauthAccount":{"emailAddress":"m@torg.no"},"mcpServers":{"sessions":{"type":"stdio","command":"/usr/bin/theirs","args":["--serve"]}}}\n' \
        > "$HOME/.claude-torg/.claude.json"
    before=$(cat "$HOME/.claude-torg/.claude.json")
    out=$("$AP" new torg 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "not this tool's" || return
    assert_contains "$out" "left alone" || return
    assert_equals "$before" "$(cat "$HOME/.claude-torg/.claude.json")"
}

# Telling someone their live root "is empty" is false and alarming, and the
# login prompt is wrong too when the root is already signed in.
case_new_does_not_call_a_populated_root_empty() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.claude-torg"
    fixture_account "$HOME/.claude-torg" "m@torg.no" "org-t"

    out=$("$AP" new torg 2>&1)
    assert_not_contains "$out" "The root is empty" || return
    assert_not_contains "$out" "it will ask you to log in"
}

case_new_reports_tightening_the_mode_on_adoption() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.claude-torg"
    fixture_account "$HOME/.claude-torg" "m@torg.no" "org-t"
    chmod 755 "$HOME/.claude-torg"

    out=$("$AP" new torg 2>&1)
    assert_contains "$out" "mode 755 became 700" || return
    assert_equals "700" "$(file_mode "$HOME/.claude-torg")"
}

# A fresh root is still created, not adopted, so the guardrails warning that
# matters for a fresh profile does not go missing under --explain.
case_new_still_explains_a_fresh_root() {
    HOME=$(new_home); export HOME
    out=$("$AP" new fresh --explain 2>&1)
    assert_contains "$out" "The root holds nothing from any other profile" || return
    assert_not_contains "$out" "adopted rather than created"
}

# The short default form leaves that paragraph out, and still says what to
# run next.
case_new_short_form_still_names_a_fresh_root() {
    HOME=$(new_home); export HOME
    out=$("$AP" new fresh 2>&1)
    assert_not_contains "$out" "The root holds nothing" || return
    assert_contains "$out" "Next: agent-profile run fresh"
}

# A profile at the default root permanently silences D01, because an unpinned
# run and that profile's own runs are identical on disk. Nothing else says so,
# and by the time it matters the choice cannot be undone: relocating a root
# invalidates its login. The full reasoning is behind --explain now; the short
# form still names the fact so it is never a silent surprise.
case_new_warns_when_a_profile_claims_the_default_root() {
    HOME=$(new_home); export HOME
    out=$("$AP" new brygga --root "$HOME/.claude" --explain 2>&1)
    assert_contains "$out" "owns the default root" || return
    assert_contains "$out" "D01 goes quiet" || return
    assert_contains "$out" "F06"
}

case_new_short_form_still_names_the_default_root() {
    HOME=$(new_home); export HOME
    out=$("$AP" new brygga --root "$HOME/.claude" 2>&1)
    assert_contains "$out" "owns the default root" || return
    assert_not_contains "$out" "D01 goes quiet"
}

case_new_is_silent_about_it_for_an_ordinary_root() {
    HOME=$(new_home); export HOME
    out=$("$AP" new brygga 2>&1)
    assert_not_contains "$out" "owns the default root"
}

case_a_bare_profile_name_runs_it() {
    HOME=$(new_home); export HOME
    "$AP" new torg >/dev/null 2>&1
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" torg 2>&1)
    assert_contains "$out" "CLAUDE_CONFIG_DIR=$HOME/.claude-torg claude"
}

case_a_bare_profile_name_forwards_arguments() {
    HOME=$(new_home); export HOME
    "$AP" new torg >/dev/null 2>&1
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" torg --continue --verbose 2>&1)
    assert_contains "$out" "claude --continue --verbose"
}

# A profile can never shadow a subcommand: every command is matched before the
# fallback. The worst case for a profile named after one is that it needs the
# explicit run form, not that anything breaks.
case_a_subcommand_wins_over_a_profile_of_the_same_name() {
    HOME=$(new_home); export HOME
    "$AP" new list >/dev/null 2>&1
    out=$("$AP" list 2>&1)
    assert_contains "$out" "sessions" || return

    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" run list 2>&1)
    assert_contains "$out" "CLAUDE_CONFIG_DIR=$HOME/.claude-list claude"
}

case_neither_a_command_nor_a_profile_names_both() {
    HOME=$(new_home); export HOME
    out=$("$AP" nonsense 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown command or profile 'nonsense'" || return
    assert_contains "$out" "list for profiles"
}

run_case "new creates a root holding only its registration" case_new_creates_a_root_holding_only_its_registration
run_case "new creates an empty root when the agent is absent" case_new_creates_an_empty_root_when_the_agent_is_absent
run_case "new sets mode 700"                          case_new_sets_mode_700
run_case "new sets mode 700 on the app data dir"      case_new_sets_mode_700_on_the_app_data_dir
run_case "new reports tightening the app data mode"   case_new_reports_tightening_the_app_data_mode
run_case "new writes exactly four registry keys"      case_new_writes_four_keys
run_case "new is idempotent"                          case_new_is_idempotent
run_case "new refuses to repoint an existing profile" case_new_refuses_to_repoint
run_case "new rejects invalid names"                  case_new_rejects_bad_names
run_case "new rejects an unknown agent"               case_new_rejects_unknown_agent
run_case "new warns a fresh root has no guardrails"   case_new_warns_root_has_no_guardrails
run_case "list reports account, org and sessions"     case_list_reports_account_and_sessions
run_case "list flags a missing root"                  case_list_flags_missing_root
run_case "path and env print the pinned root"         case_path_and_env
run_case "env survives a space in the path"           case_env_survives_a_space_in_the_path
run_case "env survives an apostrophe in the path"    case_env_survives_an_apostrophe_in_the_path
run_case "a spaced root works end to end"            case_a_spaced_root_works_end_to_end
run_case "an unknown profile exits 1"                 case_unknown_profile_exits_1
run_case "an unknown agent= is a hard error"          case_unknown_agent_in_registry_is_hard_error
run_case "new adopts a populated root untouched"   case_new_adopts_a_populated_root_without_touching_it
run_case "new leaves a foreign sessions entry alone" case_new_leaves_a_foreign_sessions_entry_alone
run_case "new does not call a populated root empty" case_new_does_not_call_a_populated_root_empty
run_case "new reports tightening the mode"         case_new_reports_tightening_the_mode_on_adoption
run_case "new still explains a fresh root"         case_new_still_explains_a_fresh_root
run_case "new's short form still names a fresh root"   case_new_short_form_still_names_a_fresh_root
run_case "new warns about the default root"       case_new_warns_when_a_profile_claims_the_default_root
run_case "new's short form still names the default root" case_new_short_form_still_names_the_default_root
run_case "new is silent for an ordinary root"     case_new_is_silent_about_it_for_an_ordinary_root
run_case "a bare profile name runs it"            case_a_bare_profile_name_runs_it
run_case "a bare profile name forwards arguments" case_a_bare_profile_name_forwards_arguments
run_case "a subcommand wins over a profile"       case_a_subcommand_wins_over_a_profile_of_the_same_name
run_case "neither a command nor a profile"        case_neither_a_command_nor_a_profile_names_both
