# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# shellcheck disable=SC2016  # recording_security generates script text; it must not expand here
#
# remove and remove --purge: retiring a profile when an engagement ends.
#
# This is the only command that deletes anything, so most of what is pinned
# here is what it refuses to do: purge without a terminal, purge on an answer
# that is not exactly the profile name, and purge a path the registry does not
# name or that a symlink could carry somewhere else. Every case runs in a
# throwaway HOME, so nothing real is ever in reach.

# retiring_profile <name>: a profile with an account and a session, the shape
# of one that has been worked in.
retiring_profile() {
    "$AP" new "$1" >/dev/null 2>&1
    fixture_account "$HOME/.claude-$1" "m@$1.example" "org-$1"
    fixture_transcript "$HOME/.claude-$1" "-U-m-$1" "/U/m/$1"
}

# handmade_profile <name> <root> <app-data>: a registry entry written by hand,
# which is how a root the tool would never have created gets in front of it.
handmade_profile() {
    mkdir -p "$HOME/.config/agent-profiles"
    printf 'agent=claude\nroot=%s\napp_data=%s\ncreated=2026-09-08\n' "$2" "$3" \
        > "$HOME/.config/agent-profiles/$1.conf"
}

# register_applet <name> <applet>: a launcher on disk that the profile's
# registry entry names, which is the state `app` leaves behind.
#
# The launch line is the generated form, so the fixture is a machine doctor is
# happy with. A launcher that was already wrong would make "quiet after a
# purge" prove much less than it looks.
register_applet() {
    _ra_data=$(sed -n 's/^app_data=//p' "$HOME/.config/agent-profiles/$1.conf" | head -1)
    fixture_applet "$2" "$(fixture_launch_line "$HOME/Claude.app" "$(reg_root_of "$1")" "$_ra_data")"
    printf 'applet=%s\n' "$2" >> "$HOME/.config/agent-profiles/$1.conf"
}

# recording_security <bindir>: a stand-in security(1) that writes down every
# call. The tool must never call it, so the marker file is the failure.
recording_security() {
    mkdir -p "$1"
    {
        printf '#!/bin/sh\n'
        printf 'printf "%%s\\n" "$*" >> "$HOME/security-was-called"\n'
        printf 'exit 0\n'
    } > "$1/security"
    chmod +x "$1/security"
}

# plain <args...>: remove without --purge.
plain() {
    USER=tester PATH="$HOME/fakebin:$PATH" "$AP" remove "$@" 2>&1
}

# purge <answer> <args...>: remove --purge, with that answer typed back at the
# confirmation prompt.
#
# AGENT_PROFILE_ASSUME_TTY stands in for a terminal, the same way the picker's
# cases fake one. A real pseudo-terminal would need script(1), whose arguments
# differ between BSD and util-linux, so it would be least reliable on macOS.
purge() {
    _pg_answer="$1"; shift
    printf '%s\n' "$_pg_answer" | \
        AGENT_PROFILE_ASSUME_TTY=1 USER=tester PATH="$HOME/fakebin:$PATH" \
        "$AP" remove "$@" --purge 2>&1
}

# rm_doctor: doctor with the stand-in AppleScript tools and the fixture's own
# applet directories, so the launcher rules really run rather than skipping.
rm_doctor() {
    PATH="$HOME/fakebin:$PATH" \
    AGENT_PROFILE_APP_BUNDLE="$HOME/Claude.app" \
    AGENT_PROFILE_APPLET_DIRS="$HOME/Applications:$HOME/Desktop" \
        "$AP" doctor 2>&1
}

# rm_doctor_mac: the same, as if on macOS against a stand-in Keychain.
rm_doctor_mac() {
    PATH="$HOME/fakebin:$PATH" \
    AGENT_PROFILE_PLATFORM=Darwin \
    USER=tester \
    AGENT_PROFILE_APP_BUNDLE="$HOME/Claude.app" \
    AGENT_PROFILE_APPLET_DIRS="$HOME/Applications:$HOME/Desktop" \
        "$AP" doctor 2>&1
}

# ---------------------------------------------------------------------------
# remove, with no flags
# ---------------------------------------------------------------------------

case_remove_unregisters_the_profile() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(plain bouvet); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Unregistered bouvet" || return
    [ -f "$HOME/.config/agent-profiles/bouvet.conf" ] && fail "the registry entry survived"
}

# The whole promise of the flagless form: it removes the record and nothing
# else. Anything it deleted here would be data nobody asked it to touch.
case_remove_leaves_every_path_alone() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    register_applet bouvet "$HOME/Applications/Claude-Bouvet.app"
    plain bouvet >/dev/null
    [ -d "$HOME/.claude-bouvet" ] || { fail "the root was deleted"; return; }
    [ -f "$HOME/.claude-bouvet/projects/-U-m-bouvet/s1.jsonl" ] || \
        { fail "the sessions were deleted"; return; }
    [ -d "$HOME/Library/Application Support/Claude-Bouvet" ] || \
        { fail "the app data directory was deleted"; return; }
    [ -d "$HOME/Applications/Claude-Bouvet.app" ] || fail "the launcher was deleted"
}

case_remove_names_the_root_with_its_session_count() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    fixture_transcript "$HOME/.claude-bouvet" "-U-m-second" "/U/m/second"
    out=$(plain bouvet)
    assert_contains "$out" "$HOME/.claude-bouvet" || return
    assert_contains "$out" "2 session(s)" || return
    assert_contains "$out" "rm -rf '$HOME/.claude-bouvet'"
}

# The order is part of the answer: root, app data, launcher, credential, which
# is the order they matter in and the order they are deleted in.
case_remove_lists_everything_left_in_order() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    register_applet bouvet "$HOME/Applications/Claude-Bouvet.app"
    out=$(plain bouvet)
    got=$(printf '%s\n' "$out" | \
        sed -n 's/^  \(config root\|app data\|launcher\|credential\) .*/\1/p' | tr '\n' ' ')
    assert_equals "config root app data launcher credential " "$got"
}

case_remove_prints_the_delete_command_for_each_path() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    register_applet bouvet "$HOME/Applications/Claude-Bouvet.app"
    out=$(plain bouvet)
    assert_contains "$out" "rm -rf '$HOME/.claude-bouvet'" || return
    assert_contains "$out" "rm -rf '$HOME/Library/Application Support/Claude-Bouvet'" || return
    assert_contains "$out" "rm -rf '$HOME/Applications/Claude-Bouvet.app'"
}

# The service name has to be the one cred_info derives, or the command printed
# deletes nothing and the reader believes the credential is gone.
case_remove_names_the_keychain_service_cred_info_derives() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(plain bouvet)
    assert_contains "$out" \
        "security delete-generic-password -s '$(cred_service_for "$HOME/.claude-bouvet")' -a 'tester'"
}

# The tool never touches credentials, and an offboarding command is the last
# place to make an exception. It prints the command and does not run it.
case_remove_never_calls_security() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    recording_security "$HOME/fakebin"
    plain bouvet >/dev/null
    [ -f "$HOME/security-was-called" ] && \
        fail "security was called" "$(cat "$HOME/security-was-called")"
}

case_remove_rejects_an_unknown_profile() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(plain nosuch); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "no such profile 'nosuch'" || return
    [ -f "$HOME/.config/agent-profiles/bouvet.conf" ] || fail "it removed something else"
}

case_remove_needs_a_profile_name() {
    HOME=$(new_home); export HOME
    out=$(plain); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "usage:"
}

case_remove_rejects_an_unknown_option() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(plain bouvet --wipe); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "unknown option '--wipe'" || return
    [ -f "$HOME/.config/agent-profiles/bouvet.conf" ] || fail "it acted before reading the flags"
}

# ---------------------------------------------------------------------------
# --purge: the refusals
# ---------------------------------------------------------------------------

# No script may ever purge. The typed confirmation is the whole safety
# mechanism, and a prompt nobody can answer is not one.
case_purge_refuses_when_stdin_is_not_a_terminal() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(printf 'bouvet\n' | USER=tester "$AP" remove bouvet --purge 2>&1); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "--purge needs a terminal" || return
    [ -d "$HOME/.claude-bouvet" ] || { fail "it deleted the root anyway"; return; }
    [ -f "$HOME/.config/agent-profiles/bouvet.conf" ] || fail "it removed the registry entry anyway"
}

case_purge_aborts_on_a_mistyped_name() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(purge "bouvett" bouvet); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "Aborted" || return
    assert_not_contains "$out" "Deleted" || return
    [ -d "$HOME/.claude-bouvet" ] || { fail "it deleted the root"; return; }
    [ -d "$HOME/Library/Application Support/Claude-Bouvet" ] || \
        { fail "it deleted the app data directory"; return; }
    [ -f "$HOME/.config/agent-profiles/bouvet.conf" ] || fail "it removed the registry entry"
}

# A prefix is not the name. Accepting one would mean the confirmation is
# testing that somebody typed roughly the right thing.
case_purge_aborts_on_a_prefix_of_the_name() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(purge "bouve" bouvet); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "Aborted" || return
    [ -d "$HOME/.claude-bouvet" ] || fail "it deleted the root"
}

case_purge_aborts_on_a_different_case() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(purge "Bouvet" bouvet); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "Aborted" || return
    [ -d "$HOME/.claude-bouvet" ] || fail "it deleted the root"
}

case_purge_aborts_on_an_empty_answer() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    out=$(purge "" bouvet); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "Aborted" || return
    [ -d "$HOME/.claude-bouvet" ] || fail "it deleted the root"
}

# A symlink is refused rather than followed. Deleting it would either take the
# data it points at, which was never this profile's, or leave that data behind
# while reporting the root gone.
case_purge_refuses_a_symlinked_root() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/elsewhere"
    printf 'someone else\n' > "$HOME/elsewhere/keep.txt"
    ln -s "$HOME/elsewhere" "$HOME/.claude-link"
    handmade_profile link "$HOME/.claude-link" "$HOME/data-link"
    out=$(purge "link" link); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "it is a symlink" || return
    [ -f "$HOME/elsewhere/keep.txt" ] || { fail "it deleted what the symlink pointed at"; return; }
    [ -L "$HOME/.claude-link" ] || { fail "it deleted the symlink"; return; }
    # The closing list has to name what is really still there.
    assert_contains "$out" "Left on this machine"
}

# Two entries at one root are one account wearing two names, so deleting the
# root while retiring one of them takes the other's data with it.
case_purge_refuses_a_root_another_profile_claims() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.claude-shared"
    handmade_profile aa "$HOME/.claude-shared" "$HOME/data-aa"
    handmade_profile bb "$HOME/.claude-shared" "$HOME/data-bb"
    out=$(purge "aa" aa); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "profile bb names it too" || return
    [ -d "$HOME/.claude-shared" ] || { fail "it deleted a root two profiles claim"; return; }
    [ -f "$HOME/.config/agent-profiles/bb.conf" ] || fail "it removed the other profile"
}

# The registry has to spell a path the way the tool writes it. "$HOME/.." is a
# real directory whose spelling says nothing about where it is, and doctor
# already reports the shape as D10.
case_purge_refuses_a_root_that_is_not_canonical() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.claude-slashy"
    handmade_profile slashy "$HOME/.claude-slashy/" "$HOME/data-slashy"
    out=$(purge "slashy" slashy); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "not canonical" || return
    [ -d "$HOME/.claude-slashy" ] || fail "it deleted the root"
}

case_purge_refuses_a_root_that_is_not_a_directory() {
    HOME=$(new_home); export HOME
    printf 'not a root\n' > "$HOME/.claude-file"
    handmade_profile filey "$HOME/.claude-file" "$HOME/data-filey"
    out=$(purge "filey" filey); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "it is not a directory" || return
    [ -f "$HOME/.claude-file" ] || fail "it deleted the file"
}

# Where a launcher would conventionally be is a guess. Deleting one on a guess
# is deleting a bundle nobody registered, which could be anybody's.
case_purge_leaves_a_launcher_the_registry_does_not_name() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    fixture_applet "$HOME/Applications/Claude-Bouvet.app" \
        "$(fixture_launch_line "$HOME/Claude.app" "$HOME/.claude-bouvet" "$HOME/x")"
    out=$(purge "bouvet" bouvet); status=$?
    assert_status 1 "$status" || return
    assert_contains "$out" "the registry entry does not name it" || return
    [ -d "$HOME/Applications/Claude-Bouvet.app" ] || { fail "it deleted an unregistered launcher"; return; }
    assert_contains "$out" "rm -rf '$HOME/Applications/Claude-Bouvet.app'"
}

# ---------------------------------------------------------------------------
# --purge: what it does when it is allowed to
# ---------------------------------------------------------------------------

case_purge_deletes_the_root_the_app_data_and_the_launcher() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    register_applet bouvet "$HOME/Applications/Claude-Bouvet.app"
    out=$(purge "bouvet" bouvet); status=$?
    assert_status 0 "$status" "$out" || return
    [ -e "$HOME/.claude-bouvet" ] && { fail "the root survived"; return; }
    [ -e "$HOME/Library/Application Support/Claude-Bouvet" ] && \
        { fail "the app data directory survived"; return; }
    [ -e "$HOME/Applications/Claude-Bouvet.app" ] && { fail "the launcher survived"; return; }
    [ -e "$HOME/.config/agent-profiles/bouvet.conf" ] && { fail "the registry entry survived"; return; }
    assert_contains "$out" "Unregistered bouvet"
}

# Nothing is left behind beside the deleted path either. The item is moved
# into a scratch directory before it is deleted, and that has to go too.
case_purge_leaves_nothing_beside_the_root() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    purge "bouvet" bouvet >/dev/null
    for leftover in "$HOME"/.agent-profile-removing.*; do
        [ -e "$leftover" ] && fail "a scratch directory was left beside the root" "$leftover"
    done
}

case_purge_leaves_another_profile_untouched() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    retiring_profile tide
    purge "bouvet" bouvet >/dev/null
    [ -d "$HOME/.claude-tide" ] || { fail "it deleted the other root"; return; }
    [ -f "$HOME/.claude-tide/projects/-U-m-tide/s1.jsonl" ] || \
        { fail "it deleted the other profile's sessions"; return; }
    [ -d "$HOME/Library/Application Support/Claude-Tide" ] || \
        { fail "it deleted the other app data directory"; return; }
    [ -f "$HOME/.config/agent-profiles/tide.conf" ] || fail "it removed the other registry entry"
}

# Even here the credential is only ever printed. This is the case that would
# catch --purge quietly growing a security(1) call.
case_purge_only_prints_the_credential_command() {
    HOME=$(new_home); export HOME
    retiring_profile bouvet
    recording_security "$HOME/fakebin"
    service=$(cred_service_for "$HOME/.claude-bouvet")
    out=$(purge "bouvet" bouvet)
    assert_contains "$out" "security delete-generic-password -s '$service' -a 'tester'" || return
    [ -f "$HOME/security-was-called" ] && \
        fail "security was called" "$(cat "$HOME/security-was-called")"
}

# ---------------------------------------------------------------------------
# What doctor says afterwards
# ---------------------------------------------------------------------------

# What a bare remove leaves behind, so the case below cannot pass because
# there was nothing to find in the first place. This is also the argument for
# --purge: unregistering alone turns a tidy machine into two findings.
case_doctor_reports_what_a_bare_remove_leaves() {
    HOME=$(new_home); export HOME
    fake_osa "$HOME/fakebin"
    retiring_profile bouvet
    retiring_profile tide
    register_applet bouvet "$HOME/Applications/Claude-Bouvet.app"
    before=$(rm_doctor); status=$?
    assert_status 0 "$status" "$before" || return
    plain bouvet >/dev/null
    out=$(rm_doctor); status=$?
    assert_status 2 "$status" || return
    assert_contains "$out" "D06" || return
    assert_contains "$out" "D14"
}

# The promise the README makes about offboarding, checked rather than
# asserted: once a profile is purged, the audit has nothing left to find.
case_doctor_is_quiet_after_a_purge() {
    HOME=$(new_home); export HOME
    fake_osa "$HOME/fakebin"
    retiring_profile bouvet
    retiring_profile tide
    register_applet bouvet "$HOME/Applications/Claude-Bouvet.app"
    purge "bouvet" bouvet >/dev/null
    out=$(rm_doctor); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "No isolation problems found across 1 profile(s)."
}

# The one thing a purge cannot clean up, because the tool never touches
# credentials: the Keychain entry stays, and doctor keeps counting it as an
# orphan until the printed command is run. Everything else is quiet.
case_doctor_still_reports_the_purged_keychain_entry() {
    HOME=$(new_home); export HOME
    fake_osa "$HOME/fakebin"
    retiring_profile bouvet
    retiring_profile tide
    register_applet bouvet "$HOME/Applications/Claude-Bouvet.app"
    fake_keychain "$HOME/fakebin" \
        "$(cred_service_for "$HOME/.claude-bouvet")" \
        "$(cred_service_for "$HOME/.claude-tide")"
    purge "bouvet" bouvet >/dev/null
    out=$(rm_doctor_mac); status=$?
    assert_status 2 "$status" "$out" || return
    assert_contains "$out" "D12" || return
    assert_contains "$out" "1 Keychain credential entr(ies) belong to no known root" || return
    for rule in D04 D05 D06 D07 D13 D14 D15; do
        assert_not_contains "$out" "$rule" || return
    done
}

run_case "remove unregisters the profile"             case_remove_unregisters_the_profile
run_case "remove leaves every path alone"             case_remove_leaves_every_path_alone
run_case "remove names the root and its sessions"     case_remove_names_the_root_with_its_session_count
run_case "remove lists what is left, in order"        case_remove_lists_everything_left_in_order
run_case "remove prints a delete command per path"    case_remove_prints_the_delete_command_for_each_path
run_case "remove names the derived Keychain service"  case_remove_names_the_keychain_service_cred_info_derives
run_case "remove never calls security"                case_remove_never_calls_security
run_case "remove rejects an unknown profile"          case_remove_rejects_an_unknown_profile
run_case "remove needs a profile name"                case_remove_needs_a_profile_name
run_case "remove rejects an unknown option"           case_remove_rejects_an_unknown_option
run_case "--purge refuses without a terminal"         case_purge_refuses_when_stdin_is_not_a_terminal
run_case "--purge aborts on a mistyped name"          case_purge_aborts_on_a_mistyped_name
run_case "--purge aborts on a prefix of the name"     case_purge_aborts_on_a_prefix_of_the_name
run_case "--purge aborts on a different case"         case_purge_aborts_on_a_different_case
run_case "--purge aborts on an empty answer"          case_purge_aborts_on_an_empty_answer
run_case "--purge refuses a symlinked root"           case_purge_refuses_a_symlinked_root
run_case "--purge refuses a shared root"              case_purge_refuses_a_root_another_profile_claims
run_case "--purge refuses a non-canonical root"       case_purge_refuses_a_root_that_is_not_canonical
run_case "--purge refuses a root that is a file"      case_purge_refuses_a_root_that_is_not_a_directory
run_case "--purge leaves an unregistered launcher"    case_purge_leaves_a_launcher_the_registry_does_not_name
run_case "--purge deletes root, app data and applet"  case_purge_deletes_the_root_the_app_data_and_the_launcher
run_case "--purge leaves nothing beside the root"     case_purge_leaves_nothing_beside_the_root
run_case "--purge leaves another profile untouched"   case_purge_leaves_another_profile_untouched
run_case "--purge only prints the credential command" case_purge_only_prints_the_credential_command
run_case "doctor reports what a bare remove leaves"   case_doctor_reports_what_a_bare_remove_leaves
run_case "doctor is quiet after a purge"              case_doctor_is_quiet_after_a_purge
run_case "doctor still reports the Keychain entry"    case_doctor_still_reports_the_purged_keychain_entry
