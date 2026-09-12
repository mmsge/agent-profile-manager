# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# The generated documentation. README.md's "What doctor reads" table is the
# document a security review reads first, and it used to be written by hand.
# These cases are what stops it going quiet: the first one fails when the
# checked-in table and a regenerated one differ, and the rest pin the failures
# that must name a rule rather than dropping a row.

GEN_READS="tools/gen-doctor-reads.sh"

# docs_fixture: a throwaway copy of the parts of the checkout the generator
# reads, echoed. The generator finds its root from its own path, so a copy is
# a small complete repository it can be pointed at, mangled and rewritten
# without touching this one.
docs_fixture() {
    _df=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-docs.XXXXXX")
    mkdir -p "$_df/bin" "$_df/tools"
    cp "$ROOT/bin/agent-profile" "$_df/bin/agent-profile"
    cp "$ROOT/$GEN_READS" "$_df/$GEN_READS"
    cp "$ROOT/README.md" "$_df/README.md"
    printf '%s\n' "$_df"
}

# gen_reads <dir> [args...]: run the generator in a fixture, stashing output
# and status. Run under the interpreter the suite is running under, the way
# the agent-profile shim does, so the bash 3.2 leg really tests bash 3.2.
gen_reads() {
    _gr_dir="$1"; shift
    GROUT=$("${BASH:-/bin/bash}" "$_gr_dir/$GEN_READS" ${1+"$@"} 2>&1)
    GRSTATUS=$?
}

# docs_edit <file> <sed-expression>: an edit in place without sed -i, whose
# spelling differs between BSD and GNU sed.
docs_edit() {
    sed "$2" "$1" > "$1.edited" && mv "$1.edited" "$1"
}

# docs_drop_declaration <file> <rule> <keep-header|drop-header>: remove a
# declaration's body, and its header too unless asked to keep it.
docs_drop_declaration() {
    awk -v rule="$2" -v keep="$3" '
        index($0, "# doctor reads (" rule) > 0 {
            skipping = 1
            if (keep == "keep-header") print
            next
        }
        skipping == 1 && $0 ~ /^[[:space:]]*#[[:space:]][[:space:]]+[^[:space:]]/ { next }
        { skipping = 0; print }
    ' "$1" > "$1.edited" && mv "$1.edited" "$1"
}

# docs_table_rules <readme>: the rule ids in the generated table, in order.
docs_table_rules() {
    awk '
        index($0, "<!-- BEGIN GENERATED: what doctor reads") == 1 { inblock = 1; next }
        index($0, "<!-- END GENERATED: what doctor reads") == 1 { inblock = 0 }
        inblock == 1
    ' "$1" | sed -n 's/^| \(D[0-9][0-9]*\).*/\1/p' | tr '\n' ' '
}

case_table_matches_the_source() {
    # The no-diff test itself: what is committed is what the generator makes
    # of bin/agent-profile right now.
    gen_reads "$ROOT" --check
    assert_status 0 "$GRSTATUS" "$GROUT" || return
    assert_contains "$GROUT" "16 rules"
}

case_a_hand_edited_row_fails_by_name() {
    _d=$(docs_fixture)
    docs_edit "$_d/README.md" 's/^| D07 | The file mode.*/| D07 | Nothing worth mentioning. |/'
    gen_reads "$_d" --check
    assert_status 1 "$GRSTATUS" "$GROUT" || return
    assert_contains "$GROUT" "row for D07" || return
    assert_contains "$GROUT" "Nothing worth mentioning" || return
    assert_contains "$GROUT" "The file mode of each registered root"
    rm -rf "$_d"
}

case_a_missing_declaration_fails_by_name() {
    # The rule stays in the code and in the catalogue; only the comment saying
    # what it reads is gone. That must name D07 rather than quietly dropping
    # its row.
    _d=$(docs_fixture)
    docs_drop_declaration "$_d/bin/agent-profile" "D07" "drop-header"
    gen_reads "$_d" --check
    assert_status 1 "$GRSTATUS" "$GROUT" || return
    assert_contains "$GROUT" "rule D07 has no" || return
    assert_contains "$GROUT" "doctor reads (D07)"
    rm -rf "$_d"
}

case_an_empty_declaration_fails_by_name() {
    _d=$(docs_fixture)
    docs_drop_declaration "$_d/bin/agent-profile" "D09" "keep-header"
    gen_reads "$_d" --check
    assert_status 1 "$GRSTATUS" "$GROUT" || return
    assert_contains "$GROUT" "declaration for D09"
    rm -rf "$_d"
}

case_an_unparseable_declaration_fails_by_name() {
    _d=$(docs_fixture)
    docs_edit "$_d/bin/agent-profile" 's/# doctor reads (D09):/# doctor reads for D09:/'
    gen_reads "$_d" --check
    assert_status 1 "$GRSTATUS" "$GROUT" || return
    assert_contains "$GROUT" "not in the expected shape" || return
    assert_contains "$GROUT" "doctor reads for D09"
    rm -rf "$_d"
}

case_a_rule_the_table_does_not_have_fails() {
    # A new rule in the catalogue, declared but never added to the README.
    # This is the one that stops a rule being added without saying what it
    # reads.
    _d=$(docs_fixture)
    awk -v t="$(printf '\t')" '
        index($0, "\"D16" t) > 0 {
            print $0 " \\"
            print "        \"D17" t "Something new nobody has written down\""
            next
        }
        index($0, "cmd_doctor() {") == 1 {
            print "# doctor reads (D17):"
            print "#   Something or other."
            print ""
        }
        { print }
    ' "$_d/bin/agent-profile" > "$_d/bin/edited" && mv "$_d/bin/edited" "$_d/bin/agent-profile"
    gen_reads "$_d" --check
    assert_status 1 "$GRSTATUS" "$GROUT" || return
    assert_contains "$GROUT" "no row for D17"
    rm -rf "$_d"
}

case_a_declaration_for_no_rule_fails() {
    # The residue a renamed or deleted rule leaves behind.
    _d=$(docs_fixture)
    awk '
        index($0, "cmd_doctor() {") == 1 {
            print "# doctor reads (D99):"
            print "#   A rule that is not in the catalogue."
            print ""
        }
        { print }
    ' "$_d/bin/agent-profile" > "$_d/bin/edited" && mv "$_d/bin/edited" "$_d/bin/agent-profile"
    gen_reads "$_d" --check
    assert_status 1 "$GRSTATUS" "$GROUT" || return
    assert_contains "$GROUT" "no rule D99"
    rm -rf "$_d"
}

case_check_writes_nothing() {
    _d=$(docs_fixture)
    docs_edit "$_d/README.md" 's/^| D15 | The registry only.*/| D15 | Everything. |/'
    cp "$_d/README.md" "$_d/README.before"
    gen_reads "$_d" --check
    assert_status 1 "$GRSTATUS" "$GROUT" || return
    cmp -s "$_d/README.before" "$_d/README.md" || fail "--check rewrote README.md"
    rm -rf "$_d"
}

case_writing_restores_the_table() {
    _d=$(docs_fixture)
    cp "$_d/README.md" "$_d/README.before"
    docs_edit "$_d/README.md" 's/^| D15 | The registry only.*/| D15 | Everything. |/'
    gen_reads "$_d"
    assert_status 0 "$GRSTATUS" "$GROUT" || return
    assert_contains "$GROUT" "updated" || return
    gen_reads "$_d" --check
    assert_status 0 "$GRSTATUS" "$GROUT" || return
    # Only the row inside the generated block comes back: the rest of the file
    # is left exactly as it was.
    cmp -s "$_d/README.before" "$_d/README.md" || fail "the rewrite changed more than the table"
    rm -rf "$_d"
}

case_the_table_lists_the_rules_doctor_reports() {
    # The generator reads doctor_rule_catalog() out of the source; this asks
    # the running program instead, so the table is tied to what doctor really
    # reports rather than to one parse of one function.
    HOME=$(new_home); export HOME
    docs_json=$("$AP" doctor --json 2>/dev/null)
    docs_reported=$(printf '%s\n' "$docs_json" | python3 -c '
import json, sys
print(" ".join(r["rule"] for r in json.load(sys.stdin)["rules"]) + " ")
')
    assert_equals "$docs_reported" "$(docs_table_rules "$ROOT/README.md")"
}

run_case "the table matches the source"                 case_table_matches_the_source
run_case "a hand-edited row fails by name"              case_a_hand_edited_row_fails_by_name
run_case "a missing declaration fails by name"          case_a_missing_declaration_fails_by_name
run_case "an empty declaration fails by name"           case_an_empty_declaration_fails_by_name
run_case "an unparseable declaration fails by name"     case_an_unparseable_declaration_fails_by_name
run_case "a rule the table does not have fails"         case_a_rule_the_table_does_not_have_fails
run_case "a declaration for no rule fails"              case_a_declaration_for_no_rule_fails
run_case "--check writes nothing"                       case_check_writes_nothing
run_case "writing restores the table"                   case_writing_restores_the_table
run_case "the table lists the rules doctor reports"     case_the_table_lists_the_rules_doctor_reports
