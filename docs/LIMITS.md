# What this does not protect against

This tool closes the gaps a hand-maintained setup accumulates on its own. It
does not close every way a shell or a desktop can end up running `claude`
unpinned. Know what is still open, one honest paragraph each. The drawing in
[The desktop and the IDEs](DESKTOP.md#the-launch-paths) shows the same list as
launch paths, with the rule that catches each.

- **The `claude-cli://` URL handler.** LaunchServices launches it with no
  environment at all, so a clicked link always opens against the default root
  regardless of what is pinned; `doctor`'s D09 flags that the handler is
  installed, and the only mitigation is to open the project from a pinned
  shell instead of clicking the link.
- **An IDE opened any way but `agpin code` or `agpin idea`.** The Claude Code
  extension takes its config root from the IDE's own process environment, so
  an IDE started from the Dock, Spotlight, Launchpad or a login item runs its
  extension unpinned and every session in it writes to the default root;
  those two commands are the only launches that carry a root, `doctor`'s D16
  reports that an extension is installed, and `docs/FACTS.md` F19 to F21
  record what each family does. Both pin through `open --env`, so off macOS
  neither exists: there the only way to carry a root into an editor is to
  start it from a shell that is already pinned, with `agpin shell <profile>`
  or `eval "$(agpin env <profile>)"`, which is what D16 says on that
  platform.
- **An IDE extension pinned by its own settings rather than by its launch.**
  VS Code's `claudeCode.environmentVariables` does reach the agent the
  extension spawns, but not the extension's own config home, so its settings,
  plans, session registry and lock file stay on the default root; the JetBrains
  plugin's **Config directory** setting pins nothing at all and only chooses
  where the plugin writes its lock file. Pin the launch, not the setting.
- **Direct launches of the desktop app from Spotlight, Launchpad, the Dock or
  login items.** Only the generated applet's `open --env` line injects a
  config root, so launching `Claude.app` itself by any other route starts it
  unpinned; put the applet, not the app, in the Dock and in login items.
  `doctor`'s D17 reports the app's own icon sitting in the Dock and D18 reports
  the default app data directory once such a launch has written to it, but
  neither can see the login items: listing those needs root or an Automation
  consent dialogue, and `docs/FACTS.md` F22 records why.
- **`command claude`, which is the guard's own escape hatch.** It is
  documented and deliberate, on the theory that an escape hatch you can see
  beats one people find by deleting the guard from their rc file, but it also
  means the guard is not a hard lock: anyone who knows this can bypass it at
  will.
- **Scripts and cron jobs that call `claude`.** They do not source your
  interactive rc file, so the `guard` function was never defined in that
  process; a script that needs isolation has to export `CLAUDE_CONFIG_DIR`
  itself.
- **MCP servers or other tools that spawn the CLI.** The same mechanism as the
  two points above: anything that execs the `claude` binary directly, rather
  than going through a pinned shell, bypasses the guard and pins nothing on
  its own.
- **Roots outside `~/.claude-*` that D06 cannot see.** D06 looks for the
  conventional prefix plus the default root; a root created at an
  unconventional `--root` path is only audited once a profile claims it, so an
  unclaimed root at an unconventional path stays invisible until then.
- **Per-command pins, which the prompt label cannot show.** `CLAUDE_CONFIG_DIR=…
  claude` pins that one invocation without ever touching the shell's own
  environment, so `which --label` and the rc-file prompt keep showing whatever
  the shell was already pinned to, or nothing; run `agpin which` for the true
  state of the invocation you are about to make, not the prompt.
- **A profile that owns the default root.** Register an account at
  `~/.claude` and `doctor` can no longer tell an unpinned run from that
  profile's own work, because on disk the two are identical; D01 goes quiet
  for good and only D02 and D03 still watch. `new` says so when you do it, and
  [the setup guide](SETUP.md#part-2-a-machine-that-has-run-unpinned) shows the
  note.
- **Windows.** The tool is a bash script written for macOS paths and macOS
  mechanisms (Keychain, `open`, AppleScript applets); none of it runs on
  Windows, so a machine used from both platforms gets no isolation from this
  tool at all on the Windows side. [Install](INSTALL.md#windows) has the
  status of a port.

## Three things that are not what they look like

Pinning to the default root is not the same as not pinning, a config root can
never be moved or renamed once it has a login, and the desktop app naming an
account is not evidence that anything is pinned. Each of those is worth
reading in full, because each one has cost someone real time:
[Three things that are not what they look like](DESIGN.md#three-things-that-are-not-what-they-look-like).

In one line each, for the reader in a hurry:

- Setting `CLAUDE_CONFIG_DIR=~/.claude` produces a different layout from
  leaving it unset, because the state file moves inside the root, and a
  different login, because the credential's name gains a suffix. `doctor`
  never treats the two as equivalent, and D11 reports the second.
- Credentials are keyed to the root path, so a root at a new path reads a
  different Keychain entry and a different `.credentials.json`. There is no
  `rename` and no `move`, and `new` refuses to repoint an existing profile.
  Create a new profile instead.
- The app's own login and the config root its embedded Claude Code writes to
  are two independent identities, and they have been seen disagreeing for
  weeks. Read both, which is what `agpin explain` prints and what D13 checks,
  and run [the leak test](AUDIT.md#the-leak-test) when in doubt.
