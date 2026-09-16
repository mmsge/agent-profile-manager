# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# doctor: one case per rule, plus the clean case.

# doctor_out: runs doctor and stashes output and status.
doctor_out() {
    DOUT=$("$AP" doctor 2>&1)
    DSTATUS=$?
}

# two_clean_profiles: a healthy two-profile machine.
two_clean_profiles() {
    "$AP" new brygga >/dev/null 2>&1
    "$AP" new havnelab >/dev/null 2>&1
    fixture_account "$HOME/.claude-brygga" "m@brygga.no" "org-b"
    fixture_account "$HOME/.claude-havnelab" "m@havnelab.no" "org-h"
    fixture_transcript "$HOME/.claude-brygga" "-Users-m-dev-b" "/Users/m/dev/b"
    fixture_transcript "$HOME/.claude-havnelab" "-Users-m-dev-h" "/Users/m/dev/h"
}

case_clean_exits_zero() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    doctor_out
    assert_status 0 "$DSTATUS" "$DOUT" || return
    assert_contains "$DOUT" "No isolation problems found"
}

# A clean run off macOS is a much smaller claim than a clean run on one, and
# the terminal did not say so: the rules that did not run and the two that ran
# with less than their full reach were in --json and --report only
# (portability gap 5). One line now names them, in the shape the D12 skip note
# already has.
case_a_clean_run_says_which_rules_did_not_run() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    doctor_out
    assert_status 0 "$DSTATUS" "$DOUT" || return
    assert_contains "$DOUT" "did not run" || return
    assert_contains "$DOUT" "D17" || return
    assert_contains "$DOUT" "D18" || return
    assert_contains "$DOUT" "were limited" || return
    assert_contains "$DOUT" "D16" || return
    assert_contains "$DOUT" "doctor --json"
}

# Every rule it names has to be one the document really reports that way, or
# the line is a second place where the truth is written down.
case_the_rules_a_clean_run_names_are_the_ones_the_document_skipped() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    doctor_out
    named=$(printf '%s\n' "$DOUT" | grep 'did not run' | grep -o 'D[0-9][0-9]' | sort -u | tr '\n' ' ')
    [ -n "$named" ] || { fail "the clean run named no rule at all" "$DOUT"; return; }
    for rule in $named; do
        status=$("$AP" doctor --json 2>/dev/null | python3 -c '
import json, sys
doc = json.load(sys.stdin)
for rule in doc["rules"]:
    if rule["rule"] == sys.argv[1]:
        print(rule["status"])
        break
' "$rule")
        case "$status" in
            not_run|limited) ;;
            *) fail "the clean run named a rule the document calls $status" "rule: $rule" ;;
        esac
    done
}

# With a finding the terminal has something to say already, and this line is
# not it.
case_a_run_with_findings_does_not_list_the_skipped_rules() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    chmod 755 "$HOME/.claude-brygga"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D07" || return
    assert_not_contains "$DOUT" "did not run"
}

# The line is about this run, not about the machine, so it stays out of the
# document the way the "Wrote ..." lines do.
case_the_skipped_rule_line_is_not_in_the_document() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    out=$("$AP" doctor --json 2>/dev/null)
    assert_not_contains "$out" "did not run on this platform"
}

case_d01_unpinned_default_root() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    fixture_transcript "$HOME/.claude" "-Users-m-dev-leaked" "/Users/m/dev/leaked"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D01" || return
    assert_contains "$DOUT" "default claude root holds 1 session"
}

case_d02_stray_state_file() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    printf '{}\n' > "$HOME/.claude.json"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D02"
}

case_d03_same_project_under_two_roots() {
    # The rule that replaces a hand-maintained prefix list. It reads the real
    # cwd from transcript metadata, so it needs no configuration at all.
    HOME=$(new_home); export HOME
    two_clean_profiles
    fixture_transcript "$HOME/.claude-brygga"   "-Users-m-dev-shared" "/Users/m/dev/shared"
    fixture_transcript "$HOME/.claude-havnelab" "-Users-m-dev-shared" "/Users/m/dev/shared"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D03" || return
    assert_contains "$DOUT" "/Users/m/dev/shared" || return
    assert_contains "$DOUT" ".claude-brygga" || return
    assert_contains "$DOUT" ".claude-havnelab"
}

case_d03_ignores_a_path_in_one_root_only() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    fixture_transcript "$HOME/.claude-brygga" "-Users-m-dev-solo" "/Users/m/dev/solo"
    doctor_out
    assert_not_contains "$DOUT" "D03"
}

case_d03_is_not_fooled_by_encoding_collisions() {
    # my_repo, my-repo and my.repo all encode to the same directory name. The
    # rule must compare real cwd values, not directory names, or it would
    # report a leak that is not there.
    HOME=$(new_home); export HOME
    two_clean_profiles
    fixture_transcript "$HOME/.claude-brygga"   "-Users-m-dev-my-repo" "/Users/m/dev/my_repo"
    fixture_transcript "$HOME/.claude-havnelab" "-Users-m-dev-my-repo" "/Users/m/dev/my.repo"
    doctor_out
    assert_not_contains "$DOUT" "D03"
}

case_d04_missing_registered_root() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    rm -rf "$HOME/.claude-brygga"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D04"
}

case_d05_no_credential_and_no_account() {
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D05"
}

case_d05_quiet_when_signed_in_via_keychain() {
    # On macOS the credential lives in the Keychain, so a missing
    # .credentials.json is not proof. An account on record means signed in.
    HOME=$(new_home); export HOME
    "$AP" new brygga >/dev/null 2>&1
    fixture_account "$HOME/.claude-brygga" "m@brygga.no" "org-b"
    doctor_out
    # The finding shape, two spaces after the rule id, rather than the bare
    # id: a clean run names D05 in the line about which rules were limited,
    # and that line is not a finding.
    assert_not_contains "$DOUT" "D05  "
}

case_d06_unregistered_root() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    mkdir -p "$HOME/.claude-torg"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D06" || return
    assert_contains "$DOUT" ".claude-torg"
}

case_d07_wrong_mode() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    chmod 755 "$HOME/.claude-brygga"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D07" || return
    assert_contains "$DOUT" "mode 755"
}

# The app data directory holds the desktop app's own login and its embedded
# agent, so it is audited to the same standard as the root.
case_d07_app_data_dir_wrong_mode() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    chmod 755 "$HOME/Library/Application Support/Claude-Brygga"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D07" || return
    assert_contains "$DOUT" "app data directory is mode 755"
}

case_d08_project_dir_that_is_not_a_path() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    fixture_transcript "$HOME/.claude-brygga" "work" "/Users/m/dev/renamed"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D08"
}

case_doctor_with_no_profiles_is_not_a_finding() {
    HOME=$(new_home); export HOME
    doctor_out
    assert_status 0 "$DSTATUS" || return
    assert_contains "$DOUT" "nothing to audit"
}

# The guard used to be "does some profile claim the default root", which is a
# different question. The state file lives beside the default root, never
# inside it, so claiming that root does not make this file legitimate. On the
# first real machine this ran on, that hid a 104 KB state file holding an
# account none of the registered profiles owns.
case_d02_fires_even_when_the_default_root_is_claimed() {
    HOME=$(new_home); export HOME
    "$AP" new brygga --root "$HOME/.claude" >/dev/null 2>&1
    fixture_account "$HOME/.claude" "m@brygga.no" "org-b"
    # The stray one, beside the root rather than in it, holding someone else.
    printf '{"oauthAccount":{"emailAddress":"stranger@example.com"}}\n' > "$HOME/.claude.json"

    out=$("$AP" doctor 2>&1)
    assert_contains "$out" "D02" || return
    assert_contains "$out" "stranger@example.com"
}

case_d02_quiet_when_the_state_file_is_inside_a_root() {
    HOME=$(new_home); export HOME
    "$AP" new odd --root "$HOME" >/dev/null 2>&1
    printf '{"oauthAccount":{"emailAddress":"m@example.com"}}\n' > "$HOME/.claude.json"
    assert_not_contains "$("$AP" doctor 2>&1)" "D02"
}

# ---------------------------------------------------------------------------
# D19: the sessions server registration
# ---------------------------------------------------------------------------

case_d19_quiet_on_a_clean_machine() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    doctor_out
    assert_not_contains "$DOUT" "D19"
}

case_d19_quiet_when_a_profile_is_simply_off() {
    # Off is a choice, not a finding. list and mcp status show it.
    HOME=$(new_home); export HOME
    two_clean_profiles
    "$AP" mcp off brygga >/dev/null 2>&1
    doctor_out
    assert_status 0 "$DSTATUS" "$DOUT" || return
    assert_not_contains "$DOUT" "D19"
}

case_d19_registration_naming_another_root() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    # A state file restored into the wrong root: havnelab's file now carries
    # brygga's registration.
    cp "$HOME/.claude-brygga/.claude.json" "$HOME/.claude-havnelab/.claude.json"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D19" || return
    assert_contains "$DOUT" "havnelab is stale" || return
    assert_contains "$DOUT" "names another root" || return
    assert_contains "$DOUT" "Fix with: agent-profile mcp on havnelab"
}

case_d19_fix_line_run_as_printed_quiets_it() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    cp "$HOME/.claude-brygga/.claude.json" "$HOME/.claude-havnelab/.claude.json"
    doctor_out
    assert_contains "$DOUT" "D19" || return
    "$AP" mcp on havnelab >/dev/null 2>&1
    doctor_out
    assert_not_contains "$DOUT" "D19" || return
    assert_status 0 "$DSTATUS" "$DOUT"
}

case_d19_registration_whose_command_is_gone() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    python3 - "$HOME/.claude-brygga/.claude.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["mcpServers"]["sessions"]["command"] = "/no/such/agpin"
json.dump(d, open(p, "w"))
PY
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D19" || return
    assert_contains "$DOUT" "missing or not executable"
}

case_d19_leaves_a_foreign_sessions_entry_alone() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    printf '{"oauthAccount":{"emailAddress":"m@brygga.no","organizationUuid":"org-b"},"mcpServers":{"sessions":{"type":"stdio","command":"/usr/bin/theirs","args":["--serve"]}}}\n' \
        > "$HOME/.claude-brygga/.claude.json"
    doctor_out
    assert_not_contains "$DOUT" "D19"
}

case_d19_registration_in_the_stray_state_file() {
    # An unpinned run given a sessions server: the stray file beside the
    # default root carries the registration, and no profile owns that file.
    HOME=$(new_home); export HOME
    two_clean_profiles
    cp "$HOME/.claude-brygga/.claude.json" "$HOME/.claude.json"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D19" || return
    assert_contains "$DOUT" "stray claude state file" || return
    assert_contains "$DOUT" "claude mcp remove --scope user sessions"
}

case_d19_reads_only_the_mcp_servers_block() {
    # The finding names the command and its arguments and nothing else from
    # the file: a canary in every other key must not surface.
    HOME=$(new_home); export HOME
    two_clean_profiles
    python3 - "$HOME/.claude-brygga/.claude.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["mcpServers"]["sessions"]["args"][3] = "/somewhere/else"
d["oauthAccount"]["emailAddress"] = "CANARY-EMAIL"
d["projects"] = {"/x": {"allowedTools": ["CANARY-TOOL"]}}
json.dump(d, open(p, "w"))
PY
    doctor_out
    assert_contains "$DOUT" "D19" || return
    assert_not_contains "$DOUT" "CANARY-TOOL" || return
    # The account line list prints is a different reader; D19's own text
    # must not carry the email.
    d19=$(printf '%s\n' "$DOUT" | awk '/^D19/{f=1} f && /^$/{f=0} f')
    assert_not_contains "$d19" "CANARY-EMAIL"
}

run_case "a clean machine exits 0"                    case_clean_exits_zero
run_case "a clean run says which rules were skipped"  case_a_clean_run_says_which_rules_did_not_run
run_case "the rules it names are the skipped ones"    case_the_rules_a_clean_run_names_are_the_ones_the_document_skipped
run_case "a run with findings omits that line"        case_a_run_with_findings_does_not_list_the_skipped_rules
run_case "the skipped-rule line is not in the doc"    case_the_skipped_rule_line_is_not_in_the_document
run_case "D01 the default root holds sessions"        case_d01_unpinned_default_root
run_case "D02 a stray state file"                     case_d02_stray_state_file
run_case "D03 the same project under two roots"       case_d03_same_project_under_two_roots
run_case "D03 ignores a project in one root only"     case_d03_ignores_a_path_in_one_root_only
run_case "D03 is not fooled by encoding collisions"   case_d03_is_not_fooled_by_encoding_collisions
run_case "D04 a registered root that is missing"      case_d04_missing_registered_root
run_case "D05 no credential and no account"           case_d05_no_credential_and_no_account
run_case "D05 stays quiet for a Keychain login"       case_d05_quiet_when_signed_in_via_keychain
run_case "D06 an unregistered root"                   case_d06_unregistered_root
run_case "D07 a root that is not mode 700"            case_d07_wrong_mode
run_case "D07 an app data dir that is not mode 700"   case_d07_app_data_dir_wrong_mode
run_case "D08 a project dir that is not a path"       case_d08_project_dir_that_is_not_a_path
run_case "no profiles is not a finding"               case_doctor_with_no_profiles_is_not_a_finding
run_case "D02 fires though the default root is claimed" case_d02_fires_even_when_the_default_root_is_claimed
run_case "D02 quiet when the state file is in a root"   case_d02_quiet_when_the_state_file_is_inside_a_root
run_case "D19 is quiet on a clean machine"               case_d19_quiet_on_a_clean_machine
run_case "D19 is quiet when a profile is simply off"     case_d19_quiet_when_a_profile_is_simply_off
run_case "D19 registration naming another root"          case_d19_registration_naming_another_root
run_case "D19's fix line, run as printed, quiets it"     case_d19_fix_line_run_as_printed_quiets_it
run_case "D19 registration whose command is gone"        case_d19_registration_whose_command_is_gone
run_case "D19 leaves a foreign sessions entry alone"     case_d19_leaves_a_foreign_sessions_entry_alone
run_case "D19 registration in the stray state file"      case_d19_registration_in_the_stray_state_file
run_case "D19 reads only the mcpServers block"           case_d19_reads_only_the_mcp_servers_block
