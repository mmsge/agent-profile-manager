# shellcheck shell=bash
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# Installing, self-naming and the unpinned guard.

INSTALLER="$ROOT/tools/install.sh"

# as_name <name> <args...>: run the tool through a symlink with that name, so
# $0 -- and therefore the name it calls itself -- is the installed one.
as_name() {
    _an_name="$1"; shift
    mkdir -p "$HOME/named"
    ln -sf "$ROOT/bin/agent-profile" "$HOME/named/$_an_name"
    "${BASH:-/bin/bash}" "$HOME/named/$_an_name" "$@"
}

# A tool installed as 'agpin' must never tell the reader to run something
# called 'agent-profile', because that may not be on their PATH at all.
case_messages_use_the_name_it_was_invoked_as() {
    HOME=$(new_home); export HOME
    out=$(as_name agpin help 2>&1)
    assert_contains "$out" "agpin <command> [arguments]" || return
    assert_not_contains "$out" "agent-profile <command>"
}

case_errors_use_the_name_it_was_invoked_as() {
    HOME=$(new_home); export HOME
    out=$(as_name agpin nosuchcommand 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "agpin: unknown command" || return
    assert_contains "$out" "agpin help for commands" || return
    assert_contains "$out" "agpin list for profiles"
}

case_findings_use_the_name_it_was_invoked_as() {
    HOME=$(new_home); export HOME
    as_name agpin new bouvet >/dev/null 2>&1
    rm -rf "$HOME/.claude-bouvet"
    out=$(as_name agpin doctor 2>&1)
    assert_not_contains "$out" "agent-profile "
}

case_an_odd_argv0_falls_back_to_the_long_name() {
    HOME=$(new_home); export HOME
    out=$(as_name "we ird" help 2>&1)
    assert_contains "$out" "agent-profile <command> [arguments]"
}

# ---------------------------------------------------------------------------
# guard
# ---------------------------------------------------------------------------

# with_guard <script>: run a shell with the guard installed and a stand-in
# agent binary, so refusing and passing through are both observable.
with_guard() {
    mkdir -p "$HOME/gbin"
    printf '#!/bin/sh\necho "agent ran: $*"\n' > "$HOME/gbin/claude"
    chmod +x "$HOME/gbin/claude"
    PATH="$HOME/gbin:$PATH" "${BASH:-/bin/bash}" -c "eval \"\$($AP guard)\"; $1" 2>&1
}

case_guard_refuses_an_unpinned_run() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(with_guard 'claude --version')
    assert_contains "$out" "Refusing to run claude unpinned" || return
    assert_not_contains "$out" "agent ran:"
}

case_guard_lists_the_profiles_it_knows() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new tide >/dev/null 2>&1
    out=$(with_guard 'claude --version')
    assert_contains "$out" "bouvet" || return
    assert_contains "$out" "tide"
}

case_guard_passes_through_when_pinned() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(with_guard "export CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet; claude --version")
    assert_contains "$out" "agent ran: --version"
}

# An escape hatch that is documented and obvious beats one people discover by
# deleting the guard from their rc file.
case_guard_can_be_overridden_deliberately() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(with_guard 'command claude --version')
    assert_contains "$out" "agent ran: --version"
}

# ---------------------------------------------------------------------------
# install.sh
# ---------------------------------------------------------------------------

case_install_links_both_names() {
    HOME=$(new_home); export HOME
    out=$("$INSTALLER" --prefix "$HOME/bin" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    [ -L "$HOME/bin/agpin" ] || { fail "no agpin link"; return; }
    [ -L "$HOME/bin/agent-profile" ] || { fail "no agent-profile link"; return; }
    # Compare against this checkout rather than a literal: a hardcoded version
    # makes every release bump look like a broken installer.
    want=$("${BASH:-/bin/bash}" "$ROOT/bin/agent-profile" version | awk '{print $2}')
    assert_equals "$want" "$("${BASH:-/bin/bash}" "$HOME/bin/agpin" version | awk '{print $2}')"
}

case_install_is_idempotent_and_says_so() {
    HOME=$(new_home); export HOME
    "$INSTALLER" --prefix "$HOME/bin" >/dev/null 2>&1
    out=$("$INSTALLER" --prefix "$HOME/bin" 2>&1)
    assert_contains "$out" "Already installed" || return
    assert_not_contains "$out" "Installed $HOME/bin/agpin ->"
}

case_install_warns_when_the_prefix_is_not_on_path() {
    HOME=$(new_home); export HOME
    out=$("$INSTALLER" --prefix "$HOME/bin" 2>&1)
    assert_contains "$out" "not on your PATH" || return
    assert_contains "$out" "export PATH="
}

case_install_refuses_to_replace_a_real_file() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/bin"
    printf 'not ours\n' > "$HOME/bin/agpin"
    out=$("$INSTALLER" --prefix "$HOME/bin" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "not a symlink" || return
    assert_equals "not ours" "$(cat "$HOME/bin/agpin")"
}

case_install_takes_a_custom_name() {
    HOME=$(new_home); export HOME
    "$INSTALLER" --prefix "$HOME/bin" --name apx9 >/dev/null 2>&1
    [ -L "$HOME/bin/apx9" ] || fail "no apx9 link"
}

# Uninstall must remove what it made and nothing else, however tempting the
# name match is.
case_uninstall_leaves_anything_it_did_not_create() {
    HOME=$(new_home); export HOME
    "$INSTALLER" --prefix "$HOME/bin" >/dev/null 2>&1
    ln -sf /bin/echo "$HOME/bin/somethingelse"
    printf 'mine\n' > "$HOME/bin/agent-profile.bak"

    out=$("$INSTALLER" --prefix "$HOME/bin" --uninstall 2>&1)
    assert_contains "$out" "Removed" || return
    [ -e "$HOME/bin/agpin" ] && { fail "agpin link survived uninstall"; return; }
    [ -L "$HOME/bin/somethingelse" ] || fail "uninstall removed an unrelated link"
}

case_uninstall_will_not_remove_a_foreign_file_of_the_same_name() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/bin"
    printf 'not ours\n' > "$HOME/bin/agpin"
    out=$("$INSTALLER" --prefix "$HOME/bin" --uninstall 2>&1)
    assert_contains "$out" "not a link to this checkout" || return
    assert_equals "not ours" "$(cat "$HOME/bin/agpin")"
}

# The shortcut exists only where the alternative is a refusal. That is what
# makes it safe: there is no working unpinned invocation for it to shadow.
case_guard_treats_a_leading_profile_name_as_the_pin() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(with_guard 'claude bouvet')
    assert_contains "$out" "Pinning to bouvet" || return
    assert_contains "$out" "agent ran:"
}

case_guard_forwards_the_remaining_arguments() {
    HOME=$(new_home); export HOME
    "$AP" new tide >/dev/null 2>&1
    out=$(with_guard 'claude tide --continue --verbose')
    assert_contains "$out" "agent ran: --continue --verbose"
}

case_guard_still_refuses_a_first_argument_that_is_not_a_profile() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(with_guard "claude 'fix the bug'")
    assert_contains "$out" "Refusing to run claude unpinned" || return
    assert_not_contains "$out" "agent ran:"
}

# Pinned, claude takes a prompt. Stealing a word that happens to match a
# profile name would break that, so the shortcut must not apply here.
case_guard_leaves_the_argument_alone_when_already_pinned() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new tide >/dev/null 2>&1
    out=$(with_guard "export CLAUDE_CONFIG_DIR=$HOME/.claude-tide; claude bouvet")
    assert_contains "$out" "agent ran: bouvet" || return
    assert_not_contains "$out" "Pinning to"
}

case_guard_suggests_the_shortcut_when_it_refuses() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(with_guard 'claude')
    assert_contains "$out" "claude <profile> [args...]"
}

run_case "messages use the invoked name"          case_messages_use_the_name_it_was_invoked_as
run_case "errors use the invoked name"            case_errors_use_the_name_it_was_invoked_as
run_case "findings use the invoked name"          case_findings_use_the_name_it_was_invoked_as
run_case "an odd argv0 falls back"                case_an_odd_argv0_falls_back_to_the_long_name
run_case "guard refuses an unpinned run"          case_guard_refuses_an_unpinned_run
run_case "guard lists the profiles it knows"      case_guard_lists_the_profiles_it_knows
run_case "guard passes through when pinned"       case_guard_passes_through_when_pinned
run_case "guard can be overridden deliberately"   case_guard_can_be_overridden_deliberately
run_case "install links both names"               case_install_links_both_names
run_case "install is idempotent and says so"      case_install_is_idempotent_and_says_so
run_case "install warns about PATH"               case_install_warns_when_the_prefix_is_not_on_path
run_case "install refuses to replace a real file" case_install_refuses_to_replace_a_real_file
run_case "install takes a custom name"            case_install_takes_a_custom_name
run_case "uninstall leaves other files alone"     case_uninstall_leaves_anything_it_did_not_create
run_case "uninstall spares a foreign file"        case_uninstall_will_not_remove_a_foreign_file_of_the_same_name
run_case "guard takes a leading profile name"     case_guard_treats_a_leading_profile_name_as_the_pin
run_case "guard forwards remaining arguments"     case_guard_forwards_the_remaining_arguments
run_case "guard refuses a non-profile first arg"  case_guard_still_refuses_a_first_argument_that_is_not_a_profile
run_case "guard leaves the arg alone when pinned" case_guard_leaves_the_argument_alone_when_already_pinned
run_case "guard suggests the shortcut"            case_guard_suggests_the_shortcut_when_it_refuses
