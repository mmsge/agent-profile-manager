# Troubleshooting

Every message below is what the tool prints, with the cause and the fix.
The messages are generated from real runs, so they are current; two that
need a real Mac to produce are marked as illustrative and quoted from the
source. Each refusal is a rule of the tool rather than a bug, and the fix is
never to work around it.

## "Refusing to run claude unpinned."

<!-- BEGIN GENERATED: example guard-refusal (tools/gen-doc-examples.sh) -->
```sh
eval "$(agpin guard)"
claude
```

```
Refusing to run claude unpinned.
Nothing is pinned, so this would write to the default root,
under whichever account last logged in there.

Name one to use it, for example: claude <profile> [args...]

Profiles on this machine:
  brygga
  havnelab

Or pin the shell: eval "$(agpin env <profile>)"
Override:         command claude [args...]
```
<!-- END GENERATED: example guard-refusal -->

Cause: nothing is pinned in this shell, and the `guard` function from
`eval "$(agpin guard)"` caught it before `claude` ran unpinned.

Fix: name a profile (`claude brygga`), pin the shell first
(`eval "$(agpin env brygga)"`), or use `command claude` if you genuinely mean
to run unpinned once. An agent setting up a machine never uses the override;
see [the setup guide](SETUP.md#if-you-are-an-agent-doing-this-for-someone).

## "no such profile '\<name\>' (try: agpin list)"

<!-- BEGIN GENERATED: example err-no-such-profile (tools/gen-doc-examples.sh) -->
```sh
agpin run bryga
```

```
agpin: no such profile 'bryga' (try: agpin list)
```
<!-- END GENERATED: example err-no-such-profile -->

Cause: a typo, or the profile was never created.

Fix: `agpin list` to see the exact names, then `agpin new <name>` if it really
does not exist yet.

## "unknown command or profile '\<word\>'"

<!-- BEGIN GENERATED: example err-unknown-command (tools/gen-doc-examples.sh) -->
```sh
agpin dotcor
```

```
agpin: unknown command or profile 'dotcor'
Try: agpin help for commands, or agpin list for profiles.
```
<!-- END GENERATED: example err-unknown-command -->

Cause: the first word is neither a subcommand nor a registered profile. A
bare profile name is short for `run`, so the two are looked up in that order.

Fix: `agpin help` for the commands, `agpin list` for the profiles.

## "the 'claude' command is not on your PATH"

<!-- BEGIN GENERATED: example err-claude-not-on-path (tools/gen-doc-examples.sh) -->
```sh
agpin run brygga
```

```
agpin: the 'claude' command is not on your PATH
```
<!-- END GENERATED: example err-claude-not-on-path -->

Cause: `run`, `shell` and the guard all check for the agent's binary before
pinning it, and Claude Code is not installed or not on `PATH` in this shell.

Fix: install Claude Code, or fix `PATH`. `new` in the same state still
creates the profile, and says the sessions server was not registered; run
`agpin mcp on <name>` once `claude` is on `PATH`.

## "required command 'python3' not found"

<!-- BEGIN GENERATED: example err-no-python3 (tools/gen-doc-examples.sh) -->
```sh
agpin new brygga
```

```
agpin: required command 'python3' not found
agpin new uses python3 to canonicalise the root path, which is the
string this profile's credential is keyed on. On macOS python3 comes with the
Command Line Tools: xcode-select --install
That download is several gigabytes and this is the one prerequisite this tool
cannot avoid.
```
<!-- END GENERATED: example err-no-python3 -->

Cause: every command that reads JSON uses `python3`, and a Mac that has never
had Xcode or the Command Line Tools has none. `new` is where a fresh machine
meets that first, because it canonicalises the root path before creating it;
`list`, `doctor`, `remove` and `verify` refuse the same way.

Fix: `xcode-select --install`. It is a several gigabyte download and the one
prerequisite this tool cannot avoid. `uv` does not help here: it brings its
own Python for the sessions server and puts nothing on your `PATH`.

## "profile '\<name\>' is already registered with root '...'. Refusing to repoint it..."

<!-- BEGIN GENERATED: example err-already-registered (tools/gen-doc-examples.sh) -->
```sh
agpin new brygga --root ~/.claude-brygga-2
```

```
agpin: profile 'brygga' is already registered with root '/Users/alex/.claude-brygga'.
Refusing to repoint it: credentials are keyed to the root path, so changing it
would invalidate that profile's login. Remove /Users/alex/.config/agent-profiles/brygga.conf by hand
if you really mean to start over.
```
<!-- END GENERATED: example err-already-registered -->

Cause: `new` was run again for an existing profile name with a different
`--root`. Credentials are keyed to the root path (docs/FACTS.md F09), so
repointing would invalidate that profile's login.

Fix: pick a new name for the other root, or remove the registry entry named in
the message by hand if you really do mean to start over. Running `new` again
with the same root, or with none, is safe and says so:

<!-- BEGIN GENERATED: example new-again (tools/gen-doc-examples.sh) -->
```sh
agpin new brygga
```

```
Profile brygga is already registered.
Sessions server: on (already registered in /Users/alex/.claude-brygga/.claude.json)
That root already held data, so it was adopted rather than created: 0 session(s).
Next: agpin doctor    (audit the isolation)
```
<!-- END GENERATED: example new-again -->

## "--root must be an absolute path..."

<!-- BEGIN GENERATED: example err-root-relative (tools/gen-doc-examples.sh) -->
```sh
agpin new brygga --root relative/path
```

```
agpin: --root must be an absolute path, because the credential is keyed
on the literal path string. Got: relative/path
```
<!-- END GENERATED: example err-root-relative -->

Cause: `--root` was given a relative path.

Fix: pass an absolute path.

## "the desktop app is not installed at /Applications/Claude.app"

<!-- illustrative: producing this needs a Mac without the desktop app; the text is quoted from bin/agent-profile -->
```
agpin: the desktop app is not installed at /Applications/Claude.app
```

Cause: `desktop` and `app` need Claude Desktop at the conventional path before
they can pin it.

Fix: install Claude Desktop, or if it genuinely lives elsewhere set
`AGENT_PROFILE_APP_BUNDLE=/path/to/Claude.app` before running the command.

## "this open(1) does not support --env..."

<!-- illustrative: producing this needs a Mac whose open(1) has lost --env; the text is quoted from bin/agent-profile -->
```
agpin: this open(1) does not support --env, so the app cannot be pinned.
Launching it anyway would start an unpinned session writing to the default
root, which is the leak this tool exists to prevent, so nothing was launched.
See docs/FACTS.md F13.
```

Cause: macOS `open` no longer supports `--env` (docs/FACTS.md F13), and
without it nothing can pin the desktop app.

Fix: none from this tool. Run `agpin verify` to confirm; see
[After a Claude Code update](AUDIT.md#after-a-claude-code-update).

## "N launchers already pin profile '\<name\>': ..."

<!-- BEGIN GENERATED: example err-two-launchers (tools/gen-doc-examples.sh) -->
```sh
agpin app brygga
```

```
agpin: 2 launchers already pin profile 'brygga':

  /Users/alex/Applications/Claude-Brygga.app
  /Users/alex/Desktop/Brygga2.app

Refusing to guess which one is canonical, because repairing the wrong one
rewrites a file you did not name. Say which with --applet, and remove or
re-point the other so doctor stops reporting it as D14.
```
<!-- END GENERATED: example err-two-launchers -->

Cause: `app` found more than one existing launcher that already pins this
profile's root, and refuses to guess which is canonical.

Fix: pass `--applet PATH` to say which one, and remove or repoint the other so
`doctor`'s D14 stops reporting it.

## "... exists but is not an AppleScript applet: no compiled script inside it."

<!-- BEGIN GENERATED: example err-not-an-applet (tools/gen-doc-examples.sh) -->
```sh
agpin app brygga --applet ~/NotAnApplet.app
```

```
Repairing /Users/alex/NotAnApplet.app: it is not an AppleScript applet: there is no compiled script inside it.
agpin: /Users/alex/NotAnApplet.app exists but is not an AppleScript applet: no compiled script inside it.
Refusing to overwrite it. Remove it, or pass --applet with another path.
```
<!-- END GENERATED: example err-not-an-applet -->

Cause: the path at `--applet`, or the conventional default path, exists but is
not a bundle `app` can repair, so it refuses to overwrite something it does
not understand. The first line says what it was about to repair; the refusal
follows before anything is written.

Fix: remove it, or pass `--applet` with a different path.

## "... contains a character the launch line cannot carry safely: ..."

<!-- BEGIN GENERATED: example err-unsafe-character (tools/gen-doc-examples.sh) -->
```sh
agpin app weird
```

```
agpin: the app data directory contains a character the launch line cannot carry safely: /Users/alex/Library/Application Support/Weird$Name
The applet nests a shell command inside an AppleScript string, so a quote,
backslash, dollar or backtick in this path would need to survive two layers of
quoting. Choose a path without them.
```
<!-- END GENERATED: example err-unsafe-character -->

Cause: the config root or app data path contains a quote, backslash, dollar
sign or backtick. The applet nests a shell command inside an AppleScript
string literal, so a character like that would need to survive two layers of
quoting.

Fix: choose a root or app data path without that character; `new --root` and
`--app-data` accept any other path you like.

## A doctor finding

Every finding names the rule, the offending path and the fix, and
[The audit](AUDIT.md#the-rules) lists what each rule means. The findings a
machine that ran unpinned commonly produces, D01, D02, D06, D09 and D14, are
walked through one by one in
[the setup guide](SETUP.md#what-the-first-doctor-run-tells-you); the ones
`remove` leaves behind are in [When an engagement ends](OFFBOARDING.md).
