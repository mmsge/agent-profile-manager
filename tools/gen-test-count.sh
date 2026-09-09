#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# gen-test-count.sh: generate the test count in README.md's Development
# section instead of hand-typing it.
#
# The count used to be a number a contributor typed by hand every time a
# branch added or removed a test. Every branch that touched it edited the
# same line, so two such branches from one base always collided there, each
# guessing a different number, and the number that was actually correct once
# both landed existed on neither branch (issue #41). This script computes the
# number the same way tests/run.sh's own summary line does, so nobody
# computes it by hand, or guesses it, again.
#
# Usage:
#   tools/gen-test-count.sh                # run the suite, rewrite README.md
#   tools/gen-test-count.sh --check         # run the suite, fail if stale
#   tools/gen-test-count.sh --from FILE     # read the suite's output from
#                                           # FILE instead of running it again
#                                           # (combine with --check or not)
#
# Run the plain form after adding or removing tests, and commit the result.
# CI runs the --check form; it fails naming both numbers when they disagree,
# which is the property issue #26 added and this script must not weaken.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
README="$ROOT/README.md"

MODE="write"
OUTPUT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            MODE=check
            ;;
        --from)
            shift
            OUTPUT_FILE="${1:-}"
            if [ -z "$OUTPUT_FILE" ]; then
                printf '%s: --from needs a file\n' "$(basename "$0")" >&2
                exit 2
            fi
            ;;
        -h|--help)
            printf 'usage: %s [--check] [--from FILE]\n' "$(basename "$0")"
            exit 0
            ;;
        *)
            printf 'usage: %s [--check] [--from FILE]\n' "$(basename "$0")" >&2
            exit 2
            ;;
    esac
    shift
done

_tmp_output=""
_tmp_readme=""
cleanup() {
    [ -n "$_tmp_output" ] && rm -f "$_tmp_output"
    [ -n "$_tmp_readme" ] && rm -f "$_tmp_readme"
}
trap cleanup EXIT INT TERM

if [ -n "$OUTPUT_FILE" ]; then
    if [ ! -f "$OUTPUT_FILE" ]; then
        printf '%s: %s not found\n' "$(basename "$0")" "$OUTPUT_FILE" >&2
        exit 2
    fi
else
    _tmp_output=$(mktemp "${TMPDIR:-/tmp}/gen-test-count.XXXXXX")
    OUTPUT_FILE="$_tmp_output"
    if ! "$ROOT/tests/run.sh" >"$OUTPUT_FILE" 2>&1; then
        cat "$OUTPUT_FILE" >&2
        printf '%s: the suite failed; fix it before touching the README count\n' "$(basename "$0")" >&2
        exit 1
    fi
fi

# sed, not grep: sed exits 0 whether or not a line matches, so a missing or
# reworded summary line falls through to the explicit checks below instead of
# failing this script with no explanation.
reported=$(sed -n 's/^\([0-9][0-9]*\) test(s), .*/\1/p' "$OUTPUT_FILE" | tail -1)
if [ -z "$reported" ]; then
    printf "%s: could not find the 'N test(s), N failure(s)' summary line in %s\n" \
        "$(basename "$0")" "$OUTPUT_FILE" >&2
    exit 1
fi

documented=$(sed -n 's/^tests\/run\.sh[[:space:]][[:space:]]*# \([0-9][0-9]*\) tests.*/\1/p' "$README" | tail -1)

if [ "$MODE" = check ]; then
    if [ -z "$documented" ]; then
        printf "%s: could not find the test count line in README.md's Development section\n" \
            "$(basename "$0")" >&2
        exit 1
    fi
    if [ "$reported" != "$documented" ]; then
        printf '%s: tests/run.sh reports %s tests but README.md says %s tests; run tools/gen-test-count.sh and commit README.md\n' \
            "$(basename "$0")" "$reported" "$documented" >&2
        exit 1
    fi
    printf '%s: README.md agrees with the suite: %s tests\n' "$(basename "$0")" "$reported"
    exit 0
fi

if [ "$reported" = "$documented" ]; then
    printf '%s: README.md already says %s tests, nothing to do\n' "$(basename "$0")" "$reported"
    exit 0
fi

_tmp_readme=$(mktemp "${TMPDIR:-/tmp}/gen-test-count-readme.XXXXXX")
sed "s/^\(tests\/run\.sh[[:space:]]*# \)[0-9][0-9]*\( tests, no dependencies\)\$/\\1$reported\\2/" \
    "$README" > "$_tmp_readme"
mv "$_tmp_readme" "$README"
_tmp_readme=""
printf '%s: README.md updated: %s -> %s tests\n' "$(basename "$0")" "${documented:-none}" "$reported"
