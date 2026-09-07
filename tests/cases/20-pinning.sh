# shellcheck shell=bash
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# run, shell, which: pinned execution and the derived label.

case_run_pins_the_variable() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" run bouvet --version 2>&1)
    assert_equals "CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet claude --version" "$out"
}

case_run_forwards_all_arguments() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(AGENT_PROFILE_DRY_RUN=1 "$AP" run bouvet -p "hello world" --model opus 2>&1)
    assert_contains "$out" "claude -p hello world --model opus"
}

case_shell_pins_the_variable() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(SHELL=/bin/zsh AGENT_PROFILE_DRY_RUN=1 "$AP" shell bouvet 2>/dev/null)
    assert_equals "CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet /bin/zsh" "$out"
}

case_which_says_so_when_unpinned() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(env -u CLAUDE_CONFIG_DIR "$AP" which 2>&1)
    assert_contains "$out" "Not pinned to any profile"
}

case_which_label_fails_when_unpinned() {
    # A prompt calls this. It must exit non-zero rather than print something
    # misleading when the shell is pinned to nothing.
    HOME=$(new_home); export HOME
    out=$(env -u CLAUDE_CONFIG_DIR "$AP" which --label 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_equals "" "$out"
}

case_which_derives_label_from_root() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude-bouvet" "$AP" which --label)
    assert_equals "bouvet" "$out"
}

case_label_comes_from_the_root_not_the_registry() {
    # The label must be derived from the pinned root, never stored in a second
    # place. A root the registry has never heard of must still label correctly.
    HOME=$(new_home); export HOME
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude-unregistered" "$AP" which --label)
    assert_equals "unregistered" "$out" || return
    full=$(CLAUDE_CONFIG_DIR="$HOME/.claude-unregistered" "$AP" which)
    assert_contains "$full" "not registered"
}

case_label_survives_a_renamed_registry_entry() {
    # Rename the registry file and the label must not follow it: it comes from
    # the root. This is the drift the brief asks to make impossible.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    mv "$HOME/.config/agent-profiles/bouvet.conf" "$HOME/.config/agent-profiles/mislabelled.conf"
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude-bouvet" "$AP" which --label)
    assert_equals "bouvet" "$out"
}

# The default root is the one root whose basename says nothing: ".claude"
# names no account, and a profile living there cannot be moved somewhere
# better, because relocating a root invalidates its login. So for that root,
# and only that root, the registered name is used.
case_label_uses_the_registry_for_the_default_root() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet --root "$HOME/.claude" >/dev/null 2>&1
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude" "$AP" which --label)
    assert_equals "bouvet" "$out"
}

case_label_falls_back_when_the_default_root_is_unclaimed() {
    HOME=$(new_home); export HOME
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude" "$AP" which --label)
    assert_equals ".claude" "$out"
}

# The boundary of that exception. Every other root keeps the no-drift
# guarantee, so a renamed entry must not move a prefixed root's label even
# though the registry is now consulted for one case.
case_the_registry_exception_does_not_leak_to_other_roots() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new work --root "$HOME/My Roots/claude-work" >/dev/null 2>&1
    mv "$HOME/.config/agent-profiles/work.conf" "$HOME/.config/agent-profiles/renamed.conf"
    out=$(CLAUDE_CONFIG_DIR="$HOME/My Roots/claude-work" "$AP" which --label)
    assert_equals "claude-work" "$out"
}

# Two profiles at one root make every label and count here ambiguous, and
# nothing else reports it.
case_d15_reports_two_profiles_sharing_a_root() {
    HOME=$(new_home); export HOME
    "$AP" new a --root "$HOME/.claude-shared" >/dev/null 2>&1
    "$AP" new b --root "$HOME/.claude-shared" >/dev/null 2>&1
    out=$("$AP" doctor 2>&1)
    assert_contains "$out" "D15" || return
    assert_contains "$out" "a b"
}

case_d15_quiet_when_every_root_is_distinct() {
    HOME=$(new_home); export HOME
    "$AP" new a >/dev/null 2>&1
    "$AP" new b >/dev/null 2>&1
    assert_not_contains "$("$AP" doctor 2>&1)" "D15"
}

run_case "run pins the config-dir variable"          case_run_pins_the_variable
run_case "run forwards all arguments"                case_run_forwards_all_arguments
run_case "shell pins the config-dir variable"        case_shell_pins_the_variable
run_case "which says so explicitly when unpinned"    case_which_says_so_when_unpinned
run_case "which --label exits 1 when unpinned"       case_which_label_fails_when_unpinned
run_case "which derives the label from the root"     case_which_derives_label_from_root
run_case "the label ignores the registry"            case_label_comes_from_the_root_not_the_registry
run_case "the label survives a renamed entry"        case_label_survives_a_renamed_registry_entry
run_case "the default root labels from the registry" case_label_uses_the_registry_for_the_default_root
run_case "an unclaimed default root falls back"      case_label_falls_back_when_the_default_root_is_unclaimed
run_case "the registry exception does not leak"      case_the_registry_exception_does_not_leak_to_other_roots
run_case "D15 reports two profiles sharing a root"   case_d15_reports_two_profiles_sharing_a_root
run_case "D15 quiet when every root is distinct"     case_d15_quiet_when_every_root_is_distinct
