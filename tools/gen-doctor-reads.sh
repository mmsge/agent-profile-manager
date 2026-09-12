#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# gen-doctor-reads.sh: generate README.md's "What doctor reads" table from
# bin/agent-profile instead of maintaining it by hand.
#
# That table is what a consultant reads before running this tool on a machine
# holding a customer's data, and it was written by hand. A hand-written
# description of what code reads decays quietly: the rule grows a read, the
# table still says the old thing, and the reader has no way to know (issue
# #40). This script takes two different things from the source and fails
# rather than guessing when they disagree.
#
# The rules themselves come from the code. doctor_rule_catalog() is the list
# doctor --json reports, so the set of rows and their order are the program's
# own answer to "which rules are there", and a rule added to the catalogue
# without a declaration fails here by name rather than quietly missing a row.
#
# What each rule reads comes from a declaration beside the rule:
#
#     # doctor reads (D07):
#     #   The file mode of each registered root and its app data directory,
#     #   via `stat`. No file content.
#
# The header names the rule, and anything after the id inside the parentheses
# is carried into the table's first cell, which is how D12 says it runs only
# with --keychain-scan. The body is every following comment line indented by
# at least two spaces after the "#", joined into one cell; the first line that
# is not one ends the declaration, so ordinary prose under a bare "#" can
# follow without being swallowed. A declaration is a comment, and a comment
# can be left behind by a change to the code under it. This narrows the gap
# between the document and the code; it does not close it, and the README says
# so rather than claiming the table is derived from behaviour.
#
# Usage:
#   tools/gen-doctor-reads.sh           # rewrite the table in README.md
#   tools/gen-doctor-reads.sh --check   # fail if the table is stale, write
#                                       # nothing
#
# Run the plain form after changing what a rule reads, and commit the README
# change it makes. CI runs the --check form, which names the rule that differs
# rather than printing a whole-file diff.

set -u

SELF=$(basename "$0")
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT/bin/agent-profile"
README="$ROOT/README.md"

BEGIN_MARK='<!-- BEGIN GENERATED: what doctor reads (tools/gen-doctor-reads.sh) -->'
END_MARK='<!-- END GENERATED: what doctor reads -->'

TAB=$(printf '\t')

MODE="write"

while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check" ;;
        -h|--help)
            printf 'usage: %s [--check]\n' "$SELF"
            exit 0
            ;;
        *)
            printf 'usage: %s [--check]\n' "$SELF" >&2
            exit 2
            ;;
    esac
    shift
done

_tmp_decls=""
_tmp_rows=""
_tmp_block=""
_tmp_current=""
_tmp_readme=""
cleanup() {
    [ -n "$_tmp_decls" ] && rm -f "$_tmp_decls"
    [ -n "$_tmp_rows" ] && rm -f "$_tmp_rows"
    [ -n "$_tmp_block" ] && rm -f "$_tmp_block"
    [ -n "$_tmp_current" ] && rm -f "$_tmp_current"
    [ -n "$_tmp_readme" ] && rm -f "$_tmp_readme"
    return 0
}
trap cleanup EXIT INT TERM

die() {
    printf '%s: %s\n' "$SELF" "$1" >&2
    shift
    for _d in ${1+"$@"}; do printf '  %s\n' "$_d" >&2; done
    exit 1
}

[ -f "$SOURCE" ] || die "no such file: $SOURCE"
[ -f "$README" ] || die "no such file: $README"

# ---- the rules, from the code ---------------------------------------------
#
# doctor_rule_catalog() is the authority on which rules exist: it is what the
# --json document's rules array is built from, so a rule that can be reported
# is a rule that must have a row here.
RULES=$(sed -n '/^doctor_rule_catalog() {$/,/^}$/p' "$SOURCE" \
    | sed -n "s/^[[:space:]]*\"\\(D[0-9][0-9]*\\)[[:space:]].*/\\1/p")
if [ -z "$RULES" ]; then
    die "could not read doctor_rule_catalog() from $SOURCE" \
        "The table is built from that list, so this script will not guess one."
fi

# ---- the declarations, from the comments ----------------------------------
#
# One record per declaration: id, the first table cell, then the joined body.
# A header this script cannot parse is recorded as "!" so it is reported by
# name below rather than dropped.
_tmp_decls=$(mktemp "${TMPDIR:-/tmp}/gen-doctor-reads.XXXXXX") || \
    die "could not create a temporary file under ${TMPDIR:-/tmp}"

awk '
    function flush() {
        if (id != "") printf "%s\t%s\t%s\n", id, cell, text
        id = ""; cell = ""; text = ""; collecting = 0
    }
    /^[[:space:]]*#[[:space:]]*doctor reads/ {
        flush()
        if ($0 !~ /^[[:space:]]*#[[:space:]]doctor reads \(D[0-9][0-9]*[^()]*\):[[:space:]]*$/) {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            printf "!\t%s\t%s\n", NR, line
            next
        }
        p = index($0, "(")
        q = index($0, ")")
        cell = substr($0, p + 1, q - p - 1)
        id = cell
        sub(/[^A-Za-z0-9].*$/, "", id)
        collecting = 1
        next
    }
    collecting == 1 {
        if ($0 ~ /^[[:space:]]*#[[:space:]][[:space:]]+[^[:space:]]/) {
            t = $0
            sub(/^[[:space:]]*#[[:space:]]+/, "", t)
            text = (text == "" ? t : text " " t)
        } else {
            flush()
        }
        next
    }
    END { flush() }
' "$SOURCE" > "$_tmp_decls"

if grep -q "^!$TAB" "$_tmp_decls"; then
    # Printed here rather than through die(), so a second bad header lines up
    # under the first instead of hanging off the end of one argument.
    printf "%s: a 'doctor reads' declaration in bin/agent-profile is not in the expected shape\n" \
        "$SELF" >&2
    sed -n "s/^!$TAB\\([0-9]*\\)$TAB/  line \\1: /p" "$_tmp_decls" >&2
    printf '  Expected: # doctor reads (D07):  followed by lines indented two\n' >&2
    printf "  spaces past the '#'.\n" >&2
    exit 1
fi

# A declaration for a rule the catalogue does not have is as much a drift as a
# rule with no declaration, and it is the shape a renamed rule leaves behind.
while IFS="$TAB" read -r _id _cell _text; do
    [ -n "$_id" ] || continue
    _seen=""
    for _rule in $RULES; do
        [ "$_rule" = "$_id" ] && _seen=1
    done
    [ -n "$_seen" ] || die \
        "bin/agent-profile declares what $_id reads, but doctor_rule_catalog() has no rule $_id" \
        "Either the rule was renamed and the declaration was left behind, or the" \
        "catalogue is missing it."
done < "$_tmp_decls"

# ---- the table ------------------------------------------------------------
_tmp_rows=$(mktemp "${TMPDIR:-/tmp}/gen-doctor-reads-rows.XXXXXX") || \
    die "could not create a temporary file under ${TMPDIR:-/tmp}"
_tmp_block=$(mktemp "${TMPDIR:-/tmp}/gen-doctor-reads-block.XXXXXX") || \
    die "could not create a temporary file under ${TMPDIR:-/tmp}"

for _rule in $RULES; do
    _found=$(awk -F"$TAB" -v r="$_rule" '$1 == r { n++ } END { print n + 0 }' "$_tmp_decls")
    if [ "$_found" -eq 0 ]; then
        die "rule $_rule has no '# doctor reads ($_rule):' declaration in bin/agent-profile" \
            "Every rule in doctor_rule_catalog() needs one, so a new rule cannot be" \
            "added without saying what it reads."
    fi
    if [ "$_found" -gt 1 ]; then
        die "rule $_rule has $_found 'doctor reads' declarations in bin/agent-profile" \
            "One rule, one declaration: two of them would let the table be built from" \
            "whichever came first."
    fi
    _cell=$(awk -F"$TAB" -v r="$_rule" '$1 == r { print $2 }' "$_tmp_decls")
    _text=$(awk -F"$TAB" -v r="$_rule" '$1 == r { print $3 }' "$_tmp_decls")
    if [ -z "$_text" ]; then
        die "the declaration for $_rule in bin/agent-profile says nothing" \
            "A header needs at least one body line, indented two spaces past the '#'."
    fi
    case "$_text$_cell" in
        *"|"*) die "the declaration for $_rule contains a '|', which would break the table" \
            "Write it another way: a cell cannot carry a pipe." ;;
    esac
    printf '%s%s| %s | %s |\n' "$_rule" "$TAB" "$_cell" "$_text" >> "$_tmp_rows"
done

{
    printf '%s\n' "$BEGIN_MARK"
    printf '| Rule | Reads |\n'
    printf '| --- | --- |\n'
    cut -f2- "$_tmp_rows"
    printf '%s\n' "$END_MARK"
} > "$_tmp_block"

# ---- the README -----------------------------------------------------------
_begins=$(grep -c -F -x -- "$BEGIN_MARK" "$README")
_ends=$(grep -c -F -x -- "$END_MARK" "$README")
if [ "$_begins" -ne 1 ] || [ "$_ends" -ne 1 ]; then
    die "README.md does not hold exactly one generated block for this table" \
        "Expected these two lines around it, once each:" \
        "$BEGIN_MARK" \
        "$END_MARK"
fi

_tmp_current=$(mktemp "${TMPDIR:-/tmp}/gen-doctor-reads-current.XXXXXX") || \
    die "could not create a temporary file under ${TMPDIR:-/tmp}"
awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { inblock = 1 }
    inblock { print }
    $0 == e { inblock = 0 }
' "$README" > "$_tmp_current"

if cmp -s "$_tmp_block" "$_tmp_current"; then
    if [ "$MODE" = check ]; then
        printf '%s: README.md agrees with bin/agent-profile: %s rules\n' \
            "$SELF" "$(printf '%s\n' "$RULES" | grep -c .)"
    else
        printf '%s: README.md is already up to date, nothing to do\n' "$SELF"
    fi
    exit 0
fi

if [ "$MODE" = check ]; then
    # Name what differs. A whole-file diff would say the table changed; this
    # says which rule's row is lying, which is the thing to go and read.
    _reported=0
    while IFS="$TAB" read -r _rule _row; do
        _cur=$(awk -v r="$_rule" '
            index($0, "| " r " ") == 1 || index($0, "| " r ",") == 1 { print; exit }
        ' "$_tmp_current")
        if [ -z "$_cur" ]; then
            printf '%s: README.md has no row for %s\n' "$SELF" "$_rule" >&2
            printf '  expected: %s\n' "$_row" >&2
            _reported=$((_reported + 1))
        elif [ "$_cur" != "$_row" ]; then
            printf "%s: README.md's row for %s is not what bin/agent-profile declares\n" \
                "$SELF" "$_rule" >&2
            printf '  README.md:         %s\n' "$_cur" >&2
            printf '  bin/agent-profile: %s\n' "$_row" >&2
            _reported=$((_reported + 1))
        fi
    done < "$_tmp_rows"

    # A row for something the source has no rule for, which is what a deleted
    # or renamed rule leaves in the table.
    while IFS= read -r _line; do
        case "$_line" in
            '| Rule | Reads |'|'| --- | --- |') continue ;;
            '|'*) ;;
            *) continue ;;
        esac
        _id=$(printf '%s' "$_line" | sed -n 's/^| *\([A-Za-z0-9][A-Za-z0-9]*\).*/\1/p')
        [ -n "$_id" ] || continue
        if ! grep -q "^$_id$TAB" "$_tmp_rows"; then
            printf '%s: README.md has a row for %s, which is not a rule in bin/agent-profile\n' \
                "$SELF" "$_id" >&2
            _reported=$((_reported + 1))
        fi
    done < "$_tmp_current"

    if [ "$_reported" -eq 0 ]; then
        printf '%s: the generated block in README.md differs from a regenerated one\n' "$SELF" >&2
        printf '  Every row matches, so the difference is in the order of the rows or in\n' >&2
        printf '  the table header.\n' >&2
    fi
    printf '%s: run tools/gen-doctor-reads.sh and commit README.md\n' "$SELF" >&2
    exit 1
fi

_tmp_readme=$(mktemp "${TMPDIR:-/tmp}/gen-doctor-reads-readme.XXXXXX") || \
    die "could not create a temporary file under ${TMPDIR:-/tmp}"
awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v f="$_tmp_block" '
    $0 == b { while ((getline l < f) > 0) print l; close(f); skipping = 1; next }
    $0 == e { skipping = 0; next }
    skipping { next }
    { print }
' "$README" > "$_tmp_readme"

# Never leave a truncated README behind: a rewrite that lost the table would
# be worse than a stale one.
if ! grep -q -F -x -- "$END_MARK" "$_tmp_readme"; then
    die "the rewritten README.md lost its generated block, so nothing was written"
fi

cat "$_tmp_readme" > "$README"
rm -f "$_tmp_readme"
_tmp_readme=""
printf '%s: README.md updated: %s rules\n' "$SELF" "$(printf '%s\n' "$RULES" | grep -c .)"
