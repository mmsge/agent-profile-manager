# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# The generated examples. Every command example in README.md and the guides
# under docs/ that the tool or the installer can produce is written by
# tools/gen-doc-examples.sh from a real run, between markers, and these
# cases are what stops one going quiet: the first fails when a checked-in
# block and a regenerated one differ, and the rest pin the failures that
# must name the example rather than silently dropping or keeping a block.

GEN_EXAMPLES="tools/gen-doc-examples.sh"

# The files that may show the reader what the tool prints. A bare output
# fence in any of them is either generated or marked illustrative; the last
# case here checks that.
EXAMPLE_DOCS="README.md docs/SETUP.md docs/USE.md docs/INSTALL.md docs/DESKTOP.md docs/AUDIT.md docs/TROUBLESHOOTING.md docs/OFFBOARDING.md docs/LIMITS.md docs/CONTRIBUTING.md"

# examples_fixture: a small complete repository the generator can be pointed
# at, echoed. It holds the script and the installer, which the scenarios
# run, and one guide with one block, so a case runs one scenario rather
# than every one.
examples_fixture() {
    _ef=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-examples.XXXXXX")
    _ef=$(cd "$_ef" && pwd)
    mkdir -p "$_ef/bin" "$_ef/tools" "$_ef/docs"
    cp "$ROOT/bin/agent-profile" "$_ef/bin/agent-profile"
    cp "$ROOT/tools/install.sh" "$_ef/tools/install.sh"
    cp "$ROOT/$GEN_EXAMPLES" "$_ef/$GEN_EXAMPLES"
    printf '# A stand-in README with no generated block.\n' > "$_ef/README.md"
    {
        printf '# Use\n\n'
        printf '<!-- BEGIN GENERATED: example version (tools/gen-doc-examples.sh) -->\n'
        printf '<!-- END GENERATED: example version -->\n'
    } > "$_ef/docs/USE.md"
    printf '%s\n' "$_ef"
}

# gen_examples <dir> [args...]: run the generator in a fixture, stashing
# output and status, under the interpreter the suite is running under.
gen_examples() {
    _ge_dir="$1"; shift
    GEOUT=$("${BASH:-/bin/bash}" "$_ge_dir/$GEN_EXAMPLES" ${1+"$@"} 2>&1)
    GESTATUS=$?
}

# examples_edit <file> <sed-expression>: an edit in place without sed -i.
examples_edit() {
    sed "$2" "$1" > "$1.edited" && mv "$1.edited" "$1"
}

case_the_examples_match_the_tool() {
    # The no-diff test itself: what is committed is what the tool prints
    # right now, for every block in every guide.
    gen_examples "$ROOT" --check
    assert_status 0 "$GESTATUS" "$GEOUT" || return
    assert_contains "$GEOUT" "agrees with the tool"
}

case_writing_fills_an_empty_block() {
    _d=$(examples_fixture)
    gen_examples "$_d"
    assert_status 0 "$GESTATUS" "$GEOUT" || return
    assert_contains "$GEOUT" "updated 1 of 1" || return
    _v=$("$AP" version | awk '{print $2}')
    assert_contains "$(cat "$_d/docs/USE.md")" "agpin $_v" || return
    assert_contains "$(cat "$_d/docs/USE.md")" '```sh
agpin version
```' || return
    gen_examples "$_d" --check
    assert_status 0 "$GESTATUS" "$GEOUT"
    rm -rf "$_d"
}

case_a_hand_edited_block_fails_by_name() {
    _d=$(examples_fixture)
    gen_examples "$_d"
    examples_edit "$_d/docs/USE.md" 's/^GPL-3.0-or-later$/MIT/'
    gen_examples "$_d" --check
    assert_status 1 "$GESTATUS" "$GEOUT" || return
    assert_contains "$GEOUT" "docs/USE.md: the example 'version' is not what the tool prints" || return
    assert_contains "$GEOUT" "MIT" || return
    assert_contains "$GEOUT" "GPL-3.0-or-later" || return
    assert_contains "$GEOUT" "1 of 1 example(s) differ"
    rm -rf "$_d"
}

case_check_writes_nothing() {
    _d=$(examples_fixture)
    gen_examples "$_d"
    examples_edit "$_d/docs/USE.md" 's/^GPL-3.0-or-later$/MIT/'
    cp "$_d/docs/USE.md" "$_d/USE.before"
    gen_examples "$_d" --check
    assert_status 1 "$GESTATUS" "$GEOUT" || return
    cmp -s "$_d/USE.before" "$_d/docs/USE.md" || fail "--check rewrote docs/USE.md"
    rm -rf "$_d"
}

case_writing_restores_the_block() {
    _d=$(examples_fixture)
    gen_examples "$_d"
    cp "$_d/docs/USE.md" "$_d/USE.before"
    examples_edit "$_d/docs/USE.md" 's/^GPL-3.0-or-later$/MIT/'
    gen_examples "$_d"
    assert_status 0 "$GESTATUS" "$GEOUT" || return
    assert_contains "$GEOUT" "updated" || return
    # Only the block comes back: the rest of the file is left as it was.
    cmp -s "$_d/USE.before" "$_d/docs/USE.md" || fail "the rewrite changed more than the block"
    rm -rf "$_d"
}

case_a_block_nobody_can_generate_fails_by_name() {
    _d=$(examples_fixture)
    {
        printf '\n<!-- BEGIN GENERATED: example no-such-thing (tools/gen-doc-examples.sh) -->\n'
        printf '<!-- END GENERATED: example no-such-thing -->\n'
    } >> "$_d/docs/USE.md"
    gen_examples "$_d" --check
    assert_status 1 "$GESTATUS" "$GEOUT" || return
    assert_contains "$GEOUT" "no scenario named 'no-such-thing'"
    rm -rf "$_d"
}

case_a_mismatched_end_marker_fails() {
    _d=$(examples_fixture)
    examples_edit "$_d/docs/USE.md" 's/^<!-- END GENERATED: example version -->$/<!-- END GENERATED: example verison -->/'
    gen_examples "$_d" --check
    assert_status 1 "$GESTATUS" "$GEOUT" || return
    assert_contains "$GEOUT" "names verison but the block open is version"
    rm -rf "$_d"
}

case_the_examples_name_no_real_machine() {
    # The fixture HOME is replaced by /Users/alex before a block is written.
    # A temporary path, or this checkout's, in a guide means the
    # substitution missed something, and that reader would be told to look
    # in a directory that is not theirs.
    for _doc in $EXAMPLE_DOCS; do
        [ -f "$ROOT/$_doc" ] || continue
        _hits=$(grep -n -E '/(tmp|private|var/folders|home)/' "$ROOT/$_doc" | grep -v '^[0-9]*:.*<!--' || true)
        [ -z "$_hits" ] || fail "$_doc names a path that is not the example user's" "$_hits"
    done
}

case_every_output_fence_is_generated_or_marked_illustrative() {
    # A bare fence, one with no language, is how these documents show what
    # the tool printed. Outside a generated block it is a hand-typed example,
    # and a hand-typed example is allowed only when a comment right above it
    # says why it could not be generated.
    for _doc in $EXAMPLE_DOCS; do
        [ -f "$ROOT/$_doc" ] || continue
        _bad=$(awk '
            /^<!-- BEGIN GENERATED: / { generated = 1 }
            /^<!-- END GENERATED: / { generated = 0 }
            /^<!-- illustrative: / { marked = NR }
            /^```/ {
                if (inside) { inside = 0; next }
                inside = 1
                if ($0 == "```" && !generated && (NR - marked) > 3) print NR
                next
            }
        ' "$ROOT/$_doc")
        [ -z "$_bad" ] || fail "$_doc has an output fence that is neither generated nor marked illustrative" \
            "at line(s): $(printf '%s' "$_bad" | tr '\n' ' ')"
    done
}

run_case "the examples match the tool"                     case_the_examples_match_the_tool
run_case "writing fills an empty block"                    case_writing_fills_an_empty_block
run_case "a hand-edited block fails by name"               case_a_hand_edited_block_fails_by_name
run_case "--check writes nothing"                          case_check_writes_nothing
run_case "writing restores the block"                      case_writing_restores_the_block
run_case "a block nobody can generate fails by name"       case_a_block_nobody_can_generate_fails_by_name
run_case "a mismatched end marker fails"                   case_a_mismatched_end_marker_fails
run_case "the examples name no real machine"               case_the_examples_name_no_real_machine
run_case "every output fence is generated or illustrative" case_every_output_fence_is_generated_or_marked_illustrative
