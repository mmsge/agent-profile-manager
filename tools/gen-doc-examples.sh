#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2016  # stand-ins and SHOWN commands are literal shell text
#
# gen-doc-examples.sh: generate the command examples in the documentation
# from real runs of the tool, instead of typing what it prints by hand.
#
# A documented example is a promise about what the reader will see, and a
# hand-typed one decays the moment the message changes: the tool grows a
# line, the README still shows the old output, and the reader who compares
# the two has no way to tell which is right. The "What doctor reads" table
# and the test count are generated for that reason, and this script extends
# the same rule to every example the tool or the installer can produce.
#
# Each example is a scenario below, a function named ex_<id> that builds a
# throwaway HOME, runs the tool in it under a symlink named agpin, and prints
# what came back. The throwaway path is replaced by /Users/alex afterwards,
# and the credential hashes the tool derives from that path are replaced by
# the hashes it would derive from the /Users/alex form, so the output reads
# as one machine's rather than one run's. Nothing here reads a real config
# root, a real Keychain or a real Dock: the platform is pinned, every macOS
# command the tool would call has a stand-in first on PATH.
#
# The documentation marks a block like this:
#
#     <!-- BEGIN GENERATED: example new (tools/gen-doc-examples.sh) -->
#     ```sh
#     agpin new brygga
#     ```
#
#     ```
#     Created profile brygga
#     ...
#     ```
#     <!-- END GENERATED: example new -->
#
# and everything between the two markers is this script's to rewrite. The
# first fence is the command as the reader would type it; the second is the
# output, and it is left out when there is none. An example that needs a
# real Mac or a real terminal is not generated: it is marked with an
# `<!-- illustrative: ... -->` comment instead, and tests/cases/95-examples.sh
# keeps those to the ones that say why.
#
# Usage:
#   tools/gen-doc-examples.sh           # rewrite every marked block
#   tools/gen-doc-examples.sh --check   # fail naming each example that
#                                       # differs, write nothing
#   tools/gen-doc-examples.sh --list    # the scenarios this script knows
#
# Run the plain form after changing a message the documentation shows, and
# commit the change it makes. CI runs the --check form on every leg.

set -u

SELF=$(basename "$0")
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/bin/agent-profile"
INSTALLER="$ROOT/tools/install.sh"

# The files that may carry generated examples. A block anywhere else is not
# looked for, so a stray marker cannot make this script rewrite a file it
# was never meant to touch.
DOC_FILES="README.md docs/SETUP.md docs/USE.md docs/INSTALL.md docs/DESKTOP.md docs/AUDIT.md docs/TROUBLESHOOTING.md docs/OFFBOARDING.md docs/LIMITS.md docs/CONTRIBUTING.md"

# The user and the paths every example is rewritten to. The throwaway HOME
# becomes DOC_HOME, and a checkout the installer links to becomes DOC_SRC.
DOC_USER="alex"
DOC_HOME="/Users/alex"
DOC_SRC="/Users/alex/src/agent-profile"

MODE="write"

while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check" ;;
        --list)  MODE="list" ;;
        -h|--help)
            printf 'usage: %s [--check|--list]\n' "$SELF"
            exit 0
            ;;
        *)
            printf 'usage: %s [--check|--list]\n' "$SELF" >&2
            exit 2
            ;;
    esac
    shift
done

die() {
    printf '%s: %s\n' "$SELF" "$1" >&2
    shift
    for _d in ${1+"$@"}; do printf '  %s\n' "$_d" >&2; done
    exit 1
}

[ -f "$SCRIPT" ] || die "no such file: $SCRIPT"
[ -f "$INSTALLER" ] || die "no such file: $INSTALLER"
command -v python3 >/dev/null 2>&1 || die "python3 is needed, the same way the tool itself needs it"

# Every scenario runs the tool under the interpreter running this script,
# the way tests/run.sh does, so the bash 3.2 leg generates under bash 3.2.
BASH_BIN="${BASH:-/bin/bash}"
VERSION=$(sed -n 's/^AGENT_PROFILE_VERSION="\([^"]*\)"$/\1/p' "$SCRIPT" | head -1)
[ -n "$VERSION" ] || die "could not read AGENT_PROFILE_VERSION from $SCRIPT"

# One work directory for the run, under TMPDIR. The fixture HOMEs live in it
# and it is removed on exit, whatever happened.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gen-doc-examples.XXXXXX") || \
    die "could not create a temporary directory under ${TMPDIR:-/tmp}"
# macOS gives TMPDIR a trailing slash, which mktemp keeps. The tool's own
# canonical form has no double slash, so neither may the fixture.
WORK=$(cd "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK/out" "$WORK/homes"

# python3 is found on PATH in the fixture too, wherever this machine keeps it.
PY_DIR=$(dirname "$(command -v python3)")

# ---------------------------------------------------------------------------
# Fixtures
#
# These are the stand-ins tests/run.sh uses, cut down to what the examples
# need. They are duplicated rather than sourced because tests/run.sh runs
# the suite when it is read, and because a documentation generator that
# needs the test harness loaded is a stranger dependency than forty lines.
# ---------------------------------------------------------------------------

# H is the current fixture HOME, set by fixture_home and read by everything
# below. SHOWN is the command the block shows the reader, set by a scenario
# before it prints its output.
H=""
SHOWN=""

# fixture_home <id>: a fresh throwaway HOME with the tool linked as agpin,
# the stand-ins first on PATH, and nothing from the real machine in reach.
fixture_home() {
    H=$(mktemp -d "$WORK/homes/$1.XXXXXX") || die "could not create a fixture HOME for $1"
    H=$(cd "$H" && pwd)
    mkdir -p "$H/bin" "$H/.local/bin"
    ln -sf "$SCRIPT" "$H/.local/bin/agpin"
    ln -sf "$SCRIPT" "$H/.local/bin/agent-profile"
    stand_in_osa "$H/bin"
    # A launch is never what an example wants. If a scenario reaches open(1)
    # anyway, this says so and launches nothing.
    printf '#!/bin/sh\necho "open: stand-in, launched nothing: $*"\nexit 1\n' > "$H/bin/open"
    chmod +x "$H/bin/open"
    # Every example runs as macOS, because that is the machine the reader
    # has, and the two macOS commands doctor consults are stand-ins: a
    # Keychain that knows only the services a scenario tells it about, and
    # an empty Dock. The tool never reads a credential, and neither does an
    # example; the stand-in refuses a -g or a -w outright.
    stand_in_keychain
    stand_in_defaults
}

# stand_in_osa <bindir>: osacompile stores its -e lines verbatim and
# osadecompile prints them back, which is the round trip the applet
# machinery depends on. First on PATH, so the real ones on a Mac never see
# a fixture applet.
stand_in_osa() {
    cat > "$1/osacompile" <<'OSAEOF'
#!/bin/sh
lines=""; out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -e) shift; lines="$lines$1
" ;;
        -o) shift; out="$1" ;;
    esac
    shift
done
[ -n "$out" ] || exit 1
mkdir -p "$out/Contents/Resources/Scripts" || exit 1
printf '%s' "$lines" > "$out/Contents/Resources/Scripts/main.scpt"
OSAEOF
    cat > "$1/osadecompile" <<'OSDEOF'
#!/bin/sh
[ -f "$1" ] || exit 1
cat "$1"
OSDEOF
    chmod +x "$1/osacompile" "$1/osadecompile"
}

# stand_in_keychain: a security(1) that knows only the services listed in
# the fixture's own services file, one per line, which signed_in appends
# to. Attributes only, as the real call is made: find-generic-password
# answers yes or no and nothing else, and -g or -w are refused outright.
stand_in_keychain() {
    : > "$H/.keychain-services"
    {
        printf '#!/bin/sh\n'
        printf 'case "$1" in\n'
        printf '  find-generic-password) shift; svc=""\n'
        printf '    for a in "$@"; do case "$a" in -g|-w) exit 70 ;; esac; done\n'
        printf '    while [ $# -gt 0 ]; do [ "$1" = "-s" ] && { shift; svc="$1"; }; shift; done\n'
        printf '    grep -qxF "$svc" "$HOME/.keychain-services" && exit 0 || exit 44 ;;\n'
        printf '  *) exit 70 ;;\n'
        printf 'esac\n'
    } > "$H/bin/security"
    chmod +x "$H/bin/security"
}

# stand_in_defaults: a defaults(1) that reports an empty Dock, so D17 runs
# and finds nothing, and refuses every other question.
stand_in_defaults() {
    {
        printf '#!/bin/sh\n'
        printf '[ "$1" = "read" ] && [ "$2" = "com.apple.dock" ] && [ "$3" = "persistent-apps" ] || exit 1\n'
        printf 'printf "(\\n)\\n"\n'
    } > "$H/bin/defaults"
    chmod +x "$H/bin/defaults"
}

# cred_service_for <root>: the Keychain service name the agent uses for a
# root, computed the way the tool computes it (docs/FACTS.md F03).
cred_service_for() {
    printf 'Claude Code-credentials-%s\n' "$(python3 -c '
import hashlib, sys, unicodedata
print(hashlib.sha256(unicodedata.normalize("NFC", sys.argv[1]).encode()).hexdigest()[:8])
' "$1")"
}

# fixture_account <root> <email> <org>: a signed-in account, in the shape
# the agent records one, merged into the state file new already wrote.
fixture_account() {
    mkdir -p "$1"
    python3 - "$1/.claude.json" "$2" "$3" <<'PY'
import json, os, sys
path, email, org = sys.argv[1:4]
data = {}
if os.path.isfile(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except ValueError:
        data = {}
data["oauthAccount"] = {"emailAddress": email, "organizationUuid": org}
with open(path, "w") as fh:
    json.dump(data, fh)
    fh.write("\n")
PY
}

# fixture_transcript <root> <cwd> [name]: one session under the project
# directory the agent would use for that working directory.
fixture_transcript() {
    _ft_dir=$(printf '%s' "$2" | sed 's/[^A-Za-z0-9]/-/g')
    mkdir -p "$1/projects/$_ft_dir"
    printf '{"type":"user","cwd":"%s","version":"2.1.263","sessionId":"%s"}\n' "$2" "${3:-s1}" \
        > "$1/projects/$_ft_dir/${3:-s1}.jsonl"
}

# fixture_applet <applet> <root> <app-data>: a launcher holding exactly the
# line app would write, pinned to the real desktop app's path.
fixture_applet() {
    mkdir -p "$1/Contents/Resources/Scripts"
    printf 'do shell script "open -n -a \\"/Applications/Claude.app\\" --env \\"CLAUDE_CONFIG_DIR=%s\\" --args --user-data-dir=\\"%s\\" > /dev/null 2>&1 &"\n' \
        "$2" "$3" > "$1/Contents/Resources/Scripts/main.scpt"
}

# fixture_release: a release laid out the way GitHub lays one out, served
# over file:// so the installer's real download, checksum and unpack path
# runs. The tarball holds this checkout's bin, tools and docs.
fixture_release() {
    _fr_dir="$H/release/download/v$VERSION"
    mkdir -p "$_fr_dir"
    _fr_stage="$WORK/stage"
    rm -rf "$_fr_stage"
    mkdir -p "$_fr_stage/agent-profile-$VERSION"
    cp -R "$ROOT/bin" "$ROOT/tools" "$ROOT/docs" "$_fr_stage/agent-profile-$VERSION/"
    cp "$ROOT/README.md" "$_fr_stage/agent-profile-$VERSION/"
    tar -czf "$_fr_dir/agent-profile-$VERSION.tar.gz" -C "$_fr_stage" "agent-profile-$VERSION"
    ( cd "$_fr_dir" && shasum -a 256 "agent-profile-$VERSION.tar.gz" > SHA256SUMS )
    printf 'stand-in bundle\n' > "$_fr_dir/agent-profile-$VERSION.tar.gz.sigstore"
    printf 'stand-in bundle\n' > "$_fr_dir/SHA256SUMS.sigstore"
    printf '{"tag_name": "v%s", "name": "v%s"}\n' "$VERSION" "$VERSION" > "$H/release/latest.json"
    # A checkout the reader could have cloned, for the --dev example.
    rm -rf "$H/src"
    mkdir -p "$H/src"
    cp -R "$_fr_stage/agent-profile-$VERSION" "$H/src/agent-profile"
    rm -rf "$_fr_stage"
}

# stand_in_cosign <exit-status>: a cosign that checks the shape of the call
# and answers as told, so the verified path runs without a real signature.
stand_in_cosign() {
    cat > "$H/bin/cosign" <<'COSEOF'
#!/bin/sh
[ "$1" = "verify-blob" ] || exit 64
shift
bundle=""; blob=""
while [ $# -gt 0 ]; do
    case "$1" in
        --bundle) shift; bundle="$1" ;;
        --certificate-identity-regexp|--certificate-oidc-issuer) shift ;;
        -*) ;;
        *) blob="$1" ;;
    esac
    shift
done
[ -f "$bundle" ] && [ -f "$blob" ] || exit 65
COSEOF
    printf 'exit %s\n' "$1" >> "$H/bin/cosign"
    chmod +x "$H/bin/cosign"
}

# fresh_path: a PATH without ~/.local/bin on it, which is how a Mac that
# has never had a tool installed there starts out. The install examples
# use it, so the installer's warning about it is part of what they show.
fresh_path() {
    printf '%s\n' "$H/bin:$PY_DIR:/usr/bin:/bin"
}

# in_fixture [VAR=value ...] <command...>: run a command with nothing but the
# fixture's environment. env -i is the point: no CLAUDE_CONFIG_DIR, no
# AGENT_PROFILE_EXPLAIN and no PATH from the shell this runs in can reach
# the example, so two machines generate the same block.
in_fixture() {
    env -i \
        HOME="$H" \
        USER="$DOC_USER" \
        SHELL="/bin/zsh" \
        TMPDIR="$WORK" \
        PATH="$H/bin:$H/.local/bin:$PY_DIR:/usr/bin:/bin" \
        AGENT_PROFILE_PLATFORM="Darwin" \
        AGENT_PROFILE_APPLET_DIRS="$H/Applications:$H/Desktop" \
        AGENT_PROFILE_RELEASE_BASE_URL="file://$H/release" \
        AGENT_PROFILE_RELEASE_API_URL="file://$H/release/latest.json" \
        "$@"
}

# agpin <args...>: the tool, as agpin, in the fixture. Output and errors
# together, the way a terminal shows them; the exit status is discarded,
# because the block shows what was printed and the prose says what it means.
agpin() {
    in_fixture "$BASH_BIN" "$H/.local/bin/agpin" "$@" 2>&1
    return 0
}

# quiet <args...>: a setup step whose output is not part of the example.
quiet() {
    agpin "$@" >/dev/null
}

# two_profiles: the machine most examples run on, brygga and havnelab, each
# signed in with one session, so doctor is clean and list has something to
# say.
two_profiles() {
    quiet new brygga
    quiet new havnelab
    signed_in brygga "alex@brygga.example" "org-brygga"
    signed_in havnelab "alex@havnelab.example" "org-havnelab"
    fixture_transcript "$H/.claude-brygga" "/Users/alex/src/brygga-api"
    fixture_transcript "$H/.claude-havnelab" "/Users/alex/src/havnelab-web"
}

# signed_in <name> <email> <org>: a profile that has logged in once, which
# on a Mac means an account block in its state file and a Keychain entry
# for its root.
signed_in() {
    fixture_account "$H/.claude-$1" "$2" "$3"
    cred_service_for "$H/.claude-$1" >> "$H/.keychain-services"
}

# used_machine: a Mac that ran unpinned for months, with one new profile
# just registered. Every finding the setup guide walks through is here.
used_machine() {
    quiet new brygga
    signed_in brygga "alex@brygga.example" "org-brygga"
    fixture_transcript "$H/.claude-brygga" "/Users/alex/src/brygga-api"
    # D01: sessions in the default root, from unpinned use.
    fixture_transcript "$H/.claude" "/Users/alex/src/notes"
    # D02: the state file an unpinned run leaves beside the default root.
    fixture_account "$H" "alex@personal.example" "org-personal"
    # D06: a root made by hand, before this tool, that no profile claims.
    mkdir -p "$H/.claude-torg"
    chmod 755 "$H/.claude-torg"
    signed_in torg "alex@torg.example" "org-torg"
    fixture_transcript "$H/.claude-torg" "/Users/alex/src/torg-portal" s1
    fixture_transcript "$H/.claude-torg" "/Users/alex/src/torg-billing" s2
    # D14: a launcher made by hand, on the Desktop, pinning brygga's root.
    fixture_applet "$H/Desktop/Claude Work.app" "$H/.claude-brygga" \
        "$H/Library/Application Support/Claude-Brygga"
    # D09: the deep-link handler the agent installs.
    mkdir -p "$H/Applications/Claude Code URL Handler.app"
}

# ---------------------------------------------------------------------------
# The scenarios
#
# ex_<id> builds its fixture, sets SHOWN to the command the reader would
# type, and prints the output. Add one here, mark a block with its id, run
# the plain form, and commit both.
# ---------------------------------------------------------------------------

SCENARIOS=""
scenario() { SCENARIOS="$SCENARIOS $1"; }

scenario install
ex_install() {
    fixture_release
    stand_in_cosign 0
    SHOWN='curl -fsSL https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh | bash'
    in_fixture PATH="$(fresh_path)" "$BASH_BIN" "$INSTALLER" 2>&1
    return 0
}

scenario install-no-cosign
ex_install_no_cosign() {
    fixture_release
    SHOWN='curl -fsSL https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh | bash'
    in_fixture PATH="$(fresh_path)" AGENT_PROFILE_COSIGN=cosign-is-not-installed \
        "$BASH_BIN" "$INSTALLER" 2>&1
    return 0
}

scenario install-again
ex_install_again() {
    fixture_release
    stand_in_cosign 0
    in_fixture PATH="$(fresh_path)" "$BASH_BIN" "$INSTALLER" >/dev/null 2>&1
    SHOWN='curl -fsSL https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh | bash'
    in_fixture PATH="$(fresh_path)" "$BASH_BIN" "$INSTALLER" 2>&1
    return 0
}

scenario install-dev
ex_install_dev() {
    fixture_release
    SHOWN='tools/install.sh --dev'
    in_fixture PATH="$(fresh_path)" "$BASH_BIN" "$H/src/agent-profile/tools/install.sh" --dev 2>&1
    return 0
}

scenario install-uninstall
ex_install_uninstall() {
    fixture_release
    stand_in_cosign 0
    in_fixture "$BASH_BIN" "$INSTALLER" >/dev/null 2>&1
    SHOWN='tools/install.sh --uninstall'
    in_fixture "$BASH_BIN" "$H/src/agent-profile/tools/install.sh" --uninstall 2>&1
    return 0
}

scenario version
ex_version() {
    SHOWN='agpin version'
    agpin version
}

scenario version-check
ex_version_check() {
    fixture_release
    SHOWN='agpin version --check'
    agpin version --check
}

scenario help
ex_help() {
    SHOWN='agpin help'
    agpin help
}

scenario new
ex_new() {
    SHOWN='agpin new brygga'
    agpin new brygga
}

scenario new-explain
ex_new_explain() {
    SHOWN='agpin new brygga --explain'
    agpin new brygga --explain
}

scenario new-again
ex_new_again() {
    quiet new brygga
    SHOWN='agpin new brygga'
    agpin new brygga
}

scenario new-adopt
ex_new_adopt() {
    used_machine
    SHOWN='agpin new torg --root ~/.claude-torg'
    agpin new torg --root "$H/.claude-torg"
}

scenario new-adopt-explain
ex_new_adopt_explain() {
    used_machine
    SHOWN='agpin new torg --root ~/.claude-torg --explain'
    agpin new torg --root "$H/.claude-torg" --explain
}

scenario new-default-root
ex_new_default_root() {
    used_machine
    SHOWN='agpin new main --root ~/.claude --explain'
    agpin new main --root "$H/.claude" --explain
}

scenario list
ex_list() {
    two_profiles
    SHOWN='agpin list'
    agpin list
}

scenario list-fresh
ex_list_fresh() {
    quiet new brygga
    quiet new havnelab
    SHOWN='agpin list'
    agpin list
}

scenario which-unpinned
ex_which_unpinned() {
    two_profiles
    SHOWN='agpin which'
    agpin which
}

scenario which-pinned
ex_which_pinned() {
    two_profiles
    SHOWN='eval "$(agpin env brygga)"
agpin which'
    in_fixture CLAUDE_CONFIG_DIR="$H/.claude-brygga" "$BASH_BIN" "$H/.local/bin/agpin" which 2>&1
    return 0
}

scenario env
ex_env() {
    two_profiles
    SHOWN='agpin env brygga'
    agpin env brygga
}

scenario explain
ex_explain() {
    two_profiles
    SHOWN='agpin explain'
    agpin explain
}

scenario doctor-clean
ex_doctor_clean() {
    two_profiles
    SHOWN='agpin doctor'
    agpin doctor
}

scenario doctor-fresh
ex_doctor_fresh() {
    quiet new brygga
    quiet new havnelab
    SHOWN='agpin doctor'
    agpin doctor
}

scenario doctor-first-run
ex_doctor_first_run() {
    used_machine
    SHOWN='agpin doctor'
    agpin doctor
}

scenario app-adopt-launcher
ex_app_adopt_launcher() {
    used_machine
    SHOWN="agpin app brygga --applet '~/Desktop/Claude Work.app'"
    agpin app brygga --applet "$H/Desktop/Claude Work.app"
}

scenario doctor-second-run
ex_doctor_second_run() {
    used_machine
    quiet new torg --root "$H/.claude-torg"
    quiet app brygga --applet "$H/Desktop/Claude Work.app"
    SHOWN='agpin doctor'
    agpin doctor
}

scenario doctor-third-run
ex_doctor_third_run() {
    used_machine
    quiet new torg --root "$H/.claude-torg"
    quiet app brygga --applet "$H/Desktop/Claude Work.app"
    quiet new main --root "$H/.claude"
    SHOWN='agpin doctor'
    agpin doctor
}

scenario doctor-json-d12
ex_doctor_json_d12() {
    two_profiles
    SHOWN="agpin doctor --json | python3 -c 'import json, sys
rules = json.load(sys.stdin)[\"rules\"]
print(json.dumps([r for r in rules if r[\"rule\"] == \"D12\"][0], indent=2))'"
    agpin doctor --json | python3 -c 'import json, sys
rules = json.load(sys.stdin)["rules"]
print(json.dumps([r for r in rules if r["rule"] == "D12"][0], indent=2))'
    return 0
}

scenario doctor-report
# ~/audits is not there to begin with, which is the state every reader's Mac
# is in, so the example shows the directory being made.
ex_doctor_report() {
    two_profiles
    SHOWN='agpin doctor --report ~/audits/brygga-2026-09-08'
    agpin doctor --report "$H/audits/brygga-2026-09-08"
}

scenario doctor-quiet
ex_doctor_quiet() {
    two_profiles
    SHOWN='agpin doctor --quiet'
    agpin doctor --quiet
}

scenario app
ex_app() {
    two_profiles
    SHOWN='agpin app brygga'
    agpin app brygga
}

scenario app-explain
ex_app_explain() {
    two_profiles
    quiet app brygga
    SHOWN='agpin app brygga --explain'
    agpin app brygga --explain
}

# The rc block, in the dialect of one shell. The fixture's $SHELL is zsh,
# which is what a Mac has, so this is the block a reader will see.
scenario shellrc
ex_shellrc() {
    SHOWN='agpin shellrc'
    agpin shellrc
}

scenario guard-refusal
ex_guard_refusal() {
    two_profiles
    SHOWN='eval "$(agpin guard)"
claude'
    in_fixture "$BASH_BIN" -c 'eval "$(agpin guard)"; claude' 2>&1
    return 0
}

scenario remove
ex_remove() {
    two_profiles
    fixture_transcript "$H/.claude-brygga" "/Users/alex/src/brygga-api" s2
    fixture_transcript "$H/.claude-brygga" "/Users/alex/src/brygga-docs" s3
    quiet app brygga
    SHOWN='agpin remove brygga'
    agpin remove brygga
}

scenario remove-purge
ex_remove_purge() {
    two_profiles
    fixture_transcript "$H/.claude-brygga" "/Users/alex/src/brygga-api" s2
    fixture_transcript "$H/.claude-brygga" "/Users/alex/src/brygga-docs" s3
    quiet app brygga
    SHOWN='agpin remove brygga --purge'
    printf 'brygga\n' | in_fixture AGENT_PROFILE_ASSUME_TTY=1 \
        "$BASH_BIN" "$H/.local/bin/agpin" remove brygga --purge 2>&1
    return 0
}

scenario doctor-after-remove
ex_doctor_after_remove() {
    two_profiles
    quiet app brygga
    quiet remove brygga
    SHOWN='agpin doctor'
    agpin doctor
}

scenario err-no-such-profile
ex_err_no_such_profile() {
    two_profiles
    SHOWN='agpin run bryga'
    agpin run bryga
}

scenario err-claude-not-on-path
ex_err_claude_not_on_path() {
    two_profiles
    SHOWN='agpin run brygga'
    in_fixture PATH="$H/bin:$H/.local/bin:$PY_DIR:/usr/bin:/bin" \
        "$BASH_BIN" "$H/.local/bin/agpin" run brygga 2>&1
    return 0
}

# A Mac with no Command Line Tools, which is every Mac issued to somebody
# who is not a developer. PATH holds the stand-ins and nothing else, so
# there is no python3 anywhere on it.
scenario err-no-python3
ex_err_no_python3() {
    SHOWN='agpin new brygga'
    in_fixture PATH="$H/bin" "$BASH_BIN" "$H/.local/bin/agpin" new brygga 2>&1
    return 0
}

scenario err-already-registered
ex_err_already_registered() {
    two_profiles
    SHOWN='agpin new brygga --root ~/.claude-brygga-2'
    agpin new brygga --root "$H/.claude-brygga-2"
}

scenario err-root-relative
ex_err_root_relative() {
    SHOWN='agpin new brygga --root relative/path'
    agpin new brygga --root relative/path
}

scenario err-two-launchers
ex_err_two_launchers() {
    two_profiles
    fixture_applet "$H/Applications/Claude-Brygga.app" "$H/.claude-brygga" \
        "$H/Library/Application Support/Claude-Brygga"
    fixture_applet "$H/Desktop/Brygga2.app" "$H/.claude-brygga" \
        "$H/Library/Application Support/Claude-Brygga"
    SHOWN='agpin app brygga'
    agpin app brygga
}

scenario err-not-an-applet
ex_err_not_an_applet() {
    two_profiles
    mkdir -p "$H/NotAnApplet.app/Contents"
    SHOWN='agpin app brygga --applet ~/NotAnApplet.app'
    agpin app brygga --applet "$H/NotAnApplet.app"
}

scenario err-unsafe-character
ex_err_unsafe_character() {
    quiet new weird --app-data "$H/Library/Application Support/Weird\$Name"
    SHOWN='agpin app weird'
    agpin app weird
}

scenario err-unknown-command
ex_err_unknown_command() {
    two_profiles
    SHOWN='agpin dotcor'
    agpin dotcor
}

# ---------------------------------------------------------------------------
# Running a scenario, and making its output read as one machine's
# ---------------------------------------------------------------------------

# cook <raw-output> <fixture-home> <checkout>: the throwaway paths become the
# documented ones, and every credential hash the tool derived from a fixture
# root becomes the hash of the same root under DOC_HOME. Everything else is
# left exactly as the tool printed it.
cook() {
    python3 - "$1" "$2" "$3" "$DOC_HOME" "$DOC_SRC" <<'PY'
import glob, hashlib, os, re, sys, unicodedata

raw, home, checkout, doc_home, doc_src = sys.argv[1:6]
with open(raw) as fh:
    text = fh.read()

def suffix(path):
    return hashlib.sha256(unicodedata.normalize("NFC", path).encode()).hexdigest()[:8]

roots = set(glob.glob(os.path.join(home, ".claude*")))
roots.add(os.path.join(home, ".claude"))
# A root remove has already deleted is still named in the output.
roots.update(re.findall(re.escape(home) + r"/\.claude[A-Za-z0-9_-]*", text))
for conf in glob.glob(os.path.join(home, ".config", "agent-profiles", "*.conf")):
    with open(conf) as fh:
        for line in fh:
            if line.startswith("root="):
                roots.add(line[5:].rstrip("\n"))
for root in sorted(roots):
    if not root.startswith(home):
        continue
    doc_root = doc_home + root[len(home):]
    text = text.replace("credentials-" + suffix(root), "credentials-" + suffix(doc_root))

text = text.replace(home, doc_home)
text = text.replace(checkout, doc_src)
sys.stdout.write(text)
PY
}

# ---------------------------------------------------------------------------
# The documents
# ---------------------------------------------------------------------------

begin_mark() { printf '<!-- BEGIN GENERATED: example %s (tools/gen-doc-examples.sh) -->' "$1"; }
end_mark()   { printf '<!-- END GENERATED: example %s -->' "$1"; }

# block_ids <file>: the ids of the blocks a file carries, in order, checking
# that every BEGIN has its END with the same id and that no block nests.
block_ids() {
    awk -v f="$1" '
        /^<!-- BEGIN GENERATED: example / {
            if (open != "") {
                printf "%s: line %d: a generated block for %s opens inside the one for %s\n", f, NR, $0, open > "/dev/stderr"
                bad = 1
            }
            id = $0
            sub(/^<!-- BEGIN GENERATED: example /, "", id)
            sub(/ \(tools\/gen-doc-examples\.sh\) -->$/, "", id)
            if (id == $0 || id ~ / /) {
                printf "%s: line %d: a BEGIN marker this script cannot read: %s\n", f, NR, $0 > "/dev/stderr"
                bad = 1
                next
            }
            open = id
            print id
            next
        }
        /^<!-- END GENERATED: example / {
            id = $0
            sub(/^<!-- END GENERATED: example /, "", id)
            sub(/ -->$/, "", id)
            if (open == "") {
                printf "%s: line %d: an END marker with no block open: %s\n", f, NR, $0 > "/dev/stderr"
                bad = 1
            } else if (id != open) {
                printf "%s: line %d: the END marker names %s but the block open is %s\n", f, NR, id, open > "/dev/stderr"
                bad = 1
            }
            open = ""
            next
        }
        END {
            if (open != "") {
                printf "%s: the generated block for %s is never closed\n", f, open > "/dev/stderr"
                bad = 1
            }
            exit bad
        }
    ' "$1"
}

# current_block <file> <id>: what the file holds between the markers now.
current_block() {
    awk -v b="$(begin_mark "$2")" -v e="$(end_mark "$2")" '
        $0 == e { inblock = 0 }
        inblock { print }
        $0 == b { inblock = 1 }
    ' "$1"
}

# rewrite_file <file>: replace every block in a file with the generated one.
rewrite_file() {
    _rw_tmp="$WORK/rewrite"
    awk -v outdir="$WORK/out" '
        /^<!-- BEGIN GENERATED: example / {
            id = $0
            sub(/^<!-- BEGIN GENERATED: example /, "", id)
            sub(/ \(tools\/gen-doc-examples\.sh\) -->$/, "", id)
            print
            f = outdir "/" id
            while ((getline l < f) > 0) print l
            close(f)
            skipping = 1
            next
        }
        /^<!-- END GENERATED: example / { skipping = 0; print; next }
        skipping { next }
        { print }
    ' "$1" > "$_rw_tmp"
    # Never leave a truncated document behind.
    _rw_before=$(grep -c '^<!-- END GENERATED: example ' "$1")
    _rw_after=$(grep -c '^<!-- END GENERATED: example ' "$_rw_tmp")
    [ "$_rw_before" = "$_rw_after" ] || die "the rewrite of $1 lost a block, so nothing was written"
    cat "$_rw_tmp" > "$1"
}

if [ "$MODE" = list ]; then
    for _id in $SCENARIOS; do printf '%s\n' "$_id"; done
    exit 0
fi

# ---- collect the blocks ----------------------------------------------------
_all_ids=""
_files=""
for _doc in $DOC_FILES; do
    [ -f "$ROOT/$_doc" ] || continue
    if ! _ids=$(block_ids "$ROOT/$_doc"); then
        die "the generated blocks in $_doc are not well formed; see above"
    fi
    [ -n "$_ids" ] || continue
    _files="$_files $_doc"
    for _id in $_ids; do
        case " $_all_ids " in
            *" $_id "*) ;;
            *) _all_ids="$_all_ids $_id" ;;
        esac
    done
done

if [ -z "$_all_ids" ]; then
    printf '%s: no generated example blocks in %s\n' "$SELF" "$(printf '%s' "$DOC_FILES" | tr ' ' ',')"
    exit 0
fi

# ---- run each scenario once ------------------------------------------------
#
# The scenario runs in a subshell so its fixture cannot leak into the next,
# which means SHOWN cannot come back through the variable. The subshell
# writes it to a file beside the output instead.
run_scenario() {
    _rs_id="$1"
    _rs_fn="ex_$(printf '%s' "$_rs_id" | tr '-' '_')"
    type "$_rs_fn" >/dev/null 2>&1 || die "no scenario named '$_rs_id'" \
        "A block asks for an example this script does not know how to produce." \
        "Add an $_rs_fn function to tools/gen-doc-examples.sh, or fix the id in the marker."
    fixture_home "$_rs_id"
    _rs_home="$H"
    _rs_raw="$WORK/out/$_rs_id.raw"
    _rs_shown="$WORK/out/$_rs_id.shown"
    (
        SHOWN=""
        "$_rs_fn" > "$_rs_raw"
        printf '%s' "$SHOWN" > "$_rs_shown"
    ) || die "scenario '$_rs_id' failed"
    [ -s "$_rs_shown" ] || die "scenario '$_rs_id' did not say what command to show" \
        "Set SHOWN inside ex_$(printf '%s' "$_rs_id" | tr '-' '_') before printing the output."
    if grep -q '^```' "$_rs_raw"; then
        die "the output of scenario '$_rs_id' contains a fence line, which a block cannot carry"
    fi
    _rs_out="$WORK/out/$_rs_id"
    {
        printf '```sh\n'
        cat "$_rs_shown"
        printf '\n```\n'
        if [ -s "$_rs_raw" ]; then
            printf '\n```\n'
            cook "$_rs_raw" "$_rs_home" "$ROOT"
            printf '```\n'
        fi
    } > "$_rs_out"
    if grep -q -F "$_rs_home" "$_rs_out"; then
        die "the block for '$_rs_id' still names the fixture path $_rs_home" \
            "Something printed a path the substitution does not know about."
    fi
    rm -rf "$_rs_home"
}

for _id in $_all_ids; do
    run_scenario "$_id"
done

# ---- compare, or write -----------------------------------------------------
_drifted=0
_total=0
for _doc in $_files; do
    for _id in $(block_ids "$ROOT/$_doc"); do
        _total=$((_total + 1))
        current_block "$ROOT/$_doc" "$_id" > "$WORK/current"
        if ! cmp -s "$WORK/current" "$WORK/out/$_id"; then
            _drifted=$((_drifted + 1))
            if [ "$MODE" = check ]; then
                printf "%s: %s: the example '%s' is not what the tool prints\n" "$SELF" "$_doc" "$_id" >&2
                diff "$WORK/current" "$WORK/out/$_id" | sed 's/^/  /' >&2
            fi
        fi
    done
done

if [ "$MODE" = check ]; then
    if [ "$_drifted" -gt 0 ]; then
        printf '%s: %s of %s example(s) differ; run tools/gen-doc-examples.sh and commit the result\n' \
            "$SELF" "$_drifted" "$_total" >&2
        exit 1
    fi
    printf '%s: the documentation agrees with the tool: %s example(s) in%s\n' \
        "$SELF" "$_total" "$(printf '%s' "$_files" | sed 's/ /, /g; s/^,//')"
    exit 0
fi

if [ "$_drifted" -eq 0 ]; then
    printf '%s: every example is already up to date: %s example(s), nothing to do\n' "$SELF" "$_total"
    exit 0
fi
for _doc in $_files; do
    rewrite_file "$ROOT/$_doc"
done
printf '%s: updated %s of %s example(s) in%s\n' \
    "$SELF" "$_drifted" "$_total" "$(printf '%s' "$_files" | sed 's/ /, /g; s/^,//')"
