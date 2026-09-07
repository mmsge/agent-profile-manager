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
    assert_equals "export CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet" "$("$AP" env bouvet)"
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
run_case "an unknown profile exits 1"                 case_unknown_profile_exits_1
run_case "an unknown agent= is a hard error"          case_unknown_agent_in_registry_is_hard_error
