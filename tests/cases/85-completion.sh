# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# completion: bash, zsh and fish completion scripts.
#
# The bash form is genuinely exercised: sourced into this harness and driven
# through COMP_WORDS/COMP_CWORD/COMPREPLY the way a real bash asks it for
# matches, because bash is the one interpreter this dependency-free suite can
# assume without adding to what it depends on. There is no zsh or fish
# interpreter to source the other two into, so those are pinned structurally
# instead: the shape `_arguments`/`_describe`/`compdef` and `complete -c`
# expect, and the same self-naming and live-profile-lookup properties the bash
# form is proven to have.

# ---------------------------------------------------------------------------
# bash: sourced and actually driven
# ---------------------------------------------------------------------------

# comp_file <shell>: the printed script, written to a throwaway file so it can
# be sourced without a subshell eating the function definitions it makes.
comp_file() {
    _cf=$(mktemp "${TMPDIR:-/tmp}/agent-profile-completion.XXXXXX")
    "$AP" completion "$1" > "$_cf" 2>/dev/null
    printf '%s\n' "$_cf"
}

# complete_for <words...>: sources the bash completion, then asks it for
# matches on that argv the way bash would, and prints one match per line.
complete_for() {
    _cff=$(comp_file bash)
    # shellcheck source=/dev/null
    . "$_cff"
    rm -f "$_cff"
    # shellcheck disable=SC2206  # word splitting is exactly what COMP_WORDS wants
    COMP_WORDS=("$@")
    COMP_CWORD=$(( $# - 1 ))
    COMPREPLY=()
    _agent-profile_complete
    printf '%s\n' "${COMPREPLY[@]}"
}

case_bash_completion_lists_every_subcommand_at_the_first_word() {
    HOME=$(new_home); export HOME
    out=$(complete_for agent-profile "")
    for c in new list ls remove run shell env path which guard desktop app \
             doctor verify explain completion version help; do
        assert_contains "$out" "$c" || return
    done
}

case_bash_completion_offers_profile_names_at_the_first_word_too() {
    # A bare profile name runs it, so it belongs at the same position as a
    # subcommand.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(complete_for agent-profile "")
    assert_contains "$out" "bouvet"
}

case_bash_completion_offers_only_profiles_after_run() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new tide >/dev/null 2>&1
    out=$(complete_for agent-profile run "")
    assert_contains "$out" "bouvet" || return
    assert_contains "$out" "tide" || return
    assert_not_contains "$out" "doctor"
}

case_bash_completion_offers_profiles_and_purge_after_remove() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(complete_for agent-profile remove "")
    assert_contains "$out" "bouvet" || return
    assert_contains "$out" "--purge"
}

case_bash_completion_offers_the_agent_after_new_dash_dash_agent() {
    HOME=$(new_home); export HOME
    out=$(complete_for agent-profile new --agent "")
    assert_contains "$out" "claude"
}

case_bash_completion_offers_flags_after_new() {
    HOME=$(new_home); export HOME
    out=$(complete_for agent-profile new "")
    assert_contains "$out" "--agent" || return
    assert_contains "$out" "--root" || return
    assert_contains "$out" "--app-data"
}

case_bash_completion_offers_shells_after_guard_dash_dash_shell() {
    HOME=$(new_home); export HOME
    out=$(complete_for agent-profile guard --shell "")
    assert_contains "$out" "bash" || return
    assert_contains "$out" "zsh" || return
    assert_contains "$out" "fish"
}

case_bash_completion_offers_shells_after_completion() {
    HOME=$(new_home); export HOME
    out=$(complete_for agent-profile completion "")
    assert_contains "$out" "bash" || return
    assert_contains "$out" "zsh" || return
    assert_contains "$out" "fish"
}

case_bash_completion_offers_keychain_scan_after_doctor() {
    HOME=$(new_home); export HOME
    out=$(complete_for agent-profile doctor "")
    assert_contains "$out" "--keychain-scan"
}

# Profile names are looked up when the shell asks, not baked into the script
# at generation time, so a profile created after the script was sourced still
# completes without re-sourcing anything, the same way the guard's profile
# list is never stale.
case_bash_completion_sees_a_profile_created_after_sourcing() {
    HOME=$(new_home); export HOME
    _cff=$(comp_file bash)
    # shellcheck source=/dev/null
    . "$_cff"
    rm -f "$_cff"
    "$AP" new bouvet >/dev/null 2>&1
    COMP_WORDS=(agent-profile run "")
    COMP_CWORD=2
    COMPREPLY=()
    _agent-profile_complete
    assert_contains "${COMPREPLY[*]}" "bouvet"
}

case_bash_completion_uses_the_invoked_name() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/named"
    ln -sf "$ROOT/bin/agent-profile" "$HOME/named/agpin"
    out=$("${BASH:-/bin/bash}" "$HOME/named/agpin" completion bash 2>&1)
    assert_contains "$out" "_agpin_complete" || return
    assert_contains "$out" "complete -F _agpin_complete agpin" || return
    assert_not_contains "$out" "_agent-profile_complete"
}

# ---------------------------------------------------------------------------
# zsh and fish: checked structurally
#
# No zsh or fish interpreter is assumed here, so what is pinned is the shape
# each expects (#compdef/compdef for zsh, complete -c for fish), that every
# subcommand is named, and that both call back into the tool for profile
# names rather than hard-coding whichever profiles existed when the script was
# printed.
# ---------------------------------------------------------------------------

case_zsh_completion_has_the_compdef_pragma() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion zsh 2>&1)
    assert_contains "$out" "#compdef agent-profile" || return
    assert_contains "$out" "compdef _agent-profile agent-profile"
}

case_zsh_completion_lists_every_subcommand() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion zsh 2>&1)
    for c in new list ls remove run shell env path which guard desktop app \
             doctor verify explain completion version help; do
        assert_contains "$out" "'$c:" || return
    done
}

case_zsh_completion_looks_up_profiles_rather_than_baking_them_in() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$("$AP" completion zsh 2>&1)
    assert_contains "$out" "list 2>/dev/null" || return
    assert_not_contains "$out" "bouvet"
}

case_zsh_completion_offers_flags_per_subcommand() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion zsh 2>&1)
    assert_contains "$out" "--purge[" || return
    assert_contains "$out" "--keychain-scan[" || return
    assert_contains "$out" "--shell[shell to target]:shell:(bash zsh fish)"
}

case_zsh_completion_uses_the_invoked_name() {
    # Not "not contains agent-profile": new_home's own path is
    # ".../agent-profile-test.XXXXXX/...", so that substring is present no
    # matter what this prints. What has to be true instead is that the two
    # spots naming the command say "agpin", not the tool's fallback name.
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/named"
    ln -sf "$ROOT/bin/agent-profile" "$HOME/named/agpin"
    out=$("${BASH:-/bin/bash}" "$HOME/named/agpin" completion zsh 2>&1)
    assert_contains "$out" "#compdef agpin" || return
    assert_contains "$out" "compdef _agpin agpin"
}

case_fish_completion_registers_the_command() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion fish 2>&1)
    assert_contains "$out" "complete -c agent-profile -f"
}

case_fish_completion_lists_every_subcommand() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion fish 2>&1)
    for c in new list ls remove run shell env path which guard desktop app \
             doctor verify explain completion version help; do
        assert_contains "$out" "-a $c " || return
    done
}

case_fish_completion_looks_up_profiles_rather_than_baking_them_in() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$("$AP" completion fish 2>&1)
    assert_contains "$out" "__agent-profile_profiles" || return
    assert_not_contains "$out" "bouvet"
}

case_fish_completion_offers_flags_per_subcommand() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion fish 2>&1)
    assert_contains "$out" "-l purge" || return
    assert_contains "$out" "-l keychain-scan" || return
    assert_contains "$out" "-l shell"
}

case_fish_completion_uses_the_invoked_name() {
    # Same caveat as the zsh case above: new_home's own path already contains
    # "agent-profile", so the two spots naming the command are checked
    # directly rather than by the absence of that substring.
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/named"
    ln -sf "$ROOT/bin/agent-profile" "$HOME/named/agpin"
    out=$("${BASH:-/bin/bash}" "$HOME/named/agpin" completion fish 2>&1)
    assert_contains "$out" "complete -c agpin -f" || return
    assert_contains "$out" "__agpin_profiles"
}

# ---------------------------------------------------------------------------
# argument handling, common to all three
# ---------------------------------------------------------------------------

case_completion_needs_a_shell_argument() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "usage: agent-profile completion bash|zsh|fish"
}

case_completion_refuses_an_unknown_shell() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion powershell 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "unknown shell 'powershell'"
}

case_completion_refuses_extra_arguments() {
    HOME=$(new_home); export HOME
    out=$("$AP" completion bash extra 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "usage: agent-profile completion bash|zsh|fish"
}

run_case "bash completion lists every subcommand"     case_bash_completion_lists_every_subcommand_at_the_first_word
run_case "bash completion offers profile names too"   case_bash_completion_offers_profile_names_at_the_first_word_too
run_case "bash completion: only profiles after run"   case_bash_completion_offers_only_profiles_after_run
run_case "bash completion: profiles and --purge"      case_bash_completion_offers_profiles_and_purge_after_remove
run_case "bash completion: agent after --agent"       case_bash_completion_offers_the_agent_after_new_dash_dash_agent
run_case "bash completion: flags after new"           case_bash_completion_offers_flags_after_new
run_case "bash completion: shells after guard --shell" case_bash_completion_offers_shells_after_guard_dash_dash_shell
run_case "bash completion: shells after completion"   case_bash_completion_offers_shells_after_completion
run_case "bash completion: --keychain-scan after doctor" case_bash_completion_offers_keychain_scan_after_doctor
run_case "bash completion sees a profile added later" case_bash_completion_sees_a_profile_created_after_sourcing
run_case "bash completion uses the invoked name"      case_bash_completion_uses_the_invoked_name
run_case "zsh completion has the compdef pragma"      case_zsh_completion_has_the_compdef_pragma
run_case "zsh completion lists every subcommand"      case_zsh_completion_lists_every_subcommand
run_case "zsh completion looks profiles up live"      case_zsh_completion_looks_up_profiles_rather_than_baking_them_in
run_case "zsh completion offers flags per subcommand" case_zsh_completion_offers_flags_per_subcommand
run_case "zsh completion uses the invoked name"       case_zsh_completion_uses_the_invoked_name
run_case "fish completion registers the command"      case_fish_completion_registers_the_command
run_case "fish completion lists every subcommand"     case_fish_completion_lists_every_subcommand
run_case "fish completion looks profiles up live"     case_fish_completion_looks_up_profiles_rather_than_baking_them_in
run_case "fish completion offers flags per subcommand" case_fish_completion_offers_flags_per_subcommand
run_case "fish completion uses the invoked name"      case_fish_completion_uses_the_invoked_name
run_case "completion needs a shell argument"          case_completion_needs_a_shell_argument
run_case "completion refuses an unknown shell"        case_completion_refuses_an_unknown_shell
run_case "completion refuses extra arguments"         case_completion_refuses_extra_arguments
