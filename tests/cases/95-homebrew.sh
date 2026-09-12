# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# Pinning a release's sum in the Homebrew formula.
#
# Every case here runs against a release served from a local directory over a
# file:// URL, the same way the installer cases do, so the real download,
# extraction and verification path runs rather than a simulation of it. The
# formula each case rewrites is a copy of the real packaging/homebrew/agpin.rb,
# which is also what asserts that the real formula still has the shape the
# script expects: rename a field there and these fail.

UPDATER="$ROOT/tools/update-homebrew-formula.sh"

# A version no release of this project has, so nothing here can accidentally
# pass by agreeing with the checkout.
HB_VERSION="9.9.9"

# Which cosign the script should find. Defaulted to a name that cannot exist,
# so the unsigned cases answer the same on a machine that has cosign as on one
# that does not.
HB_COSIGN=""

hb_update() {
    AGENT_PROFILE_RELEASE_BASE_URL="file://$HOME/rel" \
    AGENT_PROFILE_COSIGN="${HB_COSIGN:-cosign-that-is-not-installed}" \
    "${BASH:-/bin/bash}" "$UPDATER" "$@"
}

# hb_fixture: a release to read, and a formula to rewrite.
hb_fixture() {
    HB_COSIGN=""
    fixture_release "$HOME/rel" "$HB_VERSION"
    cp "$ROOT/packaging/homebrew/agpin.rb" "$HOME/agpin.rb"
    cp "$HOME/agpin.rb" "$HOME/agpin.rb.before"
}

hb_sums() {
    printf '%s\n' "$HOME/rel/download/v$HB_VERSION/SHA256SUMS"
}

hb_tarball() {
    printf '%s\n' "$HOME/rel/download/v$HB_VERSION/agent-profile-$HB_VERSION.tar.gz"
}

# hb_published_sum: what the fixture release says its tarball hashes to.
hb_published_sum() {
    awk -v want="agent-profile-$HB_VERSION.tar.gz" '$2 == want { print $1 }' "$(hb_sums)"
}

# hb_field <name>: what the rewritten formula now says for one field.
hb_field() {
    sed -n "s/^  $1 \"\(.*\)\"\$/\1/p" "$HOME/agpin.rb" | head -1
}

# hb_untouched: the formula is byte for byte what it was before the run.
hb_untouched() {
    cmp -s "$HOME/agpin.rb" "$HOME/agpin.rb.before"
}

case_it_sets_url_version_and_sha256_together() {
    HOME=$(new_home); export HOME
    hb_fixture
    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "file://$HOME/rel/download/v$HB_VERSION/agent-profile-$HB_VERSION.tar.gz" \
        "$(hb_field url)" || return
    assert_equals "$HB_VERSION" "$(hb_field version)" || return
    assert_equals "$(hb_published_sum)" "$(hb_field sha256)"
}

case_the_sum_written_is_the_tarball_s_own() {
    # Not merely the number the release claims: the one the file hashes to
    # here. This is the check that a swapped SHA256SUMS cannot survive.
    HOME=$(new_home); export HOME
    hb_fixture
    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "$(shasum -a 256 "$(hb_tarball)" | awk '{print $1}')" "$(hb_field sha256)"
}

case_a_stale_formula_is_brought_fully_up_to_date() {
    # The failure worth preventing is a partial update: a new url beside an
    # old sum installs nothing at all. Start from a formula naming an older
    # release with a placeholder sum, and leave nothing of it behind.
    HOME=$(new_home); export HOME
    hb_fixture
    sed -e 's|/download/v[0-9.]*/agent-profile-[0-9.]*\.tar\.gz|/download/v0.1.0/agent-profile-0.1.0.tar.gz|' \
        -e 's/^  version ".*"$/  version "0.1.0"/' \
        -e 's/^  sha256 ".*"$/  sha256 "0000000000000000000000000000000000000000000000000000000000000000"/' \
        "$HOME/agpin.rb.before" > "$HOME/agpin.rb"

    out=$(hb_update "v$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$(hb_field url)" "agent-profile-$HB_VERSION.tar.gz" || return
    assert_equals "$HB_VERSION" "$(hb_field version)" || return
    assert_equals "$(hb_published_sum)" "$(hb_field sha256)" || return
    assert_not_contains "$(cat "$HOME/agpin.rb")" "0.1.0" || return
    assert_not_contains "$(cat "$HOME/agpin.rb")" "0000000000000000"
}

case_a_missing_row_fails_and_writes_nothing() {
    HOME=$(new_home); export HOME
    hb_fixture
    printf 'ec4ad4e3aef6e1a0a1cb0e5bf9f8c9a6f7d83b2b1f0e6a5c4d3b2a1908f7e6d5  something-else.tar.gz\n' \
        > "$(hb_sums)"

    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "no row for agent-profile-$HB_VERSION.tar.gz" || return
    assert_contains "$out" "Nothing was written" || return
    hb_untouched || fail "the formula was rewritten anyway"
}

case_a_sum_that_does_not_match_the_tarball_fails() {
    HOME=$(new_home); export HOME
    hb_fixture
    printf 'tampered\n' >> "$(hb_tarball)"

    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "does not match the sum published beside it" || return
    hb_untouched || fail "the formula was rewritten anyway"
}

case_a_partial_sum_fails_rather_than_being_written() {
    # Sixty-four zeros is the placeholder the formula carries on purpose; a
    # sum of the wrong length is a different thing, and it must not reach the
    # file at all.
    HOME=$(new_home); export HOME
    hb_fixture
    printf '%s  agent-profile-%s.tar.gz\n' "$(hb_published_sum | cut -c1-40)" "$HB_VERSION" \
        > "$(hb_sums)"

    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "not 64" || return
    hb_untouched || fail "the formula was rewritten anyway"
}

case_it_takes_the_row_for_the_tarball_and_not_a_neighbour() {
    # A release publishes the bundle beside the tarball, and version 9.9.90
    # would sort next to 9.9.9. Both start with the name being looked for, so
    # a substring match would pin the wrong file's sum.
    HOME=$(new_home); export HOME
    hb_fixture
    wanted=$(hb_published_sum)
    {
        printf '1111111111111111111111111111111111111111111111111111111111111111  agent-profile-%s.tar.gz.sigstore\n' "$HB_VERSION"
        printf '2222222222222222222222222222222222222222222222222222222222222222  agent-profile-%s0.tar.gz\n' "$HB_VERSION"
        printf '%s  agent-profile-%s.tar.gz\n' "$wanted" "$HB_VERSION"
    } > "$(hb_sums)"

    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "$wanted" "$(hb_field sha256)"
}

case_sum_only_prints_the_sum_and_writes_nothing() {
    HOME=$(new_home); export HOME
    hb_fixture
    out=$(hb_update "$HB_VERSION" --sum-only --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "$(hb_published_sum)" "$out" || return
    hb_untouched || fail "--sum-only rewrote the formula"
}

case_it_refuses_a_version_that_is_not_one() {
    HOME=$(new_home); export HOME
    hb_fixture
    out=$(hb_update "../../escaped" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "is not a version" || return
    hb_untouched || fail "the formula was rewritten anyway"
}

case_it_refuses_a_formula_it_does_not_recognise() {
    # A formula that lost its sha256 line, or grew a second one, is not
    # something to rewrite on a guess.
    HOME=$(new_home); export HOME
    hb_fixture
    grep -v '^  sha256 "' "$HOME/agpin.rb.before" > "$HOME/agpin.rb"
    cp "$HOME/agpin.rb" "$HOME/agpin.rb.before"

    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "not shaped the way this expects" || return
    hb_untouched || fail "the formula was rewritten anyway"
}

case_it_verifies_the_signature_when_cosign_is_there() {
    HOME=$(new_home); export HOME
    hb_fixture
    fake_cosign "$HOME/fakebin" 0
    HB_COSIGN="$HOME/fakebin/cosign"

    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "verified: built by the release workflow, from tag v$HB_VERSION" || return
    assert_equals "$(hb_published_sum)" "$(hb_field sha256)"
}

case_it_refuses_a_signature_that_does_not_verify() {
    HOME=$(new_home); export HOME
    hb_fixture
    fake_cosign "$HOME/fakebin" 1
    HB_COSIGN="$HOME/fakebin/cosign"

    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "did not verify" || return
    hb_untouched || fail "the formula was rewritten anyway"
}

case_it_says_when_the_signature_was_not_checked() {
    # The same position install.sh takes: a check that could not be made is
    # said out loud rather than passed over quietly.
    HOME=$(new_home); export HOME
    hb_fixture
    out=$(hb_update "$HB_VERSION" --formula "$HOME/agpin.rb" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "not checked: cosign is not installed"
}

run_case "formula: url, version and sum together" case_it_sets_url_version_and_sha256_together
run_case "formula: the sum is the tarball's own"  case_the_sum_written_is_the_tarball_s_own
run_case "formula: a stale formula is caught up"  case_a_stale_formula_is_brought_fully_up_to_date
run_case "formula: a missing row writes nothing"  case_a_missing_row_fails_and_writes_nothing
run_case "formula: a sum that does not match"     case_a_sum_that_does_not_match_the_tarball_fails
run_case "formula: a partial sum is refused"      case_a_partial_sum_fails_rather_than_being_written
run_case "formula: the row is matched exactly"    case_it_takes_the_row_for_the_tarball_and_not_a_neighbour
run_case "formula: --sum-only writes nothing"     case_sum_only_prints_the_sum_and_writes_nothing
run_case "formula: refuses a bogus version"       case_it_refuses_a_version_that_is_not_one
run_case "formula: refuses a shape it cannot read" case_it_refuses_a_formula_it_does_not_recognise
run_case "formula: checks the signature"          case_it_verifies_the_signature_when_cosign_is_there
run_case "formula: refuses a bad signature"       case_it_refuses_a_signature_that_does_not_verify
run_case "formula: says when it could not check"  case_it_says_when_the_signature_was_not_checked
