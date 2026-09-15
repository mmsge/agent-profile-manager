# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# mcp: the sessions server registration and its launcher.
#
# Every case runs against the harness's stand-in registrar, which edits
# $CLAUDE_CONFIG_DIR/.claude.json the way `claude mcp add` and `claude mcp
# remove` do and refuses the same things, and against a stand-in interpreter
# that records what `mcp serve` asked it to run. No case starts the agent or
# a Python interpreter.

# registration_of <root>: the sessions entry in a root's state file, as JSON,
# or "null".
registration_of() {
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("null"); sys.exit(0)
print(json.dumps(d.get("mcpServers", {}).get("sessions")))
' "$1/.claude.json"
}

# ---------------------------------------------------------------------------
# on, off, status
# ---------------------------------------------------------------------------

case_new_registers_the_launcher_pinned_to_the_root() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    reg=$(registration_of "$HOME/.claude-bouvet")
    assert_contains "$reg" '"type": "stdio"' || return
    assert_contains "$reg" "\"args\": [\"mcp\", \"serve\", \"--root\", \"$HOME/.claude-bouvet\"]" || return
    # The command is an absolute path to this tool, never a relative name.
    cmd=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["command"])' "$reg")
    case "$cmd" in
        /*) ;;
        *) fail "the registered command is not absolute" "$cmd"; return ;;
    esac
    [ -x "$cmd" ] || fail "the registered command is not executable" "$cmd"
}

case_the_registrar_is_run_pinned_and_at_user_scope() {
    # The stand-in refuses any scope but user, so a pass here already proves
    # the scope. This pins the pin: the log records the argv, and the state
    # file the stand-in wrote sits inside the root, which it only does when
    # CLAUDE_CONFIG_DIR named that root.
    HOME=$(new_home); export HOME
    FAKE_REGISTRAR_LOG="$HOME/registrar.log"; export FAKE_REGISTRAR_LOG
    "$AP" new bouvet >/dev/null 2>&1
    assert_contains "$(cat "$HOME/registrar.log")" "mcp add --scope user sessions --" || return
    [ -f "$HOME/.claude-bouvet/.claude.json" ] || fail "the registration did not land in the root"
    [ -f "$HOME/.claude.json" ] && fail "something wrote the stray state file"
    unset FAKE_REGISTRAR_LOG
}

case_status_reports_on_off_and_stale() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new highsoft >/dev/null 2>&1
    "$AP" new tide >/dev/null 2>&1
    "$AP" mcp off highsoft >/dev/null 2>&1
    cp "$HOME/.claude-bouvet/.claude.json" "$HOME/.claude-tide/.claude.json"
    out=$("$AP" mcp status 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "bouvet         on" || return
    assert_contains "$out" "highsoft       off" || return
    assert_contains "$out" "tide           stale" || return
    assert_contains "$out" "names another root: $HOME/.claude-bouvet"
}

case_status_for_one_profile() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new highsoft >/dev/null 2>&1
    out=$("$AP" mcp status highsoft 2>&1)
    assert_contains "$out" "highsoft" || return
    assert_not_contains "$out" "bouvet"
}

case_off_then_on_round_trips() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    before=$(registration_of "$HOME/.claude-bouvet")
    out=$("$AP" mcp off bouvet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Sessions server: off (removed from" || return
    assert_equals "null" "$(registration_of "$HOME/.claude-bouvet")" || return
    out=$("$AP" mcp on bouvet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Sessions server: on (registered in" || return
    assert_equals "$before" "$(registration_of "$HOME/.claude-bouvet")"
}

case_on_and_off_are_idempotent() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$("$AP" mcp on bouvet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "already registered" || return
    "$AP" mcp off bouvet >/dev/null 2>&1
    out=$("$AP" mcp off bouvet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "nothing registered"
}

case_on_replaces_a_stale_registration() {
    # The CLI refuses to add a name that exists, so on has to take the stale
    # entry out first, and the result has to be a clean registration.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new tide >/dev/null 2>&1
    good=$(registration_of "$HOME/.claude-tide")
    cp "$HOME/.claude-bouvet/.claude.json" "$HOME/.claude-tide/.claude.json"
    out=$("$AP" mcp on tide 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "$good" "$(registration_of "$HOME/.claude-tide")"
}

case_on_and_off_refuse_a_foreign_entry() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    printf '{"mcpServers":{"sessions":{"type":"stdio","command":"/usr/bin/theirs","args":["--serve"]}}}\n' \
        > "$HOME/.claude-bouvet/.claude.json"
    before=$(cat "$HOME/.claude-bouvet/.claude.json")
    out=$("$AP" mcp on bouvet 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "not this tool's" || return
    out=$("$AP" mcp off bouvet 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "yours to remove" || return
    assert_equals "$before" "$(cat "$HOME/.claude-bouvet/.claude.json")" || return
    assert_contains "$("$AP" mcp status bouvet 2>&1)" "foreign"
}

case_on_without_the_agent_says_so_and_exits_1() {
    HOME=$(new_home); export HOME
    AGENT_PROFILE_MCP_REGISTRAR="$HOME/no-such-claude" "$AP" new bouvet >/dev/null 2>&1
    out=$(AGENT_PROFILE_MCP_REGISTRAR="$HOME/no-such-claude" "$AP" mcp on bouvet 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "claude is not on PATH" || return
    assert_equals "null" "$(registration_of "$HOME/.claude-bouvet")"
}

case_a_registrar_that_fails_costs_a_line_not_the_profile() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/bin"
    printf '#!/bin/sh\necho "stand-in claude: boom" >&2\nexit 7\n' > "$HOME/bin/claude"
    chmod +x "$HOME/bin/claude"
    out=$(AGENT_PROFILE_MCP_REGISTRAR="$HOME/bin/claude" "$AP" new bouvet 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Created profile bouvet" || return
    assert_contains "$out" "mcp add failed" || return
    assert_contains "$out" "boom" || return
    assert_contains "$out" "Try again with:  agent-profile mcp on bouvet" || return
    [ -f "$HOME/.config/agent-profiles/bouvet.conf" ] || fail "the profile was not registered"
}

case_list_shows_the_server_state() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new highsoft >/dev/null 2>&1
    "$AP" mcp off highsoft >/dev/null 2>&1
    out=$("$AP" list 2>&1)
    assert_contains "$out" "mcp       on" || return
    assert_contains "$out" "mcp       off" || return
    json=$("$AP" list --json 2>&1)
    assert_contains "$json" '"sessions_server": "on"' || return
    assert_contains "$json" '"sessions_server": "off"'
}

case_usage_errors() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$("$AP" mcp 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "usage: agent-profile mcp on <name> | off <name> | status [name]" || return
    out=$("$AP" mcp toggle bouvet 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown mcp subcommand 'toggle'" || return
    out=$("$AP" mcp on nope 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "no such profile" || return
    out=$("$AP" mcp on bouvet --force 2>&1); status=$?
    assert_status 1 "$status" || return
    out=$("$AP" mcp status --json 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown option '--json'"
}

# ---------------------------------------------------------------------------
# serve: the launcher
# ---------------------------------------------------------------------------

case_serve_execs_the_interpreter_when_the_pin_matches() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude-bouvet" "$AP" mcp serve --root "$HOME/.claude-bouvet" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "server python: -m agent_profile_sessions --root $HOME/.claude-bouvet" || return
    assert_contains "$out" "CLAUDE_CONFIG_DIR=$HOME/.claude-bouvet" || return
    # The package directory beside the interpreter is on the path.
    assert_contains "$out" "PYTHONPATH="
}

case_serve_tolerates_a_trailing_slash_on_either_side() {
    HOME=$(new_home); export HOME
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude-bouvet/" "$AP" mcp serve --root "$HOME/.claude-bouvet" 2>&1); status=$?
    assert_status 0 "$status" "$out"
}

case_serve_refuses_when_unpinned() {
    HOME=$(new_home); export HOME
    out=$(env -u CLAUDE_CONFIG_DIR "$AP" mcp serve --root "$HOME/.claude-bouvet" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "refusing to start: CLAUDE_CONFIG_DIR is unset" || return
    assert_not_contains "$out" "server python:"
}

case_serve_refuses_a_root_that_is_not_the_pinned_one() {
    # The whole point: a registration that wandered into another root must
    # not serve that root's transcripts.
    HOME=$(new_home); export HOME
    out=$(CLAUDE_CONFIG_DIR="$HOME/.claude-highsoft" "$AP" mcp serve --root "$HOME/.claude-bouvet" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "refusing to start" || return
    assert_contains "$out" "CLAUDE_CONFIG_DIR is $HOME/.claude-highsoft, --root is $HOME/.claude-bouvet" || return
    assert_not_contains "$out" "server python:"
}

case_serve_says_when_the_server_is_not_installed() {
    HOME=$(new_home); export HOME
    out=$(CLAUDE_CONFIG_DIR="$HOME/r" AGENT_PROFILE_SERVER_PYTHON="$HOME/no/python" "$AP" mcp serve --root "$HOME/r" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "the sessions server is not installed" || return
    assert_contains "$out" "tools/install.sh"
}

case_serve_finds_the_environment_beside_the_installed_link() {
    # With no override, the interpreter is looked for relative to the script
    # the invoked link resolves to, which is how a Homebrew or ~/.local install
    # finds server/.venv without any path in the root.
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/tree/bin" "$HOME/tree/server/.venv/bin" "$HOME/bin"
    cp "$ROOT/bin/agent-profile" "$HOME/tree/bin/agent-profile"
    fake_server_python "$HOME/tree/server/.venv/bin/python"
    ln -s "$HOME/tree/bin/agent-profile" "$HOME/bin/agpin"
    out=$(CLAUDE_CONFIG_DIR="$HOME/r" AGENT_PROFILE_SERVER_PYTHON='' \
        "${BASH:-/bin/bash}" "$HOME/bin/agpin" mcp serve --root "$HOME/r" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "server python: -m agent_profile_sessions --root $HOME/r" || return
    assert_contains "$out" "PYTHONPATH=$HOME/tree/server"
}

case_serve_usage() {
    HOME=$(new_home); export HOME
    out=$(CLAUDE_CONFIG_DIR="$HOME/r" "$AP" mcp serve 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "usage: agent-profile mcp serve --root PATH" || return
    out=$(CLAUDE_CONFIG_DIR="$HOME/r" "$AP" mcp serve --root 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "--root needs a value" || return
    out=$(CLAUDE_CONFIG_DIR="$HOME/r" "$AP" mcp serve --root "$HOME/r" --port 80 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown argument --port"
}

case_serve_uses_the_invoked_name() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/named"
    ln -sf "$ROOT/bin/agent-profile" "$HOME/named/agpin"
    out=$(env -u CLAUDE_CONFIG_DIR "${BASH:-/bin/bash}" "$HOME/named/agpin" mcp serve --root "$HOME/r" 2>&1)
    assert_contains "$out" "agpin mcp serve: refusing to start"
}

run_case "new registers the launcher pinned to the root"    case_new_registers_the_launcher_pinned_to_the_root
run_case "the registrar runs pinned and at user scope"      case_the_registrar_is_run_pinned_and_at_user_scope
run_case "status reports on, off and stale"                 case_status_reports_on_off_and_stale
run_case "status for one profile"                           case_status_for_one_profile
run_case "off then on round-trips"                          case_off_then_on_round_trips
run_case "on and off are idempotent"                        case_on_and_off_are_idempotent
run_case "on replaces a stale registration"                 case_on_replaces_a_stale_registration
run_case "on and off refuse a foreign entry"                case_on_and_off_refuse_a_foreign_entry
run_case "on without the agent says so and exits 1"         case_on_without_the_agent_says_so_and_exits_1
run_case "a failing registrar costs a line, not the profile" case_a_registrar_that_fails_costs_a_line_not_the_profile
run_case "list shows the server state"                      case_list_shows_the_server_state
run_case "mcp usage errors"                                 case_usage_errors
run_case "serve execs the interpreter when the pin matches" case_serve_execs_the_interpreter_when_the_pin_matches
run_case "serve tolerates a trailing slash"                 case_serve_tolerates_a_trailing_slash_on_either_side
run_case "serve refuses when unpinned"                      case_serve_refuses_when_unpinned
run_case "serve refuses a root that is not the pinned one"  case_serve_refuses_a_root_that_is_not_the_pinned_one
run_case "serve says when the server is not installed"      case_serve_says_when_the_server_is_not_installed
run_case "serve finds the environment beside the link"      case_serve_finds_the_environment_beside_the_installed_link
run_case "serve usage"                                      case_serve_usage
run_case "serve uses the invoked name"                      case_serve_uses_the_invoked_name
