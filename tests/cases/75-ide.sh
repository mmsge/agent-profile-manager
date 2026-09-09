# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# The IDE half: the pinned launchers and D16. A stand-in open(1) and stand-in
# extension directories let these run anywhere, the same way 70-desktop.sh
# exercises the applet machinery without a Mac, so the macOS-only paths are
# tested in CI rather than shipped unrun.

# ide: run agent-profile as if on macOS, against the fixture's stand-in tools.
ide() {
    PATH="$HOME/fakebin:$PATH" AGENT_PROFILE_PLATFORM=Darwin USER=tester "$AP" "$@"
}

# ide_fixture: a throwaway HOME with one profile and an open that takes --env.
# No extension is installed; each case that wants one installs it.
#
# The stand-in security(1) is not optional, for the reason 70-desktop.sh gives:
# these cases pin the platform to Darwin, and on a real Mac that would send
# doctor and verify at the runner's own Keychain, so the same commit would pass
# on Linux and behave differently on macOS. It is given bouvet's own service so
# the Keychain-backed rules stay quiet and a D16 assertion is testing D16.
ide_fixture() {
    HOME=$(new_home); export HOME
    fake_open "$HOME/fakebin" env
    "$AP" new bouvet >/dev/null 2>&1
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-bouvet")"
}

# fixture_vscode_ext <ide-dir>: an installed Claude Code extension, named the
# way a platform-specific build is named on a real machine.
fixture_vscode_ext() {
    mkdir -p "$HOME/$1/anthropic.claude-code-2.1.266-darwin-arm64"
}

# fixture_jetbrains_plugin <ide-config-dir>: an installed plugin, at
# <config>/plugins/claude-code-jetbrains-plugin (docs/FACTS.md F21).
fixture_jetbrains_plugin() {
    mkdir -p "$HOME/$1/plugins/claude-code-jetbrains-plugin"
}

# ide_json <text> <expression>: one value out of a JSON document. Kept local
# rather than borrowed from 35-json.sh, so this file does not depend on the
# order the harness happens to source case files in.
ide_json() {
    printf '%s\n' "$1" | python3 -c '
import json, sys
value = eval(sys.argv[1], {"d": json.load(sys.stdin)})
print("" if value is None else value)
' "$2"
}

# ---------------------------------------------------------------------------
# code and idea
# ---------------------------------------------------------------------------

# The same ordering trick the desktop launcher depends on: everything after
# --args goes to the application rather than to open, so an --env on the wrong
# side of it opens a healthy, unpinned IDE. docs/FACTS.md F13.
case_code_puts_env_before_args() {
    ide_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet /tmp/project 2>&1)
    assert_contains "$out" "--env CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet" || return
    assert_contains "$out" "--args /tmp/project" || return

    before=${out%%--args*}
    case "$before" in
        *--env*) ;;
        *) fail "--env must come before --args" "got: $out"; return ;;
    esac
}

# -n is the difference between pinning an IDE and handing a path to the
# unpinned one already running. Without it the window opens, the project
# opens, and every session in it writes to the default root.
case_code_forces_a_new_instance() {
    ide_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet /tmp/project 2>&1)
    assert_contains "$out" "open -n -a"
}

case_code_defaults_to_vs_code() {
    ide_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet 2>&1)
    assert_contains "$out" "-a Visual Studio Code"
}

# No path means launch the IDE, not open a file called nothing.
case_code_omits_args_without_a_path() {
    ide_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet 2>&1)
    assert_contains "$out" "--env CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet" || return
    assert_not_contains "$out" "--args"
}

case_code_app_names_another_editor() {
    ide_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet /tmp/p --app Cursor 2>&1)
    assert_contains "$out" "-a Cursor" || return
    assert_contains "$out" "--env CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet" || return
    assert_not_contains "$out" "Visual Studio Code"
}

case_idea_defaults_to_intellij() {
    ide_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 ide idea bouvet /tmp/p 2>&1)
    assert_contains "$out" "-a IntelliJ IDEA" || return
    assert_contains "$out" "--env CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet"
}

case_idea_app_names_another_jetbrains_ide() {
    ide_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 ide idea bouvet --app PyCharm 2>&1)
    assert_contains "$out" "-a PyCharm" || return
    assert_not_contains "$out" "IntelliJ IDEA"
}

# The pin travels in --env and nowhere else. open inherits nothing from the
# invoking shell, so an exported variable here would be decoration.
case_code_does_not_export_the_variable() {
    ide_fixture
    cat > "$HOME/fakebin/open" <<'OPENEOF'
#!/bin/sh
[ "$1" = "--help" ] && { echo "--env VAR      Add an enviroment variable"; exit 0; }
echo "inherited=[${CLAUDE_CONFIG_DIR:-}]"
OPENEOF
    chmod +x "$HOME/fakebin/open"
    out=$(ide code bouvet 2>&1)
    assert_contains "$out" "inherited=[]"
}

# An open without --env cannot pin anything, and launching anyway would start
# an IDE whose extension writes to the default root. Nothing is launched.
case_code_refuses_an_open_without_env() {
    ide_fixture
    fake_open "$HOME/fakebin" noenv
    out=$(ide code bouvet /tmp/p 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "does not support --env" || return
    assert_not_contains "$out" "open: -n"
}

case_code_rejects_an_unknown_profile() {
    ide_fixture
    out=$(ide code nosuch 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "no such profile"
}

case_code_needs_a_profile() {
    ide_fixture
    out=$(ide code 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "usage:" || return
    assert_contains "$out" "code <profile> [path] [--app NAME]"
}

case_ide_rejects_an_unknown_option_and_a_second_path() {
    ide_fixture
    out=$(ide code bouvet --nope 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown option" || return

    out=$(ide idea bouvet /tmp/a /tmp/b 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unexpected argument"
}

# --app with nothing after it must fail rather than swallow the profile name.
case_ide_app_needs_a_value() {
    ide_fixture
    out=$(ide code bouvet --app 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "--app needs a value"
}

# ---------------------------------------------------------------------------
# D16
# ---------------------------------------------------------------------------

case_d16_reports_a_vs_code_extension() {
    ide_fixture
    fixture_vscode_ext ".vscode/extensions"
    out=$(ide doctor 2>&1); status=$?
    # Every other rule is quiet on this fixture, so the exit code is D16's.
    assert_status 2 "$status" "$out" || return
    assert_contains "$out" "D16" || return
    assert_contains "$out" "extension for VS Code is installed and cannot be pinned" || return
    assert_contains "$out" "$HOME/.vscode/extensions/anthropic.claude-code-2.1.266-darwin-arm64" || return
    assert_contains "$out" "agent-profile code <profile> [path]"
}

case_d16_reports_a_cursor_extension() {
    ide_fixture
    fixture_vscode_ext ".cursor/extensions"
    out=$(ide doctor 2>&1)
    assert_contains "$out" "extension for Cursor is installed and cannot be pinned" || return
    assert_contains "$out" "$HOME/.cursor/extensions/anthropic.claude-code-2.1.266-darwin-arm64"
}

# The JetBrains wording has to differ, because the mechanism differs: the
# plugin types the command into the IDE's own terminal, so a guard in an rc
# file does see it (docs/FACTS.md F19). Telling a reader otherwise sends them
# hunting for a leak that is not there.
case_d16_reports_a_jetbrains_plugin_in_its_own_words() {
    ide_fixture
    fixture_jetbrains_plugin "Library/Application Support/JetBrains/IntelliJIdea2026.1"
    out=$(ide doctor 2>&1)
    assert_contains "$out" "plugin for a JetBrains IDE is installed and cannot be pinned" || return
    assert_contains "$out" "integrated terminal, so a guard" || return
    assert_contains "$out" "it pins nothing" || return
    assert_contains "$out" "agent-profile idea <profile> [path]" || return
    # Nothing is installed but the plugin, so the VS Code wording must be
    # absent entirely rather than merely absent from this one finding.
    assert_not_contains "$out" "spawns its own copy"
}

# The agent's own detection also looks directly under Application Support,
# without the JetBrains segment, so D16 has to as well or it misses an older
# layout entirely (docs/FACTS.md F21).
case_d16_finds_a_plugin_in_the_older_layout() {
    ide_fixture
    fixture_jetbrains_plugin "Library/Application Support/PyCharm2025.3"
    out=$(ide doctor 2>&1)
    assert_contains "$out" "D16" || return
    assert_contains "$out" "PyCharm2025.3/plugins/claude-code-jetbrains-plugin"
}

case_d16_reports_every_installed_ide_once() {
    ide_fixture
    fixture_vscode_ext ".vscode/extensions"
    fixture_vscode_ext ".cursor/extensions"
    fixture_jetbrains_plugin "Library/Application Support/JetBrains/IntelliJIdea2026.1"
    out=$(ide doctor --json 2>/dev/null)
    assert_equals "3" "$(ide_json "$out" 'len([f for f in d["findings"] if f["rule"] == "D16"])')" || return
    assert_equals "fail" "$(ide_json "$out" '[r for r in d["rules"] if r["rule"] == "D16"][0]["status"]')"
}

case_d16_is_quiet_with_no_extension_installed() {
    ide_fixture
    mkdir -p "$HOME/.vscode/extensions/ms-python.python-2026.1.0"
    mkdir -p "$HOME/Library/Application Support/JetBrains/IntelliJIdea2026.1/plugins/some-other-plugin"
    out=$(ide doctor 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_not_contains "$out" "D16" || return
    assert_equals "pass" \
        "$(ide_json "$(ide doctor --json 2>/dev/null)" '[r for r in d["rules"] if r["rule"] == "D16"][0]["status"]')"
}

# Where a JetBrains IDE keeps its plugins is known for macOS only. On any
# other platform D16 has looked in two of its three places, and a document
# that called that a pass would be claiming a check that did not happen.
case_d16_is_limited_off_macos() {
    ide_fixture
    out=$("$AP" doctor --json 2>/dev/null)
    assert_equals "limited" \
        "$(ide_json "$out" '[r for r in d["rules"] if r["rule"] == "D16"][0]["status"]')" || return
    assert_contains "$(ide_json "$out" '[r for r in d["rules"] if r["rule"] == "D16"][0]["reason"]')" \
        "only known for macOS"

    # And on macOS it is not limited, so the reason is about the platform
    # rather than about the rule always being half blind.
    out=$(ide doctor --json 2>/dev/null)
    assert_equals "pass" \
        "$(ide_json "$out" '[r for r in d["rules"] if r["rule"] == "D16"][0]["status"]')"
}

# The rule has to reach the document through emit like every other one. A
# finding printed with a bare printf would be missing from --json entirely.
case_d16_reaches_the_document_with_its_prose_intact() {
    ide_fixture
    fixture_vscode_ext ".vscode/extensions"
    out=$(ide doctor --json 2>/dev/null)
    assert_equals "$HOME/.vscode/extensions/anthropic.claude-code-2.1.266-darwin-arm64" \
        "$(ide_json "$out" '[f for f in d["findings"] if f["rule"] == "D16"][0]["subject"]')" || return
    [ "$(ide_json "$out" 'len([f for f in d["findings"] if f["rule"] == "D16"][0]["detail"])')" -gt 0 ] \
        || fail "the D16 finding reached the document with no detail lines"
}

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------

# D16 reads directories rather than asking the IDE's own CLI, so its silence
# has two meanings and verify has to tell them apart. A machine with no IDE at
# all has not exercised the scan, and saying so is what stops an extensions
# directory that moved from turning D16 into a rule that reports every machine
# clean.
case_verify_reports_f21_unchecked_without_an_ide() {
    ide_fixture
    out=$(ide verify 2>&1)
    assert_contains "$out" "unchecked F21" || return
    assert_contains "$out" "no IDE extensions directory on this machine"
}

case_verify_reports_f21_ok_with_an_extension() {
    ide_fixture
    fixture_vscode_ext ".vscode/extensions"
    out=$(ide verify 2>&1)
    assert_contains "$out" "ok        F21" || return
    assert_contains "$out" "doctor reports each as D16"
}

case_verify_notes_an_ide_without_the_extension() {
    ide_fixture
    mkdir -p "$HOME/.vscode/extensions/ms-python.python-2026.1.0"
    out=$(ide verify 2>&1)
    assert_contains "$out" "note      F21" || return
    assert_contains "$out" "none of them is Claude Code's"
}

# F19 and F20 need a real IDE and a real session, so verify says how to settle
# them rather than pretending it just did, the same way it treats F01.
case_verify_says_how_to_settle_f19_and_f20() {
    ide_fixture
    out=$(ide verify 2>&1)
    assert_contains "$out" "note      F19" || return
    assert_contains "$out" "not from a session that ran" || return
    assert_contains "$out" "note      F20" || return
    assert_contains "$out" "a settings pin is not a launch pin"
}

# ---------------------------------------------------------------------------
# Discoverability
# ---------------------------------------------------------------------------

case_help_and_completions_name_the_ide_commands() {
    HOME=$(new_home); export HOME
    out=$("$AP" help)
    assert_contains "$out" "code <name> [path] [--app NAME]" || return
    assert_contains "$out" "idea <name> [path] [--app NAME]" || return

    # Per shell, and against the line that actually offers the subcommand, so
    # this cannot pass on the word "code" appearing inside "claude-code".
    assert_contains "$("$AP" completion bash)" "desktop code idea app" || return
    assert_contains "$("$AP" completion zsh)" "'code:launch VS Code pinned to a profile'" || return
    assert_contains "$("$AP" completion fish)" "-a idea -d 'Launch a JetBrains IDE pinned to a profile'"
}

run_case "code puts --env before --args"              case_code_puts_env_before_args
run_case "code forces a new instance with -n"         case_code_forces_a_new_instance
run_case "code defaults to VS Code"                   case_code_defaults_to_vs_code
run_case "code omits --args without a path"           case_code_omits_args_without_a_path
run_case "code --app names another editor"            case_code_app_names_another_editor
run_case "idea defaults to IntelliJ IDEA"             case_idea_defaults_to_intellij
run_case "idea --app names another JetBrains IDE"     case_idea_app_names_another_jetbrains_ide
run_case "code does not export the variable"          case_code_does_not_export_the_variable
run_case "code refuses an open without --env"         case_code_refuses_an_open_without_env
run_case "code rejects an unknown profile"            case_code_rejects_an_unknown_profile
run_case "code needs a profile"                       case_code_needs_a_profile
run_case "the IDE commands reject bad arguments"      case_ide_rejects_an_unknown_option_and_a_second_path
run_case "--app needs a value"                        case_ide_app_needs_a_value
run_case "D16 reports a VS Code extension"            case_d16_reports_a_vs_code_extension
run_case "D16 reports a Cursor extension"             case_d16_reports_a_cursor_extension
run_case "D16 reports a JetBrains plugin its way"     case_d16_reports_a_jetbrains_plugin_in_its_own_words
run_case "D16 finds a plugin in the older layout"     case_d16_finds_a_plugin_in_the_older_layout
run_case "D16 reports every installed IDE once"       case_d16_reports_every_installed_ide_once
run_case "D16 quiet with no extension installed"      case_d16_is_quiet_with_no_extension_installed
run_case "D16 is limited off macOS"                   case_d16_is_limited_off_macos
run_case "D16 reaches the document intact"            case_d16_reaches_the_document_with_its_prose_intact
run_case "verify reports F21 unchecked without an IDE" case_verify_reports_f21_unchecked_without_an_ide
run_case "verify reports F21 ok with an extension"    case_verify_reports_f21_ok_with_an_extension
run_case "verify notes an IDE without the extension"  case_verify_notes_an_ide_without_the_extension
run_case "verify says how to settle F19 and F20"      case_verify_says_how_to_settle_f19_and_f20
run_case "help and completions name code and idea"    case_help_and_completions_name_the_ide_commands

# ---------------------------------------------------------------------------
# A running editor
#
# The case the original tests could not reach. Every one of them ran under
# AGENT_PROFILE_DRY_RUN and asserted the command string, which was correct and
# still let a real defect through: -n does not stop VS Code handing the folder
# to an instance that is already up, so the window came back pinned to the
# wrong profile. These drive the decision instead of the string.
# ---------------------------------------------------------------------------

# fake_pgrep <dir> <running|quiet|broken>: a stand-in pgrep with a fixed
# answer, so the three branches of ide_running can each be reached from a test.
fake_pgrep() {
    mkdir -p "$1"
    case "$2" in
        running) printf '#!/bin/sh\nexit 0\n' > "$1/pgrep" ;;
        quiet)   printf '#!/bin/sh\nexit 1\n' > "$1/pgrep" ;;
        broken)  printf '#!/bin/sh\nexit 3\n' > "$1/pgrep" ;;
        *) fail "fake_pgrep: unknown mode '$2'"; return 1 ;;
    esac
    chmod +x "$1/pgrep"
}

case_code_refuses_when_the_editor_is_running() {
    ide_fixture
    fake_pgrep "$HOME/fakebin" running
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet /tmp/project 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "already running" || return
    assert_contains "$out" "--new-instance" || return
    # It must not have printed a launch it is refusing to perform.
    assert_not_contains "$out" "--env CLAUDE_CONFIG_DIR"
}

case_code_launches_when_the_editor_is_not_running() {
    ide_fixture
    fake_pgrep "$HOME/fakebin" quiet
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet /tmp/project 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "--env CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet"
}

# Fails closed. An unusable pgrep must read as "running", not as "clear to go":
# the cost of being wrong the other way is a session in another customer's root.
case_code_refuses_when_it_cannot_tell() {
    ide_fixture
    fake_pgrep "$HOME/fakebin" broken
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "could not be determined" || return
    assert_not_contains "$out" "--env CLAUDE_CONFIG_DIR"
}

case_new_instance_launches_past_a_running_editor() {
    ide_fixture
    fake_pgrep "$HOME/fakebin" running
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet /tmp/project --new-instance 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "--env CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet" || return
    assert_contains "$out" "--user-data-dir" || return
    assert_contains "$out" "/ide/Visual-Studio-Code" || return
    # The path still reaches the editor, after the user data directory rather
    # than straight after --args. Asserted as the last argument, because a path
    # that landed anywhere else would be read as a value for another flag.
    case "$out" in
        *" /tmp/project") ;;
        *) fail "the path must be the last argument" "got: $out"; return ;;
    esac
}

# The user data directory is what makes the instance separate, so it has to be
# the application's argument, after --args, exactly as --env has to be open's,
# before it. On the wrong side it is silently ignored and the instance is not
# separate at all.
case_new_instance_puts_user_data_dir_after_args() {
    ide_fixture
    fake_pgrep "$HOME/fakebin" running
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet --new-instance 2>&1)
    before=${out%%--args*}
    case "$before" in
        *--user-data-dir*) fail "--user-data-dir must come after --args" "got: $out"; return ;;
    esac
    assert_contains "$out" "--args --user-data-dir"
}

# It lives under the profile's app data directory, which remove --purge already
# deletes, so an offboarding does not leave a customer's editor state behind.
case_new_instance_user_data_dir_sits_under_the_app_data_dir() {
    ide_fixture
    fake_pgrep "$HOME/fakebin" running
    out=$(AGENT_PROFILE_DRY_RUN=1 ide code bouvet --new-instance 2>&1)
    assert_contains "$out" "Application Support/Claude-Bouvet/ide/Visual-Studio-Code"
}

case_new_instance_is_refused_for_jetbrains() {
    ide_fixture
    fake_pgrep "$HOME/fakebin" running
    out=$(AGENT_PROFILE_DRY_RUN=1 ide idea bouvet --new-instance 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "VS Code mechanism" || return
    assert_not_contains "$out" "--env CLAUDE_CONFIG_DIR"
}

case_idea_refuses_when_the_ide_is_running() {
    ide_fixture
    fake_pgrep "$HOME/fakebin" running
    out=$(AGENT_PROFILE_DRY_RUN=1 ide idea bouvet 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "already running"
}
run_case "code refuses a running editor"              case_code_refuses_when_the_editor_is_running
run_case "code launches when nothing is running"      case_code_launches_when_the_editor_is_not_running
run_case "code refuses when it cannot tell"           case_code_refuses_when_it_cannot_tell
run_case "--new-instance launches past a running one" case_new_instance_launches_past_a_running_editor
run_case "--user-data-dir comes after --args"         case_new_instance_puts_user_data_dir_after_args
run_case "the instance data sits under app data"      case_new_instance_user_data_dir_sits_under_the_app_data_dir
run_case "--new-instance is refused for JetBrains"    case_new_instance_is_refused_for_jetbrains
run_case "idea refuses a running IDE"                 case_idea_refuses_when_the_ide_is_running
