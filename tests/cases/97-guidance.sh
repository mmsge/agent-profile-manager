# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# shellcheck disable=SC2016  # the derivation matches literal '$SELF' in the source
#
# The guidance the tool prints, checked against what the tool does.
#
# The value of this tool is that it tells you what to do next. remove prints
# the commands that delete what it will not delete itself, doctor prints a fix
# under every rule it fires, and verify sends the reader to doctor. Somebody
# closing an engagement does what the output says and does not go and check
# that the tool was right.
#
# All of that is plain printf text, and nothing tied it to the behaviour it
# describes, so it drifted silently once already: #35 taught remove to say
# "doctor counts it as a D12 orphan" while #34, in parallel, put the D12
# Keychain scan behind --keychain-scan. Each branch was correct alone. Merged,
# the tool told a departing consultant to run a command that no longer checked
# anything, and git saw no conflict.
#
# So the check here cannot be "does this string appear", because the string is
# what drifted. It is "run what the tool said, and see whether the claim still
# holds".
#
# The claims are derived from bin/agent-profile rather than listed here, so a
# printed instruction is covered by being written rather than by being
# remembered. guidance_lines() is the derivation; everything below reads it.
# A new doctor rule whose fix line names a command or another rule is checked
# the moment it lands, without this file knowing it exists.
#
# Nothing here ever deletes a credential. The stand-in security(1) refuses a
# delete and refuses to read a secret, and records both, so the invariant the
# tool keeps is kept by its test suite as well.

# ---------------------------------------------------------------------------
# The derivation
# ---------------------------------------------------------------------------

# guidance_raw: every line of printed guidance in the three commands whose
# output is an instruction, tagged as a claim or as an orphan.
#
#   claim   <function>:<line>  <text>    text this file makes a check out of
#   orphan  <function>:<line>  <text>    text that reads as an instruction but
#                                        that the claim selector did not see
#
# The scope is remove, doctor and verify, which are the three commands whose
# output a reader acts on. A rule id in the first argument of finding(), or
# after rule_status, is the rule being declared rather than a rule the prose
# sends the reader to, so both are taken out before the text is read.
guidance_raw() {
    awk '
        /^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/ { fn = $0; sub(/\(\).*/, "", fn); next }
        /^\}/ { fn = ""; next }
        {
            if (fn != "cmd_remove" && fn != "remove_left" &&
                fn != "cmd_doctor" && fn != "cmd_verify") next
            text = $0
            sub(/^[ \t]+/, "", text)
            sub(/[ \t]+$/, "", text)
            if (substr(text, 1, 1) == "#") next

            # printf passes the tool name in through %s. Put it back, so the
            # invocation this line prints reads like every other one.
            if (text ~ /"\$SELF"/) gsub(/%s /, "$SELF ", text)

            gsub(/finding "D[0-9][0-9]"/, "finding", text)
            gsub(/rule_status D[0-9][0-9]/, "rule_status", text)

            probe = " " text " "

            # The word an instruction hands the reader to run, when there is
            # one. "Fix with: chmod 700 ..." names chmod; "Fix the registry by
            # hand" names nothing, and the stop list is how the two are told
            # apart without this file having to know every program there is.
            # It is what lets a fix line added on another branch be covered by
            # being written rather than by being remembered here.
            named = ""
            if (match(probe, /(with|run|instead|Try|Re-run|then): *[a-z][a-z0-9_-]*/)) {
                named = substr(probe, RSTART, RLENGTH)
                sub(/^.*: */, "", named)
                if (named ~ /^(the|a|an|it|this|that|these|those|your|them|one|no|not)$/)
                    named = ""
            }

            claim = (probe ~ /\$SELF /) || (probe ~ /D[0-9][0-9]/) ||
                    (probe ~ /F[0-9][0-9]/) || (probe ~ /rm -rf/) ||
                    (probe ~ /chmod /) || (probe ~ /security /) ||
                    (probe ~ /docs\//) || (probe ~ /tools\//) ||
                    (probe ~ /code --/) || (probe ~ /find "/) ||
                    (probe ~ /[^A-Za-z_]doctor[^A-Za-z_]/) ||
                    (probe ~ /[^A-Za-z_]verify[^A-Za-z_]/) ||
                    (named != "")

            # Deliberately generous, and only ever used to notice text the
            # claim selector missed. Missing a phrasing here weakens the
            # guard; it can never fail a line that is already covered.
            instruction = (probe ~ /with: /) || (probe ~ /[^A-Za-z_]Run /) ||
                          (probe ~ /[^A-Za-z_]run /) || (probe ~ /run: /) ||
                          (probe ~ /Try: /) || (probe ~ /Re-run:/) ||
                          (probe ~ /instead: /) || (probe ~ /usage: /) ||
                          (probe ~ /then: /)

            if (claim)            printf "claim\t%s:%d\t%s\n", fn, NR, text
            else if (instruction) printf "orphan\t%s:%d\t%s\n", fn, NR, text
        }
    ' "$ROOT/bin/agent-profile"
}

# guidance_lines: the claims, as "<where><TAB><text>".
guidance_lines() {
    guidance_raw | sed -n 's/^claim	//p'
}

# guidance_orphans: instruction-shaped text no claim was derived from.
guidance_orphans() {
    guidance_raw | sed -n 's/^orphan	//p'
}

# guidance_tab: one literal tab, for read's IFS.
guidance_tab() {
    printf '\t'
}

# doctor_flags_of <text>: the flags the text tells the reader to run doctor
# with, and nothing else on the line. Empty when it names doctor plainly.
#
# Bracketed forms are dropped first: "[--json] [--report FILE]" in a usage line
# lists what the command accepts, it does not ask for a run with all of them.
# The rest of the sentence is dropped at the first word that is not a flag, or
# "doctor --keychain-scan counts it as a D12 orphan" would carry four
# arguments called counts, it, as and a.
doctor_flags_of() {
    printf '%s\n' "$1" | awk '
        {
            gsub(/\[[^]]*\]/, "")
            out = ""
            n = split($0, w, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                t = w[i]
                sub(/^[^A-Za-z]+/, "", t)
                sub(/[^A-Za-z-].*$/, "", t)
                if (t != "doctor") continue
                for (j = i + 1; j <= n; j++) {
                    f = w[j]
                    sub(/[^a-z-].*$/, "", f)
                    if (f !~ /^--[a-z]/) break
                    out = (out == "" ? f : out " " f)
                }
                break
            }
            print out
        }
    ' | head -1
}

# guidance_doctor_flags <text>: the same, as "none" when there are none,
# because tab is IFS whitespace and read collapses an empty field into the one
# beside it, which is how a record like this silently loses a column.
guidance_doctor_flags() {
    _gdf=$(doctor_flags_of "$1")
    printf '%s\n' "${_gdf:-none}"
}

# guidance_self_commands: "<where><TAB><command><TAB><text>" for every
# invocation of this tool the guidance names.
guidance_self_commands() {
    guidance_lines | while IFS="$(guidance_tab)" read -r _gsc_where _gsc_text; do
        printf '%s\n' "$_gsc_text" \
            | grep -o '\$SELF [A-Za-z$_][A-Za-z0-9$_-]*' \
            | sed 's/^\$SELF //' \
            | while IFS= read -r _gsc_cmd; do
                printf '%s\t%s\t%s\n' "$_gsc_where" "$_gsc_cmd" "$_gsc_text"
            done
    done
}

# guidance_rule_refs: "<where><TAB><rule><TAB><flags><TAB><text>" for every
# rule id the guidance points a reader at, with the doctor invocation named
# alongside it. A rule named without an invocation is a rule a reader will go
# looking for under a plain doctor, so that is what it is checked against.
guidance_rule_refs() {
    guidance_lines | while IFS="$(guidance_tab)" read -r _grr_where _grr_text; do
        _grr_flags=$(guidance_doctor_flags "$_grr_text")
        printf '%s\n' "$_grr_text" | grep -o 'D[0-9][0-9]' | sort -u \
            | while IFS= read -r _grr_rule; do
                printf '%s\t%s\t%s\t%s\n' \
                    "$_grr_where" "$_grr_rule" "$_grr_flags" "$_grr_text"
            done
    done
}

# guidance_fact_refs: "<where><TAB><fact><TAB><text>".
guidance_fact_refs() {
    guidance_lines | while IFS="$(guidance_tab)" read -r _gfr_where _gfr_text; do
        printf '%s\n' "$_gfr_text" | grep -o 'F[0-9][0-9]' | sort -u \
            | while IFS= read -r _gfr_fact; do
                printf '%s\t%s\t%s\n' "$_gfr_where" "$_gfr_fact" "$_gfr_text"
            done
    done
}

# guidance_flag_pairs: "<where><TAB><command><TAB><flag><TAB><text>". The
# command is the one the line names; a line that names a flag but no command
# is talking about somebody else's flag, such as open's --env, and is skipped.
guidance_flag_pairs() {
    guidance_lines | while IFS="$(guidance_tab)" read -r _gfp_where _gfp_text; do
        _gfp_cmd=$(printf '%s\n' "$_gfp_text" \
            | grep -o '\$SELF [a-z][a-z-]*' | sed 's/^\$SELF //' | head -1)
        if [ -z "$_gfp_cmd" ]; then
            case " $_gfp_text " in
                *[!A-Za-z_]doctor[!A-Za-z_]*) _gfp_cmd=doctor ;;
            esac
        fi
        [ -n "$_gfp_cmd" ] || continue
        printf '%s\n' "$_gfp_text" | grep -o '\-\-[a-z][a-z-]*' | sort -u \
            | while IFS= read -r _gfp_flag; do
                printf '%s\t%s\t%s\t%s\n' \
                    "$_gfp_where" "$_gfp_cmd" "$_gfp_flag" "$_gfp_text"
            done
    done
}

# guidance_subcommands: every command main() dispatches, derived from the
# dispatch itself so a renamed command is noticed here rather than guessed at.
guidance_subcommands() {
    sed -n '/^main() {/,/^}/p' "$ROOT/bin/agent-profile" \
        | sed -n 's/^ *\([A-Za-z|-]*\))[ 	]*cmd_.*/\1/p' \
        | tr '|' '\n' \
        | sed '/^$/d'
}

# guidance_catalog_rules: every rule doctor_rule_catalog lists.
guidance_catalog_rules() {
    sed -n '/^doctor_rule_catalog() {/,/^}/p' "$ROOT/bin/agent-profile" \
        | sed -n 's/^ *"\(D[0-9][0-9]\).*/\1/p'
}

# guidance_trim <text>: an actual result, short enough to read in a failure.
guidance_trim() {
    printf '%s\n' "$1" | sed -n '1,14p' | sed 's/^/            | /'
}

# ---------------------------------------------------------------------------
# Running what the guidance printed
# ---------------------------------------------------------------------------

# printed_command_args <line>: the argv a printed line tells the reader to run
# this tool with. The line names the tool ("agent-profile doctor") or names the
# command on its own ("doctor --keychain-scan counts it as a D12 orphan"), and
# both mean the same thing to whoever reads it.
#
# Where the tool is named, the invocation runs to the quote that closes it or
# to the end of the line, so positional arguments survive. Where the command is
# named inside a sentence, only the flags printed beside it are part of it, or
# the sentence that follows would be read as arguments.
printed_command_args() {
    _pca=$(printf '%s\n' "$1" | sed 's/\[[^]]*\]//g')
    case "$_pca" in
        *"${AP##*/} "*)
            _pca=${_pca#*"${AP##*/} "}
            _pca=${_pca%%\"*}
            _pca=${_pca%%\'*}
            ;;
        *doctor*)
            _pca="doctor $(doctor_flags_of "$_pca")"
            ;;
        *) return 0 ;;
    esac
    printf '%s\n' "$_pca" | sed 's/[ .,;]*$//'
}

# printed_rm_target <line>: the path an "rm -rf '...'" line names.
printed_rm_target() {
    _prt=${1#*rm -rf }
    _prt=${_prt#\'}
    _prt=${_prt%\'}
    printf '%s\n' "$_prt"
}

# run_printed_rm <path>: delete what the report said is still there, after
# checking it really is inside the fixture. Nothing outside a throwaway HOME
# is ever in reach of this suite, and this is where that is enforced.
run_printed_rm() {
    case "$1" in
        "$HOME"/?*) ;;
        *) fail "refusing to run a printed rm outside the fixture" "target: $1"
           return 1 ;;
    esac
    rm -rf "$1"
}

# run_printed_chmod <command>: run a printed "chmod 700 '<path>'" verbatim,
# with the same guard.
run_printed_chmod() {
    _rpc=${1#chmod }
    _rpc_mode=${_rpc%% *}
    _rpc_path=${_rpc#* }
    _rpc_path=${_rpc_path#\'}
    _rpc_path=${_rpc_path%\'}
    case "$_rpc_path" in
        "$HOME"/?*) ;;
        *) fail "refusing to run a printed chmod outside the fixture" "target: $_rpc_path"
           return 1 ;;
    esac
    chmod "$_rpc_mode" "$_rpc_path"
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# guarded_keychain <bindir> <service>...: a stand-in security(1) that answers
# the two read-only questions the audit asks and refuses everything else.
#
# It is the harness's fake_keychain with teeth. A delete is recorded and
# refused, -g and -w are recorded and refused, and so is dump-keychain -d, so
# no case in this file can quietly start touching a credential and still pass.
guarded_keychain() {
    _gk_dir="$1"; shift
    mkdir -p "$_gk_dir"
    : > "$_gk_dir/known-services"
    for _gk_svc in ${1+"$@"}; do
        printf '%s\n' "$_gk_svc" >> "$_gk_dir/known-services"
    done
    printf '#!/bin/sh\nknown=%s\nrefused=%s\n' \
        "'$_gk_dir/known-services'" "'$HOME/security-refused'" > "$_gk_dir/security"
    cat >> "$_gk_dir/security" <<'SECEOF'
for arg in "$@"; do
    case "$arg" in
        -g|-w) printf '%s\n' "$*" >> "$refused"; exit 90 ;;
    esac
done
case "${1:-}" in
    find-generic-password)
        shift; svc=""
        while [ $# -gt 0 ]; do [ "$1" = "-s" ] && { shift; svc="$1"; }; shift; done
        grep -qxF "$svc" "$known" && exit 0 || exit 44 ;;
    dump-keychain)
        case " $* " in
            *" -d "*) printf '%s\n' "$*" >> "$refused"; exit 90 ;;
        esac
        sed 's/^/    "svce"<blob>="/; s/$/"/' "$known" ;;
    *)
        printf '%s\n' "$*" >> "$refused"
        printf 'stand-in security: refusing %s\n' "${1:-}" >&2
        exit 90 ;;
esac
SECEOF
    chmod +x "$_gk_dir/security"
}

# guidance_fixture: a machine on which every doctor rule has the chance to
# fire, so a claim about a rule is checked against a rule that really ran.
# Without osadecompile D13 and D14 report themselves as not run, and without a
# Keychain so do D11 and D12.
guidance_fixture() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/Claude.app"
    fake_osa "$HOME/fakebin"
    fake_open "$HOME/fakebin" env
    "$AP" new bouvet >/dev/null 2>&1
    fixture_account "$HOME/.claude-bouvet" "m@bouvet.no" "org-b"
    fixture_transcript "$HOME/.claude-bouvet" "-Users-m-dev-b" "/Users/m/dev/b"
    guarded_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-bouvet")"
}

# guidance_fixture_retiring: the same machine with a second profile, so that
# removing the first leaves a credential belonging to no root behind. This is
# the shape of an engagement ending.
guidance_fixture_retiring() {
    guidance_fixture
    "$AP" new tide >/dev/null 2>&1
    fixture_account "$HOME/.claude-tide" "m@tide.no" "org-t"
    guidance_applet "$HOME/Applications/Claude-Bouvet.app" "$HOME/.claude-bouvet" \
        "$HOME/Library/Application Support/Claude-Bouvet"
    printf 'applet=%s\n' "$HOME/Applications/Claude-Bouvet.app" \
        >> "$HOME/.config/agent-profiles/bouvet.conf"
    guarded_keychain "$HOME/fakebin" \
        "$(cred_service_for "$HOME/.claude-bouvet")" \
        "$(cred_service_for "$HOME/.claude-tide")"
}

# guidance_applet <applet> <root-it-pins> <app-data>: a launcher on disk whose
# launch line is the generated form, so a fixture starts from a machine the
# audit is happy with.
guidance_applet() {
    fixture_applet "$1" "$(fixture_launch_line "$HOME/Claude.app" "$2" "$3")"
}

# g_run: the tool, as if on macOS, against the fixture's stand-ins.
g_run() {
    PATH="$HOME/fakebin:$PATH" \
    AGENT_PROFILE_PLATFORM=Darwin \
    USER=tester \
    AGENT_PROFILE_APP_BUNDLE="$HOME/Claude.app" \
    AGENT_PROFILE_APPLET_DIRS="$HOME/Applications:$HOME/Desktop" \
        "$AP" "$@"
}

g_doctor() { g_run doctor "$@" 2>&1; }
g_verify() { g_run verify 2>&1; }
g_remove() { g_run remove "$@" 2>&1; }

# g_printed <argv...>: the tool, run with an argv the tool itself printed. The
# command name comes from the printed text, never from this file.
g_printed() { g_run "$@" 2>&1; }

# g_rule_status <rule> [doctor flags...]: what doctor's own document says
# became of one rule on this machine. "not_run" is the answer that matters:
# a rule that did not run cannot report anything, whatever the prose promised.
# A run that produced no document at all says nothing rather than raising, so
# the failure a broken tool causes is the assertion's and stays readable.
g_rule_status() {
    _grs_rule="$1"; shift
    g_run doctor --json "$@" 2>/dev/null | python3 -c '
import json, sys
try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for rule in doc["rules"]:
    if rule["rule"] == sys.argv[1]:
        print(rule["status"])
        break
' "$_grs_rule"
}

# assert_doctor_reports_what_verify_says <verify output> <doctor output>:
# every "doctor reports ... as Dnn" hint verify printed must name a rule that
# doctor really reported on this same machine.
assert_doctor_reports_what_verify_says() {
    _advs_vout="$1"
    _advs_dout="$2"
    _advs_seen=0
    printf '%s\n' "$_advs_vout" | grep 'doctor reports' > "$HOME/verify-hints" || true
    while IFS= read -r _advs_line; do
        _advs_rule=$(printf '%s\n' "$_advs_line" | grep -o 'D[0-9][0-9]' | head -1)
        [ -n "$_advs_rule" ] || continue
        _advs_seen=$((_advs_seen + 1))
        case "$_advs_dout" in
            *"$_advs_rule"*) ;;
            *) fail "verify sends the reader to a rule doctor does not report" \
                    "printed by: verify" \
                    "claim:      $(printf '%s' "$_advs_line" | sed 's/^ *//')" \
                    "ran:        ${AP##*/} doctor" \
                    "actual:" "$(guidance_trim "$_advs_dout")"
               return 1 ;;
        esac
    done < "$HOME/verify-hints"
    if [ "$_advs_seen" -eq 0 ]; then
        fail "verify printed no hint sending the reader to doctor" \
             "actual:" "$(guidance_trim "$_advs_vout")"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# The derivation itself
# ---------------------------------------------------------------------------

# Everything below reads guidance_lines(). If the derivation ever stops seeing
# the source, every one of those cases passes on an empty list and this file
# becomes decoration.
#
# This is the guard against that, and it is stated as shapes rather than as
# sentences: rewording a fix line must not fail here, while the printing moving
# out of these three commands, or guidance_raw ceasing to match, must.
case_the_guidance_is_still_where_this_file_looks_for_it() {
    HOME=$(new_home); export HOME
    guidance_expect() {
        _ge_what="$1"; _ge_least="$2"; shift 2
        _ge_got=$("$@" | grep -c '')
        [ "$_ge_got" -ge "$_ge_least" ] || \
            fail "the derivation found $_ge_got $_ge_what, expected at least $_ge_least" \
                 "Either the printing moved out of cmd_remove, cmd_doctor and" \
                 "cmd_verify, or guidance_raw stopped seeing it."
    }
    guidance_expect "guidance line(s)"    40 guidance_lines
    guidance_expect "named command(s)"     5 guidance_self_commands
    guidance_expect "named flag(s)"        3 guidance_flag_pairs
    guidance_expect "rule reference(s)"   10 guidance_rule_refs
    guidance_expect "fact reference(s)"   10 guidance_fact_refs

    # remove and verify each have to contribute, or a derivation that only
    # ever read cmd_doctor would look healthy.
    guidance_rule_refs > "$HOME/refs"
    grep -q '^cmd_remove:' "$HOME/refs" || \
        fail "no rule reference was derived from remove's closing report"
    grep -q '^cmd_verify:' "$HOME/refs" || \
        fail "no rule reference was derived from verify's hints"

    # The two external commands the tool tells a reader to run by hand.
    guidance_lines > "$HOME/claims"
    grep -q 'security delete-generic-password' "$HOME/claims" || \
        fail "no credential delete command was derived from remove"
    grep -q 'rm -rf' "$HOME/claims" || \
        fail "no delete command was derived from remove's closing report"
}

# A fix line that names a command nobody can run is worse than no fix line.
case_every_command_the_guidance_names_exists() {
    HOME=$(new_home); export HOME
    guidance_subcommands > "$HOME/subcommands"
    grep -q '^doctor$' "$HOME/subcommands" || \
        { fail "the dispatch table could not be read from main()"; return; }
    guidance_self_commands > "$HOME/named"
    [ -s "$HOME/named" ] || { fail "the guidance names no command at all"; return; }
    while IFS="$(guidance_tab)" read -r _where _cmd _text; do
        # A command chosen at run time, such as the IDE fix line's code or
        # idea. Which one it is depends on what is installed, so it is checked
        # where it is printed rather than where it is written.
        case "$_cmd" in *'$'*) continue ;; esac
        # Prose that happens to follow the tool's name rather than an
        # invocation of it. Add a word here only after checking it is prose.
        case "$_cmd" in rests) continue ;; esac
        grep -qx "$_cmd" "$HOME/subcommands" || \
            fail "the guidance names a command this tool does not have" \
                 "printed by: $_where" \
                 "claim:      $_text" \
                 "named:      ${AP##*/} $_cmd" \
                 "actual:     main() dispatches $(tr '\n' ' ' < "$HOME/subcommands")"
    done < "$HOME/named"
}

# Same again for the flags. A fix line carrying a flag the command rejects
# fails in the reader's terminal, not here, which is the wrong place.
case_every_flag_the_guidance_names_is_accepted() {
    HOME=$(new_home); export HOME
    guidance_flag_pairs > "$HOME/flags"
    [ -s "$HOME/flags" ] || { fail "the guidance names no flag at all"; return; }
    while IFS="$(guidance_tab)" read -r _where _cmd _flag _text; do
        _out=$("$AP" "$_cmd" "$_flag" 2>&1)
        case "$_out" in
            *"unknown option '$_flag'"*)
                fail "the guidance names a flag the command it names refuses" \
                     "printed by: $_where" \
                     "claim:      $_text" \
                     "ran:        ${AP##*/} $_cmd $_flag" \
                     "actual:" "$(guidance_trim "$_out")" ;;
        esac
    done < "$HOME/flags"
}

# Without this the case above would pass against a tool that accepted
# anything, which is exactly the way a check like it goes quiet.
case_an_invented_flag_is_still_refused() {
    HOME=$(new_home); export HOME
    for _cmd in doctor verify remove new app; do
        _out=$("$AP" "$_cmd" --not-a-real-flag 2>&1)
        assert_contains "$_out" "unknown option '--not-a-real-flag'" || return
    done
}

case_every_rule_the_guidance_names_is_in_the_catalog() {
    HOME=$(new_home); export HOME
    guidance_catalog_rules > "$HOME/catalog"
    grep -q '^D12$' "$HOME/catalog" || \
        { fail "the rule catalog could not be read"; return; }
    guidance_rule_refs > "$HOME/refs"
    [ -s "$HOME/refs" ] || { fail "the guidance names no rule at all"; return; }
    while IFS="$(guidance_tab)" read -r _where _rule _flags _text; do
        grep -qx "$_rule" "$HOME/catalog" || \
            fail "the guidance names a rule doctor does not have" \
                 "printed by: $_where" \
                 "claim:      $_text" \
                 "named:      $_rule" \
                 "actual:     the catalog holds $(tr '\n' ' ' < "$HOME/catalog")"
    done < "$HOME/refs"
}

# The one this file exists for.
#
# When the guidance says a rule will report something, the invocation printed
# beside it has to be one that runs that rule. #35 and #34 merged into a
# remove report that told a departing consultant to run "doctor", by then a
# command that no longer scanned the Keychain, while promising it would count
# the leftover credential as a D12 orphan. Both test suites passed.
#
# doctor's own document answers the question, because a rule that did not run
# is recorded as not_run rather than as a pass. So this runs the command the
# guidance named, on a machine where every rule has the chance to fire, and
# asks doctor what became of the rule the guidance promised.
case_every_rule_a_claim_names_runs_under_the_command_named_with_it() {
    guidance_fixture
    guidance_rule_refs > "$HOME/refs"
    [ -s "$HOME/refs" ] || { fail "the guidance names no rule at all"; return; }

    # One doctor run per distinct invocation, not per claim.
    : > "$HOME/rule-status"
    cut -f3 "$HOME/refs" | sort -u > "$HOME/flagsets"
    while IFS= read -r _flags; do
        _argv=""
        [ "$_flags" = "none" ] || _argv="$_flags"
        # shellcheck disable=SC2086  # the flags are an argv, and must split
        g_run doctor --json $_argv 2>/dev/null | python3 -c '
import json, sys
try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for rule in doc["rules"]:
    print("%s\t%s\t%s" % (sys.argv[1], rule["rule"], rule["status"]))
' "$_flags" >> "$HOME/rule-status"
    done < "$HOME/flagsets"

    while IFS="$(guidance_tab)" read -r _where _rule _flags _text; do
        _status=$(awk -F'\t' -v f="$_flags" -v r="$_rule" \
            '$1 == f && $2 == r { print $3 }' "$HOME/rule-status")
        _shown="$_flags"
        [ "$_shown" != "none" ] || _shown=""
        case "$_status" in
            ""|not_run)
                fail "the guidance names a rule the command beside it does not run" \
                     "printed by: $_where" \
                     "claim:      $_text" \
                     "ran:        ${AP##*/} doctor $_shown" \
                     "actual:     $_rule came back as ${_status:-absent from the document}" ;;
        esac
    done < "$HOME/refs"
}

# assert_rule_ran <status>: a rule that ran, whichever way it went.
assert_rule_ran() {
    case "$1" in
        not_run|"") fail "expected the rule to run, got: ${1:-no status at all}" ;;
    esac
}

# And the proof that the case above is not vacuous. If every rule ran under
# every invocation there would be nothing to catch, so pin the one gate that
# makes the question real: D12 is behind --keychain-scan, and a claim that
# named a plain doctor beside it would read not_run and fail.
case_a_rule_behind_a_flag_does_not_run_without_it() {
    guidance_fixture
    assert_equals "not_run" "$(g_rule_status D12)" || return
    assert_rule_ran "$(g_rule_status D12 --keychain-scan)"
}

case_every_fact_the_guidance_names_is_recorded() {
    HOME=$(new_home); export HOME
    guidance_fact_refs > "$HOME/facts"
    [ -s "$HOME/facts" ] || { fail "the guidance names no fact at all"; return; }
    while IFS="$(guidance_tab)" read -r _where _fact _text; do
        grep -q "^### $_fact " "$ROOT/docs/FACTS.md" || \
            fail "the guidance names a fact docs/FACTS.md does not record" \
                 "printed by: $_where" \
                 "claim:      $_text" \
                 "named:      $_fact" \
                 "actual:     no '### $_fact ' heading in docs/FACTS.md"
    done < "$HOME/facts"
}

# "Re-run: bash tools/probe-claude-desktop.sh" is a command a reader will
# paste, so the file has to be there and has to parse.
case_every_repository_file_the_guidance_names_exists() {
    HOME=$(new_home); export HOME
    guidance_lines | cut -f2- \
        | grep -o '\(tools\|docs\)/[A-Za-z0-9._-]*' | sort -u > "$HOME/files"
    [ -s "$HOME/files" ] || { fail "the guidance names no file in this repository"; return; }
    while IFS= read -r _file; do
        if [ ! -f "$ROOT/$_file" ]; then
            fail "the guidance names a file this repository does not have" \
                 "named:  $_file"
            continue
        fi
        case "$_file" in
            *.sh) bash -n "$ROOT/$_file" || \
                fail "the guidance names a script that does not parse" "named: $_file" ;;
        esac
    done < "$HOME/files"
}

# The guard against a new printed instruction in a shape the derivation does
# not see. It is the answer to "who covers the next fix line nobody
# remembered": if the text reads as an instruction and no claim came out of
# it, this fails and names the line.
case_no_printed_instruction_escapes_the_derived_list() {
    HOME=$(new_home); export HOME
    guidance_orphans > "$HOME/orphans"
    while IFS="$(guidance_tab)" read -r _where _text; do
        fail "the tool prints an instruction no claim was derived from" \
             "printed by: $_where" \
             "claim:      $_text" \
             "Teach guidance_raw to see it, or check it with a case of its own."
    done < "$HOME/orphans"
}

# Every external command the guidance prints, held to the invariant the tool
# keeps itself: it never reads a credential value, and the only thing it ever
# tells anyone to delete is a path it has just listed as still being there.
case_no_printed_command_reads_or_deletes_a_credential() {
    HOME=$(new_home); export HOME
    guidance_lines > "$HOME/claims"
    while IFS="$(guidance_tab)" read -r _where _text; do
        # A security(1) call, as opposed to prose about the command being
        # absent: every subcommand it has is a dashed word.
        _sec=$(printf '%s\n' "$_text" | grep -o 'security [a-z][a-z]*-[a-z-]*' | head -1)
        if [ -n "$_sec" ]; then
            case "$_sec" in
                "security delete-generic-password") ;;
                *) fail "the guidance names a security(1) call that is not the documented delete" \
                        "printed by: $_where" "claim:      $_text" ;;
            esac
            case "$_text" in
                *" -g"*|*" -w"*|*dump-keychain*)
                    fail "the guidance names a security(1) call that would read a secret" \
                         "printed by: $_where" "claim:      $_text" ;;
            esac
        fi
        case "$_text" in
            *"rm -rf"*)
                case "$_where" in
                    remove_left:*) ;;
                    *) fail "a delete is printed outside the closing report that names the path" \
                            "printed by: $_where" "claim:      $_text" ;;
                esac
                ;;
        esac
        case "$_text" in
            *"find \""*)
                case "$_text" in
                    *-delete*|*-exec*)
                        fail "the guidance names a find that would change the machine" \
                             "printed by: $_where" "claim:      $_text" ;;
                esac
                ;;
        esac
    done < "$HOME/claims"
}

# ---------------------------------------------------------------------------
# remove: the closing report, run rather than read
# ---------------------------------------------------------------------------

# The regression, end to end and from the real output rather than the source.
# Whatever invocation the credential line names is the one that gets run, and
# it has to report the orphan the line says it will.
case_removes_credential_line_names_a_doctor_that_reports_the_orphan() {
    guidance_fixture_retiring
    _out=$(g_remove bouvet)
    _line=$(printf '%s\n' "$_out" | grep 'D12' | head -1)
    if [ -z "$_line" ]; then
        fail "remove printed nothing about D12 in its closing report" \
             "actual:" "$(guidance_trim "$_out")"
        return
    fi
    _args=$(printed_command_args "$_line")
    if [ -z "$_args" ]; then
        fail "remove's credential line promises a rule but names no command to run" \
             "printed by: remove bouvet" "claim:      $(printf '%s' "$_line" | sed 's/^ *//')"
        return
    fi
    # shellcheck disable=SC2086  # the printed argv, run as printed
    _dout=$(g_printed $_args)
    case "$_dout" in
        *"belong to no known root"*) ;;
        *) fail "the command remove's credential line names does not report the orphan" \
                "printed by: remove bouvet" \
                "claim:      $(printf '%s' "$_line" | sed 's/^ *//')" \
                "ran:        ${AP##*/} $_args" \
                "actual:" "$(guidance_trim "$_dout")"
           return ;;
    esac
    assert_contains "$_dout" "1 Keychain credential entr(ies) belong to no known root"
}

# And the same fixture, without the flag the line names, to show the flag is
# doing the work. This is the merge of #34 and #35 reproduced: drop
# --keychain-scan from that line and the reader is told to run a command that
# reports nothing.
case_removes_credential_line_would_be_wrong_without_the_flag() {
    guidance_fixture_retiring
    g_remove bouvet >/dev/null
    assert_not_contains "$(g_doctor)" "belong to no known root"
}

# The closing "Then run:" line, and the rules it promises go quiet.
case_removes_closing_line_names_a_doctor_that_reports_d06_and_d14() {
    guidance_fixture_retiring
    _out=$(g_remove bouvet)
    _line=$(printf '%s\n' "$_out" | grep 'Then run:' | head -1)
    if [ -z "$_line" ]; then
        fail "remove printed no closing instruction" "actual:" "$(guidance_trim "$_out")"
        return
    fi
    _args=$(printed_command_args "$_line")
    # The rules the closing paragraph promises go quiet, taken from the
    # paragraph rather than from this file.
    _promised=$(printf '%s\n' "${_out#*Then run:}" | grep -o 'D[0-9][0-9]' | sort -u)
    [ -n "$_promised" ] || { fail "remove's closing report promises no rule"; return; }
    # shellcheck disable=SC2086
    _dout=$(g_printed $_args)
    for _rule in $_promised; do
        case "$_dout" in
            *"$_rule"*) ;;
            *) fail "remove promises a rule the command it names does not report" \
                    "printed by: remove bouvet" \
                    "claim:      $(printf '%s' "$_line" | sed 's/^ *//')" \
                    "ran:        ${AP##*/} $_args" \
                    "actual:     $_rule is absent from" "$(guidance_trim "$_dout")"
               return ;;
        esac
    done
}

# "Left on this machine" has to be true when it is printed, and the deletes it
# prints have to be the ones that make the rules it names go quiet.
case_the_paths_remove_prints_are_there_and_deleting_them_quiets_doctor() {
    guidance_fixture_retiring
    _out=$(g_remove bouvet)
    printf '%s\n' "$_out" | grep 'rm -rf' > "$HOME/deletes"
    _n=$(grep -c '' < "$HOME/deletes")
    if [ "$_n" -lt 3 ]; then
        fail "remove listed $_n path(s) as left behind, expected the root, app data and launcher" \
             "actual:" "$(guidance_trim "$_out")"
        return
    fi
    while IFS= read -r _line; do
        _target=$(printed_rm_target "$_line")
        if [ ! -e "$_target" ]; then
            fail "remove says a path is still on this machine and it is not" \
                 "printed by: remove bouvet" \
                 "claim:      $(printf '%s' "$_line" | sed 's/^ *//')" \
                 "actual:     $_target does not exist"
            return
        fi
        run_printed_rm "$_target" || return
    done < "$HOME/deletes"

    _args=$(printed_command_args "$(printf '%s\n' "$_out" | grep 'Then run:' | head -1)")
    # shellcheck disable=SC2086
    _dout=$(g_printed $_args)
    for _rule in D06 D14; do
        case "$_dout" in
            *"$_rule"*)
                fail "remove says a rule goes quiet once the printed deletes are run" \
                     "printed by: remove bouvet" \
                     "claim:      both go quiet once those paths are gone" \
                     "ran:        ${AP##*/} $_args" \
                     "actual:     $_rule is still reported in" "$(guidance_trim "$_dout")"
                return ;;
        esac
    done
}

# The credential command, handed to the stand-in rather than to a Keychain.
# Nothing here deletes anything: the stand-in records the call and refuses it,
# which is both how the shape is checked and how the invariant is kept.
case_removes_credential_command_is_a_delete_the_stand_in_refuses() {
    guidance_fixture_retiring
    _out=$(g_remove bouvet)
    if [ -f "$HOME/security-refused" ]; then
        fail "remove called security itself" "$(cat "$HOME/security-refused")"
        return
    fi
    _line=$(printf '%s\n' "$_out" | sed -n 's/^ *\(security .*\)$/\1/p' | head -1)
    case "$_line" in
        "security delete-generic-password "*) ;;
        *) fail "remove printed no credential delete command" \
                "actual:" "$(guidance_trim "$_out")"
           return ;;
    esac
    # The printed line, run verbatim, in a subshell that can reach nothing but
    # the stand-in. Run it as printed, or this checks a rewriting of it.
    # shellcheck disable=SC2123  # a subshell PATH, so only the stand-in answers
    ( PATH="$HOME/fakebin"; eval "$_line" ) >/dev/null 2>&1
    _status=$?
    assert_status 90 "$_status" "the stand-in security did not refuse the printed delete" || return
    _recorded=$(cat "$HOME/security-refused" 2>/dev/null)
    assert_contains "$_recorded" "delete-generic-password" || return
    assert_contains "$_recorded" "-s $(cred_service_for "$HOME/.claude-bouvet")" || return
    assert_contains "$_recorded" "-a tester" || return
    assert_not_contains "$_recorded" " -g" || return
    assert_not_contains "$_recorded" " -w"
}

# ---------------------------------------------------------------------------
# doctor: every fix line, run as printed
# ---------------------------------------------------------------------------

case_doctors_d07_fix_line_run_as_printed_quiets_d07() {
    guidance_fixture
    chmod 755 "$HOME/.claude-bouvet"
    _out=$(g_doctor)
    _line=$(printf '%s\n' "$_out" | sed -n 's/^ *Fix with: \(chmod .*\)$/\1/p' | head -1)
    if [ -z "$_line" ]; then
        fail "D07 fired and printed no chmod to fix it" "actual:" "$(guidance_trim "$_out")"
        return
    fi
    run_printed_chmod "$_line" || return
    _after=$(g_doctor)
    case "$_after" in
        *D07*) fail "the fix D07 prints does not quiet D07" \
                    "printed by: doctor (D07)" \
                    "claim:      Fix with: $_line" \
                    "ran:        $_line" \
                    "actual:" "$(guidance_trim "$_after")" ;;
    esac
}

case_doctors_d13_fix_line_run_as_printed_quiets_d13() {
    guidance_fixture
    mkdir -p "$HOME/.claude-elsewhere"
    guidance_applet "$HOME/Applications/Claude-Bouvet.app" "$HOME/.claude-elsewhere" \
        "$HOME/Library/Application Support/Claude-Bouvet"
    printf 'applet=%s\n' "$HOME/Applications/Claude-Bouvet.app" \
        >> "$HOME/.config/agent-profiles/bouvet.conf"
    _out=$(g_doctor)
    assert_contains "$_out" "D13" || return
    _line=$(printf '%s\n' "$_out" | grep 'Fix with:' | grep "${AP##*/} app" | head -1)
    _args=$(printed_command_args "$_line")
    if [ -z "$_args" ]; then
        fail "D13 fired and printed no command to fix it" "actual:" "$(guidance_trim "$_out")"
        return
    fi
    # shellcheck disable=SC2086
    g_printed $_args >/dev/null 2>&1
    _after=$(g_doctor)
    case "$_after" in
        *D13*) fail "the fix D13 prints does not quiet D13" \
                    "printed by: doctor (D13)" \
                    "claim:      $(printf '%s' "$_line" | sed 's/^ *//')" \
                    "ran:        ${AP##*/} $_args" \
                    "actual:" "$(guidance_trim "$_after")" ;;
    esac
}

case_doctors_d14_fix_line_run_as_printed_quiets_d14() {
    guidance_fixture
    guidance_applet "$HOME/Desktop/Bouvet.app" "$HOME/.claude-bouvet" \
        "$HOME/Library/Application Support/Claude-Bouvet"
    _out=$(g_doctor)
    assert_contains "$_out" "D14" || return
    _line=$(printf '%s\n' "$_out" | grep 'Fix with:' | grep -- '--applet' | head -1)
    _args=$(printed_command_args "$_line")
    if [ -z "$_args" ]; then
        fail "D14 fired and printed no command to fix it" "actual:" "$(guidance_trim "$_out")"
        return
    fi
    # The applet path is quoted in the fix line and printed_command_args stops
    # at the flag, so hand the flag its value the way the line spells it.
    _applet=$(printf '%s\n' "$_line" | sed -n "s/.*--applet '\(.*\)'.*/\1/p")
    if [ -z "$_applet" ]; then
        fail "D14's fix line names --applet without a path" "claim: $_line"
        return
    fi
    # shellcheck disable=SC2086
    g_printed $_args "$_applet" >/dev/null 2>&1
    _after=$(g_doctor)
    case "$_after" in
        *D14*) fail "the fix D14 prints does not quiet D14" \
                    "printed by: doctor (D14)" \
                    "claim:      $(printf '%s' "$_line" | sed 's/^ *//')" \
                    "ran:        ${AP##*/} $_args '$_applet'" \
                    "actual:" "$(guidance_trim "$_after")" ;;
    esac
}

case_doctors_d15_fix_line_names_the_registry_that_holds_the_entries() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/.claude-shared" "$HOME/.config/agent-profiles"
    chmod 700 "$HOME/.claude-shared"
    for _name in aa bb; do
        printf 'agent=claude\nroot=%s/.claude-shared\napp_data=%s/data-%s\ncreated=2026-09-12\n' \
            "$HOME" "$HOME" "$_name" > "$HOME/.config/agent-profiles/$_name.conf"
    done
    _out=$("$AP" doctor 2>&1)
    assert_contains "$_out" "D15" || return
    _line=$(printf '%s\n' "$_out" | grep 'Remove the registry entries' | head -1)
    _dir=${_line##* from }
    _dir=${_dir%.}
    if [ ! -d "$_dir" ]; then
        fail "D15 names a registry directory that is not there" \
             "printed by: doctor (D15)" \
             "claim:      $(printf '%s' "$_line" | sed 's/^ *//')" \
             "actual:     $_dir is not a directory"
        return
    fi
    if [ ! -f "$_dir/aa.conf" ]; then
        fail "D15 sends the reader to a directory that does not hold the entries" \
             "printed by: doctor (D15)" \
             "claim:      $(printf '%s' "$_line" | sed 's/^ *//')" \
             "actual:     no aa.conf under $_dir"
        return
    fi
    rm -f "$_dir/aa.conf"
    assert_not_contains "$("$AP" doctor 2>&1)" "D15"
}

# The line doctor prints when D12 did not run is itself an instruction, and it
# is the one that has to survive the flag moving. Run what it says.
case_doctors_d12_skip_note_names_a_doctor_that_reports_d12() {
    guidance_fixture
    guarded_keychain "$HOME/fakebin" \
        "$(cred_service_for "$HOME/.claude-bouvet")" \
        "Claude Code-credentials-deadbeef"
    _out=$(g_doctor)
    _line=$(printf '%s\n' "$_out" | grep 'were not checked' | head -1)
    if [ -z "$_line" ]; then
        fail "doctor did not say D12 was skipped" "actual:" "$(guidance_trim "$_out")"
        return
    fi
    _args=$(printed_command_args "$_line")
    # shellcheck disable=SC2086
    _after=$(g_printed $_args)
    case "$_after" in
        *"belong to no known root"*) ;;
        *) fail "the command doctor names for the skipped scan does not run it" \
                "printed by: doctor" \
                "claim:      $(printf '%s' "$_line" | sed 's/^ *//')" \
                "ran:        ${AP##*/} $_args" \
                "actual:" "$(guidance_trim "$_after")" ;;
    esac
}

# ---------------------------------------------------------------------------
# verify: the hints that send the reader to doctor
# ---------------------------------------------------------------------------

case_verifys_missing_root_hint_sends_you_to_a_rule_doctor_reports() {
    guidance_fixture
    rm -rf "$HOME/.claude-bouvet"
    assert_doctor_reports_what_verify_says "$(g_verify)" "$(g_doctor)"
}

case_verifys_project_dir_note_sends_you_to_a_rule_doctor_reports() {
    guidance_fixture
    fixture_transcript "$HOME/.claude-bouvet" "work" "/Users/m/dev/renamed"
    assert_doctor_reports_what_verify_says "$(g_verify)" "$(g_doctor)"
}

case_verifys_url_handler_note_sends_you_to_a_rule_doctor_reports() {
    guidance_fixture
    mkdir -p "$HOME/Applications/Claude Code URL Handler.app"
    assert_doctor_reports_what_verify_says "$(g_verify)" "$(g_doctor)"
}

case_verifys_ide_note_sends_you_to_a_rule_doctor_reports() {
    guidance_fixture
    mkdir -p "$HOME/.vscode/extensions/anthropic.claude-code-2.1.266-darwin-arm64"
    assert_doctor_reports_what_verify_says "$(g_verify)" "$(g_doctor)"
}

# ---------------------------------------------------------------------------
# The invariant, kept by the suite as well as by the tool
# ---------------------------------------------------------------------------

# The audit asks the Keychain two read-only questions and nothing else. The
# stand-in refuses everything that is not one of them, so a rule that started
# reading a secret would fail here rather than on somebody's machine.
case_the_audit_never_asks_the_keychain_for_a_secret() {
    guidance_fixture
    g_doctor --keychain-scan >/dev/null 2>&1
    g_verify >/dev/null 2>&1
    g_remove bouvet >/dev/null 2>&1
    if [ -f "$HOME/security-refused" ]; then
        fail "the tool made a security(1) call the stand-in refuses" \
             "$(cat "$HOME/security-refused")"
    fi
}

# And the proof that the stand-in would have caught it.
case_the_stand_in_security_refuses_a_delete_or_a_secret_read() {
    guidance_fixture
    "$HOME/fakebin/security" delete-generic-password -s x -a tester >/dev/null 2>&1
    assert_status 90 $? "a delete was not refused" || return
    "$HOME/fakebin/security" find-generic-password -s x -a tester -w >/dev/null 2>&1
    assert_status 90 $? "a secret read was not refused" || return
    "$HOME/fakebin/security" dump-keychain -d >/dev/null 2>&1
    assert_status 90 $? "a secret dump was not refused" || return
    _recorded=$(cat "$HOME/security-refused" 2>/dev/null)
    assert_contains "$_recorded" "delete-generic-password" || return
    assert_contains "$_recorded" "-w" || return
    assert_contains "$_recorded" "-d"
}

run_case "the guidance is still where this looks for it" case_the_guidance_is_still_where_this_file_looks_for_it
run_case "every command the guidance names exists"       case_every_command_the_guidance_names_exists
run_case "every flag the guidance names is accepted"     case_every_flag_the_guidance_names_is_accepted
run_case "an invented flag is still refused"             case_an_invented_flag_is_still_refused
run_case "every rule the guidance names is catalogued"   case_every_rule_the_guidance_names_is_in_the_catalog
run_case "every rule runs under the command named"       case_every_rule_a_claim_names_runs_under_the_command_named_with_it
run_case "a rule behind a flag needs the flag"           case_a_rule_behind_a_flag_does_not_run_without_it
run_case "every fact the guidance names is recorded"     case_every_fact_the_guidance_names_is_recorded
run_case "every repository file it names exists"         case_every_repository_file_the_guidance_names_exists
run_case "no printed instruction escapes the list"       case_no_printed_instruction_escapes_the_derived_list
run_case "no printed command touches a credential"       case_no_printed_command_reads_or_deletes_a_credential
run_case "remove's credential line reports the orphan"   case_removes_credential_line_names_a_doctor_that_reports_the_orphan
run_case "remove's credential line needs its flag"       case_removes_credential_line_would_be_wrong_without_the_flag
run_case "remove's closing line reports D06 and D14"     case_removes_closing_line_names_a_doctor_that_reports_d06_and_d14
run_case "remove's paths are there, and go quiet"        case_the_paths_remove_prints_are_there_and_deleting_them_quiets_doctor
run_case "remove's credential command is refused"        case_removes_credential_command_is_a_delete_the_stand_in_refuses
run_case "D07's fix line, run as printed, quiets D07"    case_doctors_d07_fix_line_run_as_printed_quiets_d07
run_case "D13's fix line, run as printed, quiets D13"    case_doctors_d13_fix_line_run_as_printed_quiets_d13
run_case "D14's fix line, run as printed, quiets D14"    case_doctors_d14_fix_line_run_as_printed_quiets_d14
run_case "D15's fix line names the real registry"        case_doctors_d15_fix_line_names_the_registry_that_holds_the_entries
run_case "D12's skip note names a doctor that scans"     case_doctors_d12_skip_note_names_a_doctor_that_reports_d12
run_case "verify's missing-root hint holds"              case_verifys_missing_root_hint_sends_you_to_a_rule_doctor_reports
run_case "verify's project-dir note holds"               case_verifys_project_dir_note_sends_you_to_a_rule_doctor_reports
run_case "verify's URL-handler note holds"               case_verifys_url_handler_note_sends_you_to_a_rule_doctor_reports
run_case "verify's IDE note holds"                       case_verifys_ide_note_sends_you_to_a_rule_doctor_reports
run_case "the audit never asks for a secret"             case_the_audit_never_asks_the_keychain_for_a_secret
run_case "the stand-in security refuses a delete"        case_the_stand_in_security_refuses_a_delete_or_a_secret_read
