# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
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

# AP_SOURCE is the script itself. $AP is a two-line shim that re-executes it
# under the harness's bash, so grepping $AP proves nothing about the source.
# Both invariants below once passed against the shim while one of them would
# have failed against the real script, which is the vacuous pass this note
# exists to prevent.
AP_SOURCE="$ROOT/bin/agent-profile"

case_source_never_copies_or_links_between_roots() {
    # Criterion 4 asks a reviewer to verify this by inspection. Assert it too,
    # so a future change cannot quietly introduce it.
    hits=$(grep -nE '(^|[^[:alnum:]_])(ln[[:space:]]+-s|cp[[:space:]]+-|rsync|install[[:space:]]+-m)' \
        "$AP_SOURCE" | grep -v '^[0-9]*: *#' || true)
    assert_equals "" "$hits"
}

case_source_never_reads_credential_content() {
    # The tool may check that a credential exists, which is find-generic-password
    # with its output discarded. It must never ask for the secret itself: -g or
    # -w on find-generic-password, or -d on dump-keychain.
    hits=$(grep -nE 'find-generic-password[^|]*[[:space:]]-[gw]([[:space:]]|$)|dump-keychain[^|]*[[:space:]]-d([[:space:]]|$)' \
        "$AP_SOURCE" | grep -v '^[0-9]*: *#' || true)
    assert_equals "" "$hits" || return
    # Prove the grep is reading the real thing. The existence check has to be
    # in there, or this case is asserting against the wrong file.
    if ! grep -q 'find-generic-password' "$AP_SOURCE"; then
        fail "no credential existence check in $AP_SOURCE, so this case is not reading the source"
    fi
}

case_source_never_uses_predictable_temp_names() {
    # A temp path built from $$ is guessable, and under a shared TMPDIR that is
    # a symlink race waiting to happen. Every temporary file or directory has
    # to come from mktemp.
    # shellcheck disable=SC2016  # the pattern is a literal, not an expansion
    hits=$(grep -nE '\$\$' "$AP_SOURCE" | grep -v '^[0-9]*: *#' || true)
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

case_no_document_carries_a_credential() {
    # The machine-readable audit is handed to other people, so the invariant
    # that the tool never reads a credential has to hold in the rendering as
    # well as in the source. A credential file is put where a root really
    # keeps one, and no document may reproduce a byte of it.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat-NOTATOKEN-CANARY"}}\n' \
        > "$HOME/.claude-bouvet/.credentials.json"
    assert_not_contains "$("$AP" doctor --json 2>&1)" "CANARY" || return
    assert_not_contains "$("$AP" list --json 2>&1)" "CANARY" || return
    assert_not_contains "$("$AP" verify --json 2>&1)" "CANARY" || return
    "$AP" doctor --report "$HOME/audit" >/dev/null 2>&1
    assert_not_contains "$(cat "$HOME/audit.json")" "CANARY" || return
    assert_not_contains "$(cat "$HOME/audit.md")" "CANARY"
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
run_case "the source uses no predictable temp names"  case_source_never_uses_predictable_temp_names
run_case "no command writes the agent state file"     case_no_command_writes_to_the_agents_state_file
run_case "no document carries a credential"           case_no_document_carries_a_credential
run_case "explain states the scheme"                  case_explain_states_the_scheme
run_case "help, version and an unknown command"       case_help_and_version
