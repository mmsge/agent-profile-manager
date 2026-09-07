# shellcheck shell=bash
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# new, list, path, env: profile lifecycle.

case_new_creates_empty_root() {
    HOME=$(new_home); export HOME
    out=$("$AP" new bouvet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    [ -d "$HOME/.claude-bouvet" ] || { fail "root was not created"; return; }
    # The root must be EMPTY. Nothing is ever seeded or copied into it.
    if [ -n "$(ls -A "$HOME/.claude-bouvet" 2>/dev/null)" ]; then
        fail "root is not empty" "$(ls -A "$HOME/.claude-bouvet")"
        return
    fi
    [ -d "$HOME/Library/Application Support/Claude-Bouvet" ] || \
        fail "app data dir was not created"
}

case_new_sets_mode_700() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    mode=$(file_mode "$HOME/.claude-bouvet")
    assert_equals "700" "$mode"
}

case_new_writes_four_keys() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    conf="$HOME/.config/agent-profiles/bouvet.conf"
    [ -f "$conf" ] || { fail "no registry entry at $conf"; return; }
    got=$(cut -d= -f1 < "$conf" | tr '\n' ' ')
    assert_equals "agent root app_data created " "$got"
}

case_new_is_idempotent() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    before=$(cat "$HOME/.config/agent-profiles/bouvet.conf")
    out=$("$AP" new bouvet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "already registered" || return
    after=$(cat "$HOME/.config/agent-profiles/bouvet.conf")
    assert_equals "$before" "$after"
}

case_new_refuses_to_repoint() {
    # Credentials are keyed to the root path, so repointing would silently
    # invalidate the login. It must refuse rather than do it.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$("$AP" new bouvet --root "$HOME/elsewhere" 2>&1); status=$?
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
    HOME=$(new_home); export HOME
    out=$("$AP" new bouvet 2>&1)
    assert_contains "$out" "no settings, no hooks"
}

case_list_reports_account_and_sessions() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "markus@bouvet.no" "org-abc"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-markus-dev-a" "/Users/markus/dev/a"
    out=$("$AP" list 2>&1)
    assert_contains "$out" "markus@bouvet.no" || return
    assert_contains "$out" "org-abc" || return
    assert_contains "$out" "sessions  1"
}

case_list_flags_missing_root() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    rm -rf "$HOME/.claude-bouvet"
    out=$("$AP" list 2>&1)
    assert_contains "$out" "MISSING"
}

case_path_and_env() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    assert_equals "$HOME/.claude-bouvet" "$("$AP" path bouvet)" || return
    # Assert what eval produces, not the exact quoting, so the quoting can
    # change without the test caring.
    got=$(eval "$("$AP" env bouvet)"; printf '%s' "$CLAUDE_CONFIG_DIR")
    assert_equals "$HOME/.claude-bouvet" "$got"
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

run_case "new creates an empty root"                  case_new_creates_empty_root
run_case "new sets mode 700"                          case_new_sets_mode_700
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
