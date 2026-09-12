#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2016  # the patterns below are literals, not expressions
#
# lint-bash32.sh: refuse constructs that bash 3.2 does not support.
#
# macOS ships bash 3.2 as /bin/bash and that is the only bash the tool may
# assume. Several bash 4 constructs do not fail as syntax errors under 3.2:
# ${var^^} expands to nothing useful, `declare -A` creates an ordinary
# variable, and `mapfile` is simply not found at runtime. A script using them
# can pass `bash -n` and still be wrong, which is why this check exists
# alongside shellcheck rather than instead of it.

set -u


FILES="${*:-bin/agent-profile tools/probe-claude-desktop.sh tools/gen-test-count.sh tools/gen-doctor-reads.sh tests/run.sh}"
STATUS=0

check() {
    _pattern="$1"
    _label="$2"
    for _file in $FILES; do
        [ -f "$_file" ] || continue
        # Skip comment lines: this file's own explanations must not trip it.
        if grep -nE "$_pattern" "$_file" | grep -vE '^[0-9]+: *#' | grep -q .; then
            printf 'bash 3.2: %s in %s\n' "$_label" "$_file"
            grep -nE "$_pattern" "$_file" | grep -vE '^[0-9]+: *#' | sed 's/^/  /'
            STATUS=1
        fi
    done
}

check '\bmapfile\b'                    'mapfile (bash 4)'
check '\breadarray\b'                  'readarray (bash 4)'
check 'declare[[:space:]]+-A'          'associative array (bash 4)'
check 'local[[:space:]]+-A'            'associative array (bash 4)'
check '\$\{[A-Za-z_][A-Za-z0-9_]*\^'   'case conversion ${var^^} (bash 4)'
check '\$\{[A-Za-z_][A-Za-z0-9_]*,,'   'case conversion ${var,,} (bash 4)'
check '&>>'                            '&>> append redirect (bash 4)'
check '\bcoproc\b'                     'coproc (bash 4)'
check '\$\{[A-Za-z_][A-Za-z0-9_]*@[AaEKkLQPUu]\}' 'parameter transformation (bash 4.4)'

if [ "$STATUS" -eq 0 ]; then
    printf 'bash 3.2 clean.\n'
fi
exit "$STATUS"
