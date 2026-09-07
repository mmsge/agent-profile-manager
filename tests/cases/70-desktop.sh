# shellcheck shell=bash
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
#
# The desktop half. Stand-in open, osacompile, osadecompile, sips and iconutil
# plus AGENT_PROFILE_PLATFORM let these run anywhere, so the macOS-only paths
# are exercised in CI rather than shipped unrun.

# desk: run agent-profile as if on macOS, against the fixture's stand-in tools
# and a fixture app bundle.
desk() {
    PATH="$HOME/fakebin:$PATH" \
    AGENT_PROFILE_PLATFORM=Darwin \
    AGENT_PROFILE_APP_BUNDLE="$HOME/Claude.app" \
    AGENT_PROFILE_APPLET_DIRS="$HOME/Applications:$HOME/Desktop" \
        "$AP" "$@"
}

# desktop_fixture: a throwaway HOME with one profile and every stand-in tool.
#
# The stand-in security(1) is not optional. These cases pin the platform to
# Darwin, and on a real Mac that would send doctor and verify at the runner's
# own Keychain, so the same commit would pass on Linux and behave differently
# on macOS. It is given tide's own service so the Keychain-backed rules are
# quiet and a D13 assertion is testing D13.
desktop_fixture() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/Claude.app"
    fake_osa "$HOME/fakebin"
    fake_open "$HOME/fakebin" env
    fake_icon_tools "$HOME/fakebin"
    "$AP" new tide >/dev/null 2>&1
    fake_keychain "$HOME/fakebin" "$(cred_service_for "$HOME/.claude-tide")"
}

# want_line: the launch line the tool should produce for the tide fixture.
want_line() {
    printf 'do shell script "open -n -a \\"%s\\" --env \\"CLAUDE_CONFIG_DIR=%s\\" --args --user-data-dir=\\"%s\\" > /dev/null 2>&1 &"\n' \
        "$HOME/Claude.app" \
        "$HOME/.claude-tide" \
        "$HOME/Library/Application Support/Claude-Tide"
}

# ---------------------------------------------------------------------------
# desktop
# ---------------------------------------------------------------------------

# The ordering is the whole trick: everything after --args is handed to the
# application rather than to open, so an --env on the wrong side of it launches
# a perfectly healthy, perfectly unpinned app. docs/FACTS.md F13.
case_desktop_puts_env_before_args() {
    desktop_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 desk desktop tide 2>&1)
    assert_contains "$out" "--env CLAUDE_CONFIG_DIR=$HOME/.claude-tide" || return
    assert_contains "$out" "--args --user-data-dir=$HOME/Library/Application Support/Claude-Tide" || return

    before=${out%%--args*}
    case "$before" in
        *--env*) ;;
        *) fail "--env must come before --args" "got: $out"; return ;;
    esac
}

case_desktop_passes_extra_args_through() {
    desktop_fixture
    out=$(AGENT_PROFILE_DRY_RUN=1 desk desktop tide --hide 2>&1)
    assert_contains "$out" "--user-data-dir=$HOME/Library/Application Support/Claude-Tide --hide"
}

# The pin travels in --env and nowhere else. open inherits nothing from the
# invoking shell, so an exported variable here would be decoration that looks
# like a mechanism.
case_desktop_does_not_export_the_variable() {
    desktop_fixture
    cat > "$HOME/fakebin/open" <<'OPENEOF'
#!/bin/sh
[ "$1" = "--help" ] && { echo "--env VAR      Add an enviroment variable"; exit 0; }
echo "inherited=[${CLAUDE_CONFIG_DIR:-}]"
OPENEOF
    chmod +x "$HOME/fakebin/open"
    out=$(desk desktop tide 2>&1)
    assert_contains "$out" "inherited=[]"
}

# An open without --env cannot pin anything. Launching anyway would start an
# unpinned session writing to the default root, which is the leak the whole
# tool exists to prevent, so nothing is launched.
case_desktop_refuses_an_open_without_env() {
    desktop_fixture
    fake_open "$HOME/fakebin" noenv
    out=$(desk desktop tide 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "does not support --env" || return
    assert_not_contains "$out" "open: -n"
}

case_desktop_refuses_when_the_app_is_absent() {
    desktop_fixture
    rmdir "$HOME/Claude.app"
    out=$(desk desktop tide 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "not installed"
}

# ---------------------------------------------------------------------------
# app
# ---------------------------------------------------------------------------

case_app_creates_an_applet_and_registers_it() {
    desktop_fixture
    out=$(desk app tide 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "Created" || return

    applet="$HOME/Applications/Claude-Tide.app"
    [ -d "$applet" ] || { fail "no applet at $applet"; return; }
    assert_equals "$(want_line)" "$(applet_line_of "$applet")" || return
    assert_equals "$applet" "$(sed -n 's/^applet=//p' "$HOME/.config/agent-profiles/tide.conf")"
}

# "Already applied" and "never worked" must not look the same. That confusion
# cost several rounds during the migrations, and this is the command most
# likely to be run twice.
case_app_is_idempotent_and_says_so() {
    desktop_fixture
    desk app tide >/dev/null 2>&1
    out=$(desk app tide 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "already correct" || return
    assert_not_contains "$out" "Repaired"
}

case_app_repairs_a_wrong_root_and_keeps_the_icon() {
    desktop_fixture
    applet="$HOME/Applications/Claude-Tide.app"
    fixture_applet "$applet" \
        'do shell script "open -n -a \"/Applications/Claude.app\" --env \"CLAUDE_CONFIG_DIR=/somewhere/else\" --args --user-data-dir=\"/elsewhere\" > /dev/null 2>&1 &"'
    printf 'ORIGINAL-ICON\n' > "$applet/Contents/Resources/applet.icns"

    out=$(desk app tide 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "different config root" || return
    assert_equals "$(want_line)" "$(applet_line_of "$applet")" || return
    assert_equals "ORIGINAL-ICON" "$(cat "$applet/Contents/Resources/applet.icns")"
}

case_app_refuses_a_bundle_that_is_not_an_applet() {
    desktop_fixture
    applet="$HOME/Applications/Claude-Tide.app"
    mkdir -p "$applet/Contents/MacOS"
    out=$(desk app tide 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "not an AppleScript applet"
}

case_app_rejects_a_root_the_launch_line_cannot_carry() {
    HOME=$(new_home); export HOME
    mkdir -p "$HOME/Claude.app"
    fake_osa "$HOME/fakebin"
    fake_open "$HOME/fakebin" env
    "$AP" new odd --root "$HOME/has\$dollar" >/dev/null 2>&1
    out=$(desk app odd 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "cannot carry safely"
}

# ---------------------------------------------------------------------------
# icons
# ---------------------------------------------------------------------------

case_icon_is_installed_and_the_original_kept_once() {
    desktop_fixture
    applet="$HOME/Applications/Claude-Tide.app"
    desk app tide >/dev/null 2>&1
    printf 'ORIGINAL-ICON\n' > "$applet/Contents/Resources/applet.icns"
    printf 'source\n' > "$HOME/src.png"

    out=$(desk app tide --icon "$HOME/src.png" 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_equals "generated-icns" "$(cat "$applet/Contents/Resources/applet.icns")" || return
    assert_equals "ORIGINAL-ICON" "$(cat "$applet/Contents/Resources/applet.icns.orig")" || return

    # A second run must not overwrite the real original with a generated one.
    desk app tide --icon "$HOME/src.png" >/dev/null 2>&1
    assert_equals "ORIGINAL-ICON" "$(cat "$applet/Contents/Resources/applet.icns.orig")"
}

case_icon_reports_a_missing_source_image() {
    desktop_fixture
    desk app tide >/dev/null 2>&1
    out=$(desk app tide --icon "$HOME/absent.png" 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "no such image"
}

# ---------------------------------------------------------------------------
# D13
# ---------------------------------------------------------------------------

d13_out() {
    fixture_applet "$HOME/Applications/Claude-Tide.app" "$1"
    desk doctor 2>&1
}

case_d13_reports_an_unpinned_launcher() {
    desktop_fixture
    out=$(d13_out 'do shell script "open -n -a \"/Applications/Claude.app\" --args --user-data-dir=\"/x\" > /dev/null 2>&1 &"')
    assert_contains "$out" "D13" || return
    assert_contains "$out" "nothing pinned"
}

# The failure that looks correct in a diff: --env is present, spelled right,
# and useless, because open hands everything after --args to the application.
case_d13_reports_env_after_args() {
    desktop_fixture
    out=$(d13_out 'do shell script "open -n -a \"/Applications/Claude.app\" --args --env \"CLAUDE_CONFIG_DIR=/x\" --user-data-dir=\"/y\" > /dev/null 2>&1 &"')
    assert_contains "$out" "D13" || return
    assert_contains "$out" "comes after --args"
}

case_d13_reports_the_wrong_root() {
    desktop_fixture
    out=$(d13_out 'do shell script "open -n -a \"/Applications/Claude.app\" --env \"CLAUDE_CONFIG_DIR=/somewhere/else\" --args --user-data-dir=\"/x\" > /dev/null 2>&1 &"')
    assert_contains "$out" "D13" || return
    assert_contains "$out" "different config root"
}

case_d13_reports_the_wrong_app_data_dir() {
    desktop_fixture
    out=$(d13_out "do shell script \"open -n -a \\\"$HOME/Claude.app\\\" --env \\\"CLAUDE_CONFIG_DIR=$HOME/.claude-tide\\\" --args --user-data-dir=\\\"/somewhere/else\\\" > /dev/null 2>&1 &\"")
    assert_contains "$out" "D13" || return
    assert_contains "$out" "different app data directory"
}

case_d13_quiet_on_a_correct_applet() {
    desktop_fixture
    desk app tide >/dev/null 2>&1
    out=$(desk doctor 2>&1)
    assert_not_contains "$out" "D13"
}

case_d13_quiet_when_there_is_no_applet() {
    desktop_fixture
    out=$(desk doctor 2>&1)
    assert_not_contains "$out" "D13"
}

# A hand-tuned launch line that still pins the right root is nobody's business
# but its owner's. doctor reports isolation problems, not deviations from a
# generated form.
case_d13_quiet_on_a_hand_tuned_but_correct_line() {
    desktop_fixture
    out=$(d13_out "do shell script \"open -n -a \\\"$HOME/Claude.app\\\" --env \\\"CLAUDE_CONFIG_DIR=$HOME/.claude-tide\\\" --args --user-data-dir=\\\"$HOME/Library/Application Support/Claude-Tide\\\" --hide > /dev/null 2>&1 &\"")
    assert_not_contains "$out" "D13"
}

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------

case_verify_is_broken_without_env_support() {
    desktop_fixture
    fake_open "$HOME/fakebin" noenv
    out=$(desk verify 2>&1); status=$?
    assert_status 3 "$status" "$out" || return
    assert_contains "$out" "BROKEN    F13"
}

case_verify_passes_with_env_support() {
    desktop_fixture
    out=$(desk verify 2>&1)
    assert_contains "$out" "ok        F13  open still supports --env"
}

# Without osadecompile, D13 audits nothing while looking perfectly healthy.
# That is a "could not look", not a "nothing wrong", and verify has to say so.
#
# Removing the stand-in only hides it on a machine that has no osadecompile of
# its own. A stock macOS carries one in /usr/bin, so there the removal falls
# straight through to the real one. Assert whichever branch this machine can
# actually reach, rather than one that happens to hold on Linux and quietly
# tests nothing on the platform the tool targets.
case_verify_reports_on_the_applet_reader() {
    desktop_fixture
    rm -f "$HOME/fakebin/osadecompile"
    out=$(desk verify 2>&1); status=$?

    if command -v osadecompile >/dev/null 2>&1; then
        assert_contains "$out" "ok        F13  osadecompile is available"
    else
        assert_contains "$out" "osadecompile is missing" || return
        assert_status 4 "$status" "$out"
    fi
}

# ---------------------------------------------------------------------------
# Backwards compatibility
# ---------------------------------------------------------------------------

# Registry entries written before applet= existed must keep working, and must
# fall back to the conventional path rather than to nothing.
case_registry_without_an_applet_key_still_works() {
    desktop_fixture
    grep -v '^applet=' "$HOME/.config/agent-profiles/tide.conf" > "$HOME/t.conf"
    mv "$HOME/t.conf" "$HOME/.config/agent-profiles/tide.conf"
    out=$(desk app tide 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "$HOME/Applications/Claude-Tide.app"
}

case_explain_names_both_identities() {
    desktop_fixture
    out=$(desk explain 2>&1)
    assert_contains "$out" "TWO IDENTITIES" || return
    assert_contains "$out" "launcher"
}

# ---------------------------------------------------------------------------
# Finding launchers this tool did not create
# ---------------------------------------------------------------------------

# tide_line: the launch line a correct applet for the tide fixture holds.
tide_line() {
    fixture_launch_line "$HOME/Claude.app" "$HOME/.claude-tide" \
        "$HOME/Library/Application Support/Claude-Tide"
}

# The depth is the whole trick. A script sits five levels below the search
# directory, and a -maxdepth 4 returns nothing while looking like a clean
# machine. That exact mistake was made once against a real Mac, so it is
# pinned here rather than trusted to a comment.
case_scan_finds_an_applet_five_levels_down() {
    desktop_fixture
    fixture_applet "$HOME/Desktop/Tide-Claude.app" "$(tide_line)"
    out=$(desk doctor 2>&1)
    assert_contains "$out" "D14" || return
    assert_contains "$out" "$HOME/Desktop/Tide-Claude.app"
}

case_scan_ignores_bundles_that_are_not_ours() {
    desktop_fixture
    mkdir -p "$HOME/Desktop/NotAnApplet.app/Contents/MacOS"
    fixture_applet "$HOME/Desktop/Unrelated.app" 'do shell script "say hello"'
    out=$(desk doctor 2>&1)
    assert_not_contains "$out" "D14"
}

case_d14_names_the_profile_owning_the_root() {
    desktop_fixture
    fixture_applet "$HOME/Desktop/Tide-Claude.app" "$(tide_line)"
    out=$(desk doctor 2>&1)
    assert_contains "$out" "launcher for profile 'tide' is not registered" || return
    assert_contains "$out" "agent-profile app tide --applet"
}

case_d14_reports_a_launcher_no_profile_owns() {
    desktop_fixture
    fixture_applet "$HOME/Desktop/Stray.app" \
        "$(fixture_launch_line "$HOME/Claude.app" "$HOME/.claude-nobody" "$HOME/x")"
    out=$(desk doctor 2>&1)
    assert_contains "$out" "no profile claims" || return
    assert_contains "$out" "agent-profile new"
}

case_d14_quiet_once_the_applet_is_registered() {
    desktop_fixture
    fixture_applet "$HOME/Desktop/Tide-Claude.app" "$(tide_line)"
    desk app tide --applet "$HOME/Desktop/Tide-Claude.app" >/dev/null 2>&1
    out=$(desk doctor 2>&1)
    assert_not_contains "$out" "D14"
}

# Neither rule subsumes the other: a registered applet can be wrong while an
# unregistered one sits beside it, and both are worth knowing at once.
case_d13_and_d14_can_both_fire() {
    desktop_fixture
    desk app tide >/dev/null 2>&1
    fixture_applet "$(reg_applet_of tide)" \
        "$(fixture_launch_line "$HOME/Claude.app" "$HOME/.claude-elsewhere" "$HOME/x")"
    fixture_applet "$HOME/Desktop/Stray.app" \
        "$(fixture_launch_line "$HOME/Claude.app" "$HOME/.claude-nobody" "$HOME/x")"
    out=$(desk doctor 2>&1)
    assert_contains "$out" "D13" || return
    assert_contains "$out" "D14"
}

# ---------------------------------------------------------------------------
# app adopting rather than inventing
# ---------------------------------------------------------------------------

case_app_adopts_a_launcher_outside_the_conventional_dir() {
    desktop_fixture
    fixture_applet "$HOME/Desktop/Tide-Claude.app" "$(tide_line)"

    out=$(desk app tide 2>&1); status=$?
    assert_status 0 "$status" "$out" || return
    assert_contains "$out" "adopted it" || return
    assert_contains "$out" "already correct" || return
    assert_equals "$HOME/Desktop/Tide-Claude.app" "$(reg_applet_of tide)" || return

    # It must not have built a second one at the conventional path.
    if [ -d "$HOME/Applications/Claude-Tide.app" ]; then
        fail "app built a second applet instead of adopting the existing one"
    fi
}

case_app_refuses_when_two_launchers_pin_one_root() {
    desktop_fixture
    fixture_applet "$HOME/Desktop/Tide-Claude.app" "$(tide_line)"
    fixture_applet "$HOME/Desktop/Tide-Copy.app" "$(tide_line)"

    out=$(desk app tide 2>&1); status=$?
    assert_status 1 "$status" "$out" || return
    assert_contains "$out" "Tide-Claude.app" || return
    assert_contains "$out" "Tide-Copy.app" || return
    assert_contains "$out" "--applet"
}

case_app_falls_back_to_the_conventional_path() {
    desktop_fixture
    out=$(desk app tide 2>&1)
    assert_contains "$out" "Created" || return
    assert_not_contains "$out" "adopted it" || return
    assert_equals "$HOME/Applications/Claude-Tide.app" "$(reg_applet_of tide)"
}

case_explicit_applet_wins_over_the_scan() {
    desktop_fixture
    fixture_applet "$HOME/Desktop/Tide-Claude.app" "$(tide_line)"
    out=$(desk app tide --applet "$HOME/Applications/Chosen.app" 2>&1)
    assert_contains "$out" "Chosen.app" || return
    assert_not_contains "$out" "adopted it" || return
    assert_equals "$HOME/Applications/Chosen.app" "$(reg_applet_of tide)"
}

# The hint used to be built from root_prefix, whose glob ".claude-*" excludes
# "~/.claude" -- the one place every unpinned session lands, and so the single
# most important directory the leak test has to see.
case_the_leak_test_hint_covers_the_default_root() {
    desktop_fixture
    out=$(desk app tide 2>&1)
    # shellcheck disable=SC2016  # the literal text the hint must print
    assert_contains "$out" '"$HOME"/.claude* -name' || return
    # shellcheck disable=SC2016  # the literal text it must not print
    assert_not_contains "$out" '"$HOME"/.claude-* -name'
}

run_case "desktop puts --env before --args"           case_desktop_puts_env_before_args
run_case "desktop passes extra args through"          case_desktop_passes_extra_args_through
run_case "desktop does not export the variable"       case_desktop_does_not_export_the_variable
run_case "desktop refuses an open without --env"      case_desktop_refuses_an_open_without_env
run_case "desktop refuses when the app is absent"     case_desktop_refuses_when_the_app_is_absent
run_case "app creates an applet and registers it"     case_app_creates_an_applet_and_registers_it
run_case "app is idempotent and says so"              case_app_is_idempotent_and_says_so
run_case "app repairs a wrong root, keeps the icon"   case_app_repairs_a_wrong_root_and_keeps_the_icon
run_case "app refuses a bundle that is not an applet" case_app_refuses_a_bundle_that_is_not_an_applet
run_case "app rejects an uncarryable root"            case_app_rejects_a_root_the_launch_line_cannot_carry
run_case "the icon installs, original kept once"      case_icon_is_installed_and_the_original_kept_once
run_case "the icon reports a missing source image"    case_icon_reports_a_missing_source_image
run_case "D13 reports an unpinned launcher"           case_d13_reports_an_unpinned_launcher
run_case "D13 reports --env after --args"             case_d13_reports_env_after_args
run_case "D13 reports the wrong root"                 case_d13_reports_the_wrong_root
run_case "D13 reports the wrong app data dir"         case_d13_reports_the_wrong_app_data_dir
run_case "D13 quiet on a correct applet"              case_d13_quiet_on_a_correct_applet
run_case "D13 quiet when there is no applet"          case_d13_quiet_when_there_is_no_applet
run_case "D13 quiet on a hand-tuned correct line"     case_d13_quiet_on_a_hand_tuned_but_correct_line
run_case "verify is broken without --env support"     case_verify_is_broken_without_env_support
run_case "verify passes with --env support"           case_verify_passes_with_env_support
run_case "verify reports on the applet reader"        case_verify_reports_on_the_applet_reader
run_case "a registry without applet= still works"     case_registry_without_an_applet_key_still_works
run_case "explain names both identities"              case_explain_names_both_identities
run_case "the scan finds an applet five levels down" case_scan_finds_an_applet_five_levels_down
run_case "the scan ignores bundles that are not ours" case_scan_ignores_bundles_that_are_not_ours
run_case "D14 names the profile owning the root"    case_d14_names_the_profile_owning_the_root
run_case "D14 reports a launcher nobody owns"       case_d14_reports_a_launcher_no_profile_owns
run_case "D14 quiet once the applet is registered"  case_d14_quiet_once_the_applet_is_registered
run_case "D13 and D14 can both fire"                case_d13_and_d14_can_both_fire
run_case "app adopts a launcher outside ~/Applications" case_app_adopts_a_launcher_outside_the_conventional_dir
run_case "app refuses two launchers for one root"   case_app_refuses_when_two_launchers_pin_one_root
run_case "app falls back to the conventional path"  case_app_falls_back_to_the_conventional_path
run_case "an explicit --applet wins over the scan"  case_explicit_applet_wins_over_the_scan
run_case "the leak test hint covers the default root" case_the_leak_test_hint_covers_the_default_root
