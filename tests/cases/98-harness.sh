# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# The harness's own case filter. tests/run.sh NAME... runs only the case
# files whose name contains a NAME, and refuses a NAME nothing matches. Each
# case here runs a second harness as a child process, under the same
# interpreter as this one, against a file small enough to finish in seconds.

case_run_sh_runs_one_case_file_by_name() {
    out=$("${BASH:-bash}" "$ROOT/tests/run.sh" 85-completion 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "  cases   85-completion" || return
    assert_contains "$out" "85-completion" || return
    # Nothing else was sourced: the first file of the suite is not in the output.
    assert_not_contains "$out" "10-profiles" || return
    assert_not_contains "$out" "0 test(s)"
}

case_run_sh_takes_a_pasted_path_too() {
    out=$("${BASH:-bash}" "$ROOT/tests/run.sh" tests/cases/85-completion.sh 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "85-completion"
}

case_run_sh_refuses_a_name_that_matches_nothing() {
    out=$("${BASH:-bash}" "$ROOT/tests/run.sh" no-such-case 2>&1); status=$?
    assert_status 2 "$status" "$out" || return
    assert_contains "$out" 'nothing under tests/cases/ matches "no-such-case"' || return
    # It refused before running anything, so there is no summary line.
    assert_not_contains "$out" "test(s)"
}

run_case "run.sh runs one case file by name"       case_run_sh_runs_one_case_file_by_name
run_case "run.sh takes a pasted path too"          case_run_sh_takes_a_pasted_path_too
run_case "run.sh refuses a name that matches nothing" case_run_sh_refuses_a_name_that_matches_nothing
