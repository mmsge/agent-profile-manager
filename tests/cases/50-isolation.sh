# shellcheck shell=bash
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# The invariant the whole tool exists to protect: no file is ever shared,
# symlinked or copied between two roots.

case_no_symlinks_anywhere_under_a_root() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new highsoft >/dev/null 2>&1
    found=$(find "$HOME/.claude-bouvet" "$HOME/.claude-highsoft" -type l 2>/dev/null)
    assert_equals "" "$found"
}

case_a_second_profile_does_not_inherit_the_first() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    # Give the first root settings and a hook, as a real profile would have.
    printf '{"model":"opus"}\n' > "$HOME/.claude-bouvet/settings.json"
    mkdir -p "$HOME/.claude-bouvet/skills/example"
    "$AP" new highsoft >/dev/null 2>&1
    if [ -n "$(ls -A "$HOME/.claude-highsoft" 2>/dev/null)" ]; then
        fail "the new root inherited something" "$(ls -A "$HOME/.claude-highsoft")"
    fi
}

case_registry_lives_outside_every_root() {
    # Putting the tool's own state inside a root would make that state
    # account-specific, which is the opposite of the point.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    case "$HOME/.config/agent-profiles/bouvet.conf" in
        "$HOME/.claude"*) fail "the registry is inside a config root" ;;
    esac
    [ -f "$HOME/.config/agent-profiles/bouvet.conf" ] || fail "no registry entry"
}

case_source_never_copies_or_links_between_roots() {
    # Criterion 4 asks a reviewer to verify this by inspection. Assert it too,
    # so a future change cannot quietly introduce it.
    hits=$(grep -nE '(^|[^[:alnum:]_])(ln[[:space:]]+-s|cp[[:space:]]+-|rsync|install[[:space:]]+-m)' \
        "$AP" | grep -v '^[0-9]*: *#' || true)
    assert_equals "" "$hits"
}

case_source_never_reads_credential_content() {
    # The tool may check that a credential exists. It must never read one, and
    # must never call security with -g.
    hits=$(grep -nE 'security[^|]*-g|dump-keychain[^|]*-g|find-generic-password' "$AP" \
        | grep -v '^[0-9]*: *#' || true)
    assert_equals "" "$hits"
}

case_no_command_writes_to_the_agents_state_file() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
    before=$(cat "$HOME/.claude-bouvet/.claude.json")
    "$AP" list >/dev/null 2>&1
    "$AP" doctor >/dev/null 2>&1
    "$AP" verify >/dev/null 2>&1
    "$AP" explain >/dev/null 2>&1
    after=$(cat "$HOME/.claude-bouvet/.claude.json")
    assert_equals "$before" "$after"
}

case_explain_states_the_scheme() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$("$AP" explain 2>&1); status=$?
    assert_status 0 "$status" || return
    assert_contains "$out" "No symlinks" || return
    assert_contains "$out" "keyed to the root path" || return
    assert_contains "$out" "$HOME/.claude-bouvet"
}

case_help_and_version() {
    HOME=$(new_home); export HOME
    assert_contains "$("$AP" version)" "agent-profile" || return
    assert_contains "$("$AP" help)" "EXIT CODES" || return
    out=$("$AP" nonsense 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown command"
}

run_case "no symlinks under any root"                 case_no_symlinks_anywhere_under_a_root
run_case "a second profile inherits nothing"          case_a_second_profile_does_not_inherit_the_first
run_case "the registry lives outside every root"      case_registry_lives_outside_every_root
run_case "the source never copies between roots"      case_source_never_copies_or_links_between_roots
run_case "the source never reads credentials"         case_source_never_reads_credential_content
run_case "no command writes the agent state file"     case_no_command_writes_to_the_agents_state_file
run_case "explain states the scheme"                  case_explain_states_the_scheme
run_case "help, version and an unknown command"       case_help_and_version
