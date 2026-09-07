# shellcheck shell=bash
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# doctor: one case per rule, plus the clean case.

# doctor_out: runs doctor and stashes output and status.
doctor_out() {
    DOUT=$("$AP" doctor 2>&1)
    DSTATUS=$?
}

# two_clean_profiles: a healthy two-profile machine.
two_clean_profiles() {
    "$AP" new bouvet >/dev/null 2>&1
    "$AP" new highsoft >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_account "$HOME/.claude-highsoft" "m@highsoft.no" "org-h"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
    fixture_transcript "$HOME/.claude-highsoft" "-Users-m-dev-h" "/Users/m/dev/h"
}

case_clean_exits_zero() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    doctor_out
    assert_status 0 "$DSTATUS" "$DOUT" || return
    assert_contains "$DOUT" "No isolation problems found"
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
    fixture_transcript "$HOME/.claude-bouvet"   "-Users-m-dev-shared" "/Users/m/dev/shared"
    fixture_transcript "$HOME/.claude-highsoft" "-Users-m-dev-shared" "/Users/m/dev/shared"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D03" || return
    assert_contains "$DOUT" "/Users/m/dev/shared" || return
    assert_contains "$DOUT" ".claude-bouvet" || return
    assert_contains "$DOUT" ".claude-highsoft"
}

case_d03_ignores_a_path_in_one_root_only() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-solo" "/Users/m/dev/solo"
    doctor_out
    assert_not_contains "$DOUT" "D03"
}

case_d03_is_not_fooled_by_encoding_collisions() {
    # my_repo, my-repo and my.repo all encode to the same directory name. The
    # rule must compare real cwd values, not directory names, or it would
    # report a leak that is not there.
    HOME=$(new_home); export HOME
    two_clean_profiles
    fixture_transcript "$HOME/.claude-bouvet"   "-Users-m-dev-my-repo" "/Users/m/dev/my_repo"
    fixture_transcript "$HOME/.claude-highsoft" "-Users-m-dev-my-repo" "/Users/m/dev/my.repo"
    doctor_out
    assert_not_contains "$DOUT" "D03"
}

case_d04_missing_registered_root() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    rm -rf "$HOME/.claude-bouvet"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D04"
}

case_d05_no_credential_and_no_account() {
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D05"
}

case_d05_quiet_when_signed_in_via_keychain() {
    # On macOS the credential lives in the Keychain, so a missing
    # .credentials.json is not proof. An account on record means signed in.
    HOME=$(new_home); export HOME
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    doctor_out
    assert_not_contains "$DOUT" "D05"
}

case_d06_unregistered_root() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    mkdir -p "$HOME/.claude-tide"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D06" || return
    assert_contains "$DOUT" ".claude-tide"
}

case_d07_wrong_mode() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    chmod 755 "$HOME/.claude-bouvet"
    doctor_out
    assert_status 2 "$DSTATUS" || return
    assert_contains "$DOUT" "D07" || return
    assert_contains "$DOUT" "mode 755"
}

case_d08_project_dir_that_is_not_a_path() {
    HOME=$(new_home); export HOME
    two_clean_profiles
    fixture_transcript "$HOME/.claude-bouvet" "work" "/Users/m/dev/renamed"
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

run_case "a clean machine exits 0"                    case_clean_exits_zero
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
run_case "D08 a project dir that is not a path"       case_d08_project_dir_that_is_not_a_path
run_case "no profiles is not a finding"               case_doctor_with_no_profiles_is_not_a_finding
