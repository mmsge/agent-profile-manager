# Agent Profile Manager

`agent-profile` keeps several AI agent accounts separate on one Mac, and audits
that the separation actually holds.

Claude Code has no built-in account switcher. The only mechanism for keeping two
accounts apart is giving each its own config root, selected by the
`CLAUDE_CONFIG_DIR` environment variable. Doing that by hand works right up
until it does not: a copy-paste slip labels one account's sessions as another's,
one root gets pinned to the *default* root and quietly overloads it, and the
desktop app never gets pinned at all. This tool removes the hand-maintained
duplication rather than adding a layer on top of it.

## Ten-minute start

Five steps, on a Mac with Claude Code already installed.

**1. Install it.**

```sh
tools/install.sh
```

```
Installed /Users/alex/.local/bin/agpin -> /path/to/agent-profile/bin/agent-profile
Installed /Users/alex/.local/bin/agent-profile -> /path/to/agent-profile/bin/agent-profile

WARNING: /Users/alex/.local/bin is not on your PATH, so the command will not be found.
Add this to your shell rc file:
  export PATH="/Users/alex/.local/bin:$PATH"

Next:
  agpin help
  agpin doctor

Worth adding to your shell rc file:
  eval "$(agpin guard)"      # refuse to run the agent unpinned
  PROMPT='$(agpin which --label 2>/dev/null) %~ %# '
```

If `~/.local/bin` is already on your `PATH`, the warning is replaced by a line
saying so instead. See [Install](#install) for `--prefix` and `--name`.

**2. Create one profile per account.**

```sh
agpin new bouvet
```

```
Created profile bouvet
  agent     claude
  root      /Users/alex/.claude-bouvet
  app data  /Users/alex/Library/Application Support/Claude-Bouvet

The root is empty, which is the point: nothing is shared between profiles.
That also means it has no settings, no hooks and none of the guardrails your
other profiles may have. Set those up here directly; do not copy them across.

Next: agent-profile run bouvet   (it will ask you to log in)
```

Do that once per account, for example `agpin new highsoft`. Then sign in to
each: `agpin run bouvet`, `agpin run highsoft`.

**3. Add two lines to your shell rc file.**

```sh
eval "$(agpin guard)"
PROMPT='$(agpin which --label 2>/dev/null) %~ %# '
```

The first refuses to run `claude` with nothing pinned. The second shows which
profile a pinned shell is using, so a prompt can never claim the wrong account.
Open a new shell, or `source` the rc file, before the next step.

**4. Check the separation actually holds.**

```sh
agpin doctor
```

```
No isolation problems found across 2 profile(s).
```

If it finds something instead, each finding names the rule and the offender
and says how to fix it; see [Troubleshooting](#troubleshooting) if the fix
itself is not obvious.

**5. Pin the desktop app.**

```sh
agpin app bouvet
```

```
Created /Users/alex/Applications/Claude-Bouvet.app
  pins      CLAUDE_CONFIG_DIR=/Users/alex/.claude-bouvet
  app data  /Users/alex/Library/Application Support/Claude-Bouvet

Confirm it actually pins, by starting a Code session in the app and running:
  find "$HOME"/.claude* -name "*.jsonl" -mmin -3
The path it prints is the root that is really in use.
```

Drag the generated `.app` into the Dock. Repeat per account, then run it again
any time to confirm nothing has drifted; a second run on an already-correct
applet says so rather than rebuilding it.

That covers a clean machine. `agpin` with no arguments asks which profile and
whether to open the terminal or the desktop app, which is worth doing instead
of typing the full command every time; see [Just asking](#just-asking).

## Moving a machine you already use

Everything above assumes a fresh account. Most machines are not that: Claude
Code has usually been running unpinned for a while already, with sessions
piling up in the default root and the desktop app opening whatever account it
last opened.

**Register what already exists first.** `new` on a root that already exists
and holds data adopts it rather than creating it. Nothing is copied, moved,
seeded or removed; the only change is that the root and its app data directory
become mode 700. Point it at what you already have:

```sh
agent-profile new tide --root ~/.claude-tide \
    --app-data ~/Library/Application\ Support/Claude-Tide
```

It says which of the two it did, and reports the session count it found, so
"adopted your live root" and "made you an empty one" can never be confused.
Check with `agent-profile list` that each profile names the account you expect
before trusting `doctor`.

**What the first `doctor` run tells you.** Registering even one new profile is
enough to make `doctor` start reporting the residue of the old, unpinned use,
because it can now compare what it finds against a registry instead of finding
nothing to compare against. On a machine that has run unpinned for months, a
first run commonly looks like this, once one new account (`bouvet`) is
registered:

```
D01  the default claude root holds 1 session(s)
     /Users/alex/.claude
     Something ran without a profile pinned and wrote here.
     Note that pinning to the default root is not the same as not pinning:
     the state file moves inside the root when the variable is set.

D02  a stray claude state file sits outside every profile root
     /Users/alex/.claude.json
     account: alex@personal.example
     This file is written when nothing is pinned. It holds an account,
     per-project trust decisions and personal MCP servers for whichever
     account last ran unpinned, which need not be any profile here.

D06  a claude config root exists that no profile claims
     /Users/alex/.claude-tide
     Register it, or remove it if it is left over.
     Unregistered roots are invisible to every other check here.

D14  a desktop launcher for profile 'bouvet' is not registered
     /Users/alex/Desktop/Claude Work.app
     It pins /Users/alex/.claude-bouvet, which profile 'bouvet' owns, but no profile
     names this applet, so the launcher audit has never read it.
     An unregistered launcher is invisible to every other check here.
     Fix with: agent-profile app bouvet --applet '/Users/alex/Desktop/Claude Work.app'

D09  a claude-cli:// handler is installed and cannot be pinned
     /Users/alex/Applications/Claude Code URL Handler.app
     LaunchServices passes no environment, so a deep link opens against the
     default root whatever this tool has configured. Treat links as a leak
     path: open the project through a pinned shell instead of clicking them.

5 finding(s).
```

Five different kinds of residue, and each is resolved differently:

- **D06**, the leftover `~/.claude-tide` root, is resolved exactly as in the
  first step above: `agent-profile new tide --root ~/.claude-tide` adopts it.
  Once a profile claims it, D06 stops reporting it.

- **D14**, the launcher already sitting on the Desktop from before this tool
  existed, is resolved by pointing the profile at it instead of building a
  second one: `agent-profile app bouvet --applet '~/Desktop/Claude Work.app'`.
  `app` finds this launcher on its own the next time it runs without
  `--applet`, since it searches `~/Desktop` as well as `~/Applications` for
  exactly this reason; see [D14](#the-audit).

- **D01 and D02** both trace back to the same account: whoever has been using
  Claude Code unpinned on this machine. There are two ways to resolve D01, and
  they are not equivalent. If that unpinned use is genuinely stray and nobody's
  account, stop running unpinned (the guard from step 3 above prevents new
  instances) and leave the old data alone or clean it up by hand. If it is
  actually one of your accounts, running unpinned because nobody had pinned it
  yet, register it at the default root:

  ```sh
  agent-profile new main --root ~/.claude
  ```

  An account living in the **default** root is a supported case: register it
  with `--root ~/.claude` and `doctor` will stop reporting that root as an
  unpinned leak, because a profile now claims it. It is still a different
  login from running unpinned, and D11 still says so.

  It costs you D01 permanently, though, and `new` says so when you do it. An
  unpinned run writes to that same root in the same layout, so on disk it is
  indistinguishable from that profile's own work. D02 and D03 become the only
  rules still watching unpinned use, and moving the root to recover D01 is not
  an option because that invalidates the login. The real guard is never
  running the agent unpinned at all. Here is that note, verbatim:

  ```
  NOTE: this profile owns the default root.

  Anything that runs with nothing pinned writes to that same root, in the same
  layout, so from now on doctor cannot tell an unpinned run apart from this
  profile's own. D01 goes quiet for good. It is not a bug and there is no
  setting for it: on disk the two are identical.

  What still watches unpinned use:
    D02  the state file beside the root, which names whichever account last
         ran unpinned and need not be any profile here
    D03  the same project appearing under two roots

  This cannot be undone by moving the root: credentials are keyed to the root
  path, so relocating it invalidates this login (docs/FACTS.md F06). The real
  guard is never running the agent unpinned in the first place.
  ```

  D02 itself has no command that resolves it: the stray state file just says
  which account last ran unpinned, and once every account is pinned and the
  guard is in your rc file, nothing new writes there. Removing the old file by
  hand is safe, but this tool never does it for you, the same way it never
  touches any other credential or state file.

- **D09** has no fix from this tool at all: it is a standing fact about the
  `claude-cli://` handler, not something adopting a root or a launcher changes.
  See [What this does not protect against](#what-this-does-not-protect-against).

After resolving what can be resolved, a second `doctor` run on the same
machine settles into the two findings that are permanent, plus whatever your
own accounts still need to sign in:

```
D02  a stray claude state file sits outside every profile root
     /Users/alex/.claude.json
     account: alex@personal.example
     This file is written when nothing is pinned. It holds an account,
     per-project trust decisions and personal MCP servers for whichever
     account last ran unpinned, which need not be any profile here.

D09  a claude-cli:// handler is installed and cannot be pinned
     /Users/alex/Applications/Claude Code URL Handler.app
     LaunchServices passes no environment, so a deep link opens against the
     default root whatever this tool has configured. Treat links as a leak
     path: open the project through a pinned shell instead of clicking them.

2 finding(s).
```

That is not a bug in the tool; it is the honest state of a machine that has
run unpinned before and still has a URL handler installed. Nothing left in
that list is silently wrong, which is the entire point of running `doctor` in
the first place.

## What this does not protect against

This tool closes the gaps a hand-maintained setup accumulates on its own. It
does not close every way a shell or a desktop can end up running `claude`
unpinned. Know what is still open, one honest sentence each:

- **The `claude-cli://` URL handler.** LaunchServices launches it with no
  environment at all, so a clicked link always opens against the default root
  regardless of what is pinned; `doctor`'s D09 flags that the handler is
  installed, and the only mitigation is to open the project from a pinned
  shell instead of clicking the link.
- **IDE extensions that spawn the CLI from the IDE process.** An extension
  that execs `claude` directly, rather than through your shell, never passes
  through the `guard` function, so it runs with whatever `CLAUDE_CONFIG_DIR`
  the IDE's own process happens to have, usually none; check the extension's
  own environment settings if it needs to be pinned.
- **Direct launches of the desktop app from Spotlight, Launchpad, the Dock or
  login items.** Only the generated applet's `open --env` line injects a
  config root, so launching `Claude.app` itself by any other route starts it
  unpinned; put the applet, not the app, in the Dock and in login items.
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
  the shell was already pinned to, or nothing; run `agent-profile which` for
  the true state of the invocation you are about to make, not the prompt.
- **Windows.** The tool is a bash script written for macOS paths and macOS
  mechanisms (Keychain, `open`, AppleScript applets); none of it runs on
  Windows, so a machine used from both platforms gets no isolation from this
  tool at all on the Windows side.

## Troubleshooting

Every message below is quoted from the tool, with the cause and the fix.

**"Refusing to run claude unpinned."**

```
Refusing to run claude unpinned.
Nothing is pinned, so this would write to the default root,
under whichever account last logged in there.

Name one to use it, for example: claude <profile> [args...]

Profiles on this machine:
  bouvet

Or pin the shell: eval "$(agpin env <profile>)"
Override:         command claude [args...]
```

Cause: nothing is pinned in this shell, and the `guard` function from
`eval "$(agpin guard)"` caught it before `claude` ran unpinned.

Fix: name a profile (`claude bouvet`), pin the shell first
(`eval "$(agpin env bouvet)"`), or use `command claude` if you genuinely mean
to run unpinned once.

**"no such profile '\<name\>' (try: agent-profile list)"**

```
agent-profile: no such profile 'boouvet' (try: agent-profile list)
```

Cause: a typo, or the profile was never created.

Fix: `agent-profile list` to see the exact names, then
`agent-profile new <name>` if it really does not exist yet.

**"the 'claude' command is not on your PATH"**

```
agent-profile: the 'claude' command is not on your PATH
```

Cause: `run`, `shell` and the guard all check for the agent's binary before
pinning it, and Claude Code is not installed or not on `PATH` in this shell.

Fix: install Claude Code, or fix `PATH`.

**"profile '\<name\>' is already registered with root '...'. Refusing to
repoint it..."**

```
agent-profile: profile 'bouvet' is already registered with root '/Users/alex/.claude-bouvet'.
Refusing to repoint it: credentials are keyed to the root path, so changing it
would invalidate that profile's login. Remove /Users/alex/.config/agent-profiles/bouvet.conf by hand
if you really mean to start over.
```

Cause: `new` was run again for an existing profile name with a different
`--root`. Credentials are keyed to the root path (docs/FACTS.md F09), so
repointing would invalidate that profile's login.

Fix: pick a new name for the other root, or remove the registry entry named in
the message by hand if you really do mean to start over.

**"--root must be an absolute path..."**

```
agent-profile: --root must be an absolute path, because the credential is keyed
on the literal path string. Got: relative/path
```

Cause: `--root` was given a relative path.

Fix: pass an absolute path.

**"the desktop app is not installed at /Applications/Claude.app"**

```
agent-profile: the desktop app is not installed at /Applications/Claude.app
```

Cause: `desktop` and `app` need Claude Desktop at the conventional path before
they can pin it.

Fix: install Claude Desktop, or if it genuinely lives elsewhere set
`AGENT_PROFILE_APP_BUNDLE=/path/to/Claude.app` before running the command.

**"this open(1) does not support --env..."**

```
agent-profile: this open(1) does not support --env, so the app cannot be pinned.
Launching it anyway would start an unpinned session writing to the default
root, which is the leak this tool exists to prevent, so nothing was launched.
See docs/FACTS.md F13.
```

Cause: macOS `open` no longer supports `--env` (docs/FACTS.md F13), and
without it nothing can pin the desktop app.

Fix: none from this tool. Run `agent-profile verify` to confirm; see
[What to do after a Claude Code update](#what-to-do-after-a-claude-code-update).

**"N launchers already pin profile '\<name\>': ..."**

```
agent-profile: 2 launchers already pin profile 'bouvet':

  /Users/alex/Applications/Claude-Bouvet.app
  /Users/alex/Desktop/Bouvet2.app

Refusing to guess which one is canonical, because repairing the wrong one
rewrites a file you did not name. Say which with --applet, and remove or
re-point the other so doctor stops reporting it as D14.
```

Cause: `app` found more than one existing launcher that already pins this
profile's root, and refuses to guess which is canonical.

Fix: pass `--applet PATH` to say which one, and remove or repoint the other so
`doctor`'s D14 stops reporting it.

**"... exists but is not an AppleScript applet: no compiled script inside
it."**

```
agent-profile: /Users/alex/NotAnApplet.app exists but is not an AppleScript applet: no compiled script inside it.
Refusing to overwrite it. Remove it, or pass --applet with another path.
```

Cause: the path at `--applet`, or the conventional default path, exists but is
not a bundle `app` can repair, so it refuses to overwrite something it does
not understand.

Fix: remove it, or pass `--applet` with a different path.

**"... contains a character the launch line cannot carry safely: ..."**

```
agent-profile: the app data directory contains a character the launch line cannot carry safely: /Users/alex/Library/Application Support/Weird$Name
The applet nests a shell command inside an AppleScript string, so a quote,
backslash, dollar or backtick in this path would need to survive two layers of
quoting. Choose a path without them.
```

Cause: the config root or app data path contains a quote, backslash, dollar
sign or backtick. The applet nests a shell command inside an AppleScript
string literal, so a character like that would need to survive two layers of
quoting.

Fix: choose a root or app data path without that character; `new --root` and
`--app-data` accept any other path you like.

## What a profile is

It is named for agents rather than for Claude because the same problem will
arrive with ollama, codex and whatever comes next. Claude is the only agent
implemented today.

One profile is one account, and it owns two directories:

| | |
| --- | --- |
| **Config root** | `~/.claude-<name>`, the value of `CLAUDE_CONFIG_DIR` |
| **App data dir** | `~/Library/Application Support/Claude-<Name>`, the value of `--user-data-dir` |

The config root holds everything the agent stores: settings, session
transcripts, auto memory, commands, skills, agents, plugins, plans, backups, the
credential and the state file. Two profiles therefore share no file at all.
Nothing is ever shared between two config roots, on purpose and without
exception; the reasoning is in
[Why nothing is shared](docs/DESIGN.md#why-nothing-is-shared).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh | bash
```

That downloads the newest tagged release, checks it against the `SHA256SUMS`
published beside it, checks the Sigstore signature if you have `cosign`,
unpacks it into `~/.local/share/agent-profile/<version>/` and links both
`agpin` and `agent-profile` at that copy. What runs in your shell then changes
only when you run the installer again.

Install `cosign` first if you want the signature checked, and you do:

```sh
brew install cosign
```

**The tool names itself by whichever name you invoke.** Run it as `agpin` and
every message, error and suggested fix says `agpin`. That matters because a
finding telling you to run a command not on your `PATH` is worse than no
suggestion at all.

Two lines worth adding to your shell rc file:

```sh
eval "$(agpin guard)"
PROMPT='$(agpin which --label 2>/dev/null) %~ %# '
```

No dependencies beyond a stock macOS. It is one bash script, written to bash
3.2 because that is what `/bin/bash` is on macOS, and it uses `python3` from the
Command Line Tools only to read JSON. No Homebrew, no `jq`.

Installing adds nothing to that: `curl`, `shasum` and `tar` are on every Mac,
and neither `tools/install.sh` nor `agpin version --check` calls `python3`,
because on a fresh Mac that opens the Command Line Tools dialog and an
installer is the worst place to meet it. `cosign` is the one optional piece,
and the only thing that goes unchecked without it is the signature.

### What you are trusting, step by step

The one-liner runs whatever `tools/install.sh` holds on `hovud` at the moment
you run it, so that one file is trusted on GitHub's word alone. Read it first
if you would rather not:

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh
less install.sh
bash install.sh
```

Everything after that first file is checked rather than trusted.

**The tarball comes from a tag, not a branch.** A release is built by
`.github/workflows/release.yml`, which runs the same tests a branch runs,
refuses to publish when the tag and the version in `bin/agent-profile`
disagree, and attaches the tarball, its `SHA256SUMS` and a Sigstore bundle for
each.

**The checksum is verified before anything is unpacked.** A mismatch stops the
install and leaves nothing behind, so a truncated download or an altered
tarball cannot become a half-installed command.

**The signature is verified when `cosign` is installed.** The Sigstore
certificate names the workflow, the repository and the tag that produced the
file, so a release swapped by somebody who can push to this repository fails
the check rather than installing quietly. Keyless: there is no public key to
fetch and no private key anyone can steal.

**Without `cosign` the installer says so, loudly, and names what went
unchecked.** A checksum on its own proves the download is intact and nothing
more: whoever served `SHA256SUMS` served the tarball too, so changing both
passes. That warning is the difference between a verified install and one that
looks like one.

Verifying by hand, if you want to see it work:

```sh
shasum -a 256 -c SHA256SUMS
cosign verify-blob \
    --bundle agent-profile-0.7.1.tar.gz.sigstore \
    --certificate-identity-regexp '^https://github\.com/mmsge/agent-profile-manager/\.github/workflows/release\.yml@refs/tags/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    agent-profile-0.7.1.tar.gz
```

### Homebrew

```sh
brew tap mmsge/agpin
brew install agpin
```

The formula pins one tarball's `sha256`, so Homebrew refuses anything that does
not match it. That moves the trust from a branch to the tap repository, which
is an improvement and not the end of it: whoever can push to the tap can change
the URL and the sum together. The Sigstore check is the one that survives that.
See [`packaging/homebrew/README.md`](packaging/homebrew/README.md).

### Options

```sh
tools/install.sh --version v0.7.1   # a named release rather than the newest
tools/install.sh --prefix ~/bin     # where the two links go
tools/install.sh --name apx         # a different short command name
tools/install.sh --uninstall        # remove the links, and nothing else
tools/install.sh --dev              # link a git checkout instead
```

`--version` never asks the API which release is newest, so it is what you want
in anything scripted: pin the version and the machine stays on it.

`--uninstall` removes links that point at a release copy or at a checkout, and
leaves anything else of the same name alone. It does not delete the unpacked
releases, and it says where they are so you can.

It is idempotent and says which of "installed" and "already installed"
happened, and it warns when the prefix is not on your `PATH` rather than
leaving you with a command nothing can find.

### Am I current?

```sh
agpin version --check
```

Prints the version you are running and the newest release, and exits non-zero
when you are behind, so it works from a cron entry or a shell hook. It compares
the numbers field by field, because `0.10.0` is newer than `0.9.9` and a string
comparison says the opposite.

It downloads that one answer and nothing else, and it installs nothing at all.
A tool that updates itself is a tool that can be made to run new code without
anybody deciding to, which is the thing this whole release process exists to
prevent.

### The development install

```sh
tools/install.sh --dev
```

This is the old behaviour, and it is still the right one when you are working
on the tool: it symlinks `~/.local/bin/agpin` straight at `bin/agent-profile`
in your checkout, so an edit takes effect with no install step.

**The installed command then runs whatever is in that checkout.** A `git pull`
changes it, and so does anyone who can push to this repository, and
`eval "$(agpin guard)"` in an rc file means that code runs at every shell
start. On a machine that holds customer data that is not a trade-off worth
making. The installer says as much when you use it, and refuses to combine
`--dev` with `--version`, because a development install has no version to pin.


## Use

```sh
agent-profile                     # ask which profile, and terminal or desktop
agent-profile new bouvet          # create root, app data dir and registry entry
agent-profile bouvet              # run Claude Code pinned to that profile
agent-profile run bouvet          # the same thing, spelled out
agent-profile shell bouvet        # a subshell pinned to that profile
eval "$(agent-profile env bouvet)"  # pin the shell you are already in
agent-profile which               # what am I pinned to?
agent-profile list                # every profile, its account and session count
agent-profile doctor              # is the separation actually holding?
agent-profile version --check     # am I running the newest release?
agent-profile desktop bouvet      # launch the desktop app pinned
agent-profile app bouvet          # build its Dock launcher
eval "$(agent-profile guard)"     # refuse to run the agent unpinned
claude bouvet                     # with the guard on, this pins and runs
```

Adding a fourth account is one command and no edit to any file.

### Just asking

Run it with no arguments and it asks:

```
Which profile?
  1) bouvet
  2) highsoft
  3) tide

Profile [1-3, Return to cancel]: 2

Where?
  1) desktop app
  2) terminal

Open [1-2, Return to cancel]: 1
```

Five characters and two keystrokes, which beats `agpin desktop highsoft` when
you open pinned apps all day.

An empty answer cancels rather than defaulting to the first profile: silently
picking one is how you end up in the wrong account without noticing.

The prompt only appears on a terminal. Piped or scripted, the bare command
still prints help and exits non-zero exactly as before, so nothing reading the
output can hang waiting for an answer.

### Refusing to run unpinned

```sh
eval "$(agpin guard)"
```

This is the only real mitigation for the one hole the audit cannot close. An
unpinned run writes to the default root, and if a profile owns that root,
`doctor` can no longer tell the two apart. Stopping the run is what is left.

The function refuses, names the profiles you have, and shows how to pin. An
explicit `command claude` still works, because an escape hatch you can see
beats one people find by deleting the guard from their rc file.

**A leading profile name is the shortcut**, so the refusal is rarely the end of
it:

```sh
claude bouvet              # runs pinned to bouvet
claude tide --continue     # arguments after the name are passed straight on
```

The tool takes the same shortcut, so `agpin bouvet` is short for
`agpin run bouvet`. There a subcommand always wins: every command is matched
before the fallback, so a profile named `doctor` or `app` cannot shadow one,
and the worst case is that it needs the explicit `run` form.

This applies **only when nothing is pinned**, and that is what makes it safe:
the alternative on that path is a refusal, so there is no working invocation
for it to shadow. Once a shell is pinned, the argument is left alone, because
`claude` takes a prompt there and stealing a word that happened to match a
profile name would break it.

It is printed rather than installed, and re-derived on every shell start, for
the same reason the prompt label is: a copy in a dotfile drifts from the tool,
and this one would drift silently. That prompt label, and the one root where
it has to work differently, are explained in
[A prompt that cannot lie](docs/DESIGN.md#a-prompt-that-cannot-lie).

## The desktop

The desktop app takes its config root from its process environment, and macOS
`open` puts it there:

```sh
open -n -a /Applications/Claude.app \
    --env CLAUDE_CONFIG_DIR=~/.claude-bouvet \
    --args --user-data-dir=~/Library/Application\ Support/Claude-Bouvet
```

**`--env` must come before `--args`.** Everything after `--args` is handed to
the application rather than to `open`, so an `--env` on the wrong side of it
produces a launch line that reads correctly, contains every right string, and
pins nothing.

```sh
agent-profile desktop bouvet          # launch it pinned, once
agent-profile app bouvet              # or build a launcher you can keep
agent-profile app bouvet --icon ~/icons/bouvet.png
```

`app` puts that command inside an AppleScript applet, so the profile has a Dock
icon that cannot launch unpinned. Run it again and it repairs the launch line in
place, keeping the icon; if there was nothing to repair it says so, because
"already applied" and "never worked" must not look the same.

**Your launchers do not have to live in `~/Applications`.** Before falling back
to the conventional path, `app` searches for one that already pins this
profile's root and adopts it, saying plainly that it found rather than created
it. If two launchers pin the same root it refuses and asks which, rather than
rewriting a file you did not name. `--applet` always wins over the search.

`--icon` takes a 1024px PNG and installs it through `sips` and `iconutil`. It
keeps the applet's original icon once, and never replaces that backup on a
later run. At Dock size a word is illegible: one large initial and a distinct
colour per account is what actually reads.

Two things this tool will not do, both because they do not work. It will not
build a `.app` whose executable is a shell script: such a bundle has no Mach-O
header, so macOS cannot determine its architecture and the Dock icon bounces
forever. And it will not run the app binary from your shell: Electron inherits
the terminal's stdin, and the app dies with the shell.

A profile has two identities that can disagree with each other, the app's own
login and the config root its embedded Claude Code writes to; see
[Two identities, and they can disagree](docs/DESIGN.md#two-identities-and-they-can-disagree).

## The audit

`doctor` is the command this tool exists for. It exits non-zero and names the
offender, so it works from a cron entry or a shell hook.

| Rule | Finding |
| --- | --- |
| D01 | The default root holds sessions, so something ran unpinned |
| D02 | A stray state file sits outside every profile root |
| D03 | The same project has sessions under more than one root |
| D04 | A registered root does not exist |
| D05 | A root has no credential and no signed-in account |
| D06 | A config root exists that no profile claims |
| D07 | A root or app data directory is not mode 700 |
| D08 | A project directory is not an encoded path |
| D09 | A `claude-cli://` handler is installed and cannot be pinned |
| D10 | A stored root is not in the form its credential is keyed on |
| D11 | A credential exists for the default root, so something ran pinned to it |
| D12 | Keychain credential entries belong to no known root |
| D13 | A desktop launcher does not pin its profile |
| D14 | A desktop launcher exists that no profile claims |
| D15 | More than one profile is registered at the same root |

The reasoning behind the trickier rules, D05's exact Keychain check, D13 and
D14 on the desktop side, and D03's use of each transcript's own working
directory, is in
[The audit, rule by rule](docs/DESIGN.md#the-audit-rule-by-rule).

## When an engagement ends

Engagements end, and the customer's data has to leave the laptop. The
machinery that kept that account separate is exactly what makes it hard to
find: a config root, an app data directory, a Dock launcher and a Keychain
entry, in four different places, none of them named after the customer.
Deleting a registry file by hand and then hunting for the rest is how a
transcript survives on a machine for another two years.

`remove` does the finding. With no flags it deletes the registry entry, nothing
else, and prints every remaining piece with the command that deletes it:

```sh
agpin remove bouvet
```

```
Unregistered bouvet

Left on this machine:

  config root  /Users/alex/.claude-bouvet
               412 session(s)
               rm -rf '/Users/alex/.claude-bouvet'

  app data     /Users/alex/Library/Application Support/Claude-Bouvet
               rm -rf '/Users/alex/Library/Application Support/Claude-Bouvet'

  launcher     /Users/alex/Applications/Claude-Bouvet.app
               rm -rf '/Users/alex/Applications/Claude-Bouvet.app'

  credential   Claude Code-credentials-1715f9d2
               This tool never touches credentials, so this one is yours to delete.
               Until it is gone, doctor counts it as a D12 orphan.
               security delete-generic-password -s 'Claude Code-credentials-1715f9d2' -a 'alex'

The registry entry is gone, so this command cannot look those paths up again.
The list above is the whole record of them.

Then run: agpin doctor
A root no profile claims is D06 and a launcher no profile claims is D14, so
both go quiet once those paths are gone.
```

`--purge` does the deleting for you, for the root, the app data directory and
the launcher:

```sh
agpin remove bouvet --purge
```

It lists what it is about to delete, then asks you to type the profile name
back. Anything else aborts having deleted nothing, and a prefix of the name is
not the name. It refuses outright when stdin is not a terminal, so no script
can purge and no pipeline can answer the question for you.

It deletes only what that profile's own registry entry names, exactly as it
names it. A symlink is refused rather than followed, because what it points at
was never this profile's. A root two profiles claim is refused, because it
holds more than the account you are retiring. A launcher the registry does not
name is refused too: where a launcher would conventionally be is a guess, and a
guess is not something to delete. Everything it declines is printed with the
reason and the command, so nothing is silently retained.

The credential is never touched, in either form. This tool does not read, write
or delete credentials, and the command that ends an engagement is the last
place to start. It prints the `security delete-generic-password` line and
leaves running it to you.

Then audit what is left:

```sh
agpin doctor
```

A root no profile claims is D06 and a launcher no profile claims is D14, so
after `remove` on its own both of those are waiting for you, and after a purge
both are quiet. D12 is the one that stays. It counts Keychain entries whose
suffix matches no root on this machine, and the retired profile's entry is now
exactly that. The suffix is a one-way hash, so nothing can trace it back to a
path or delete it for you; run the printed `security` command and D12 goes
quiet on the next run. Leaving it is harmless, and it is also a credential for
an account you no longer work for, sitting in your Keychain.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success, nothing to report |
| 1 | Usage error, unknown profile or agent, missing dependency, `version --check` found a newer release, or `remove` was aborted or could not delete everything |
| 2 | `doctor` found an isolation problem |
| 3 | `verify` found an assumption that no longer holds |
| 4 | `verify` could not check something it wanted to check |

3 and 4 are deliberately different, so an unattended run can tell "your
isolation broke" apart from "I could not look".

## What to do after a Claude Code update

Claude Code changes monthly, and some of what this tool depends on is
undocumented. That is why `verify` exists.

```sh
agent-profile verify
```

It re-checks the assumptions the tool rests on against the version actually
installed, and says plainly which it could not check. The record of every
assumption, its evidence and the version it was last checked against lives in
[`docs/FACTS.md`](docs/FACTS.md).

Two checks earn the command.

**F11**: transcripts record their own `cwd`. `doctor`'s D03 is built on it. If
a future version stops recording `cwd`, D03 finds nothing and reports a clean
machine, which is worse than failing. `verify` catches exactly that and tells
you not to trust `doctor` until it is fixed.

**F13**: `open` still takes `--env`. Without it, nothing can pin the desktop
app, and `desktop`, `app` and D13 are all invalid at once while continuing to
look healthy. `verify` reports that as broken rather than unchecked, because an
applet that no longer pins still launches perfectly.

If the desktop app updated, also run:

```sh
bash tools/probe-claude-desktop.sh
```

It works in a throwaway root, never touches a real one, never reads credential
content, and answers the questions that need a real Mac. Paste its output into
`docs/FACTS.md`.

"After an update" is a per-profile question rather than a per-machine one. Each
desktop profile downloads its own copy of Claude Code under its app data
directory, so they update independently of each other and of the CLI. There is
no single agent version on a machine like this, and an assumption can break for
one profile while holding for the rest.

`agent-profile explain` states the scheme in plain language and shows where this
machine's data currently lives, for when you come back to this in six months.

### Windows

Nothing in this tool has been run on Windows. What a port would rest on is
written down all the same, as W01 to W06 in [`docs/FACTS.md`](docs/FACTS.md),
with the same statuses the macOS facts carry and an honest one for each. Every
entry there was read out of the documentation or argued from it. None was
observed on a Windows machine, so none is `VERIFIED`.

```powershell
powershell -ExecutionPolicy Bypass -File tools\probe-claude-windows.ps1
```

The probe works in a throwaway config root and app data directory under
`$env:TEMP`, never touches a real root, never reads the content of a credential
file, and removes what it made. Run it in Windows PowerShell 5.1 or PowerShell
7 and paste the output into the Windows section of `docs/FACTS.md`. That
settles five of the six. W05 needs a person as well: pin the launcher the probe
leaves behind, launch from the pin, and say which root the session landed in.

W04 is the one that decides the shape of a port. It asks whether the desktop
app's embedded Claude Code reads the config root from the app's process
environment, which is F01 asked again for Windows. Until somebody answers it,
no Windows launcher should ship, because a launcher that pins nothing looks
exactly like one that works.

## Three things that are not what they look like

Pinning to the default root is not the same as not pinning, a config root can
never be moved or renamed once it has a login, and the desktop app naming an
account is not evidence that anything is pinned. Each of those is worth
reading in full, because each one has cost someone real time:
[Three things that are not what they look like](docs/DESIGN.md#three-things-that-are-not-what-they-look-like).

## Status

macOS only. Both halves are implemented.

The question that gated the desktop half is answered: the desktop app's
embedded Claude Code does honour `CLAUDE_CONFIG_DIR` from its process
environment, and `open --env` is what delivers it. That was established on a
real machine during two account migrations and confirmed twice, once per
account. The Keychain naming, the URL handler and the state-file questions are
answered too. The record is [`docs/FACTS.md`](docs/FACTS.md).

Three things are deliberately not built yet: a per-root status line installer
(tamper-proof by construction, but it means writing inside a root, which this
tool does not do), `doctor --recent` as a standing command rather than the
manual leak test below, and validation of what a root's settings actually
contain rather than just its layout. The reasoning for each is in
[Not built, and deliberately](docs/DESIGN.md#not-built-and-deliberately).

### The leak test

Whatever else you check, this is the one that settles an argument. Run a real
session, then:

```sh
find "$HOME"/.claude* -name '*.jsonl' -mmin -3
```

The path it prints is the root that is really in use. It needs no throwaway
root, no probe and no documentation, and it works the same for the terminal and
the desktop.

## Development

```sh
tests/run.sh              # 204 tests, no dependencies
shellcheck bin/agent-profile tools/*.sh tests/run.sh tests/cases/*.sh
tools/lint-bash32.sh      # refuse bash 4 constructs
```

CI runs the suite on macOS under both `/bin/bash` (the real 3.2) and Homebrew's
latest bash. Tests never touch a real config root: every path the script
resolves comes from `HOME` or an `AGENT_PROFILE_*` variable, and the harness
redirects all of them into a throwaway tree.

Versioning is semantic. `Z` for fixes, `Y` for backwards-compatible features,
`X` for breaking changes.

### Cutting a release

Bump `AGENT_PROFILE_VERSION` in `bin/agent-profile`, merge that, then tag the
merge commit:

```sh
git checkout hovud && git pull
git tag -s v0.7.1 -m "agent-profile 0.7.1"
git push origin v0.7.1
```

`-s` makes it a signed annotated tag, which needs a signing key configured;
`-a` makes an annotated one without a signature. A signed tag records who cut
the release, and the Sigstore bundle records what the workflow then built from
it. Those answer different questions, so do both.

`.github/workflows/release.yml` takes it from there: it runs the same test
matrix `ci.yml` runs, calling that workflow rather than copying it, refuses the
tag if it disagrees with `AGENT_PROFILE_VERSION`, builds the tarball, writes
`SHA256SUMS`, signs both with keyless Sigstore and publishes the release.

The tarball is built with fixed ownership, fixed order and the tagged commit's
own timestamp, so anyone can check the tag out, rebuild it and get the same
`sha256`. A checksum nobody can reproduce only says the file did not change in
transit.

Then update `packaging/homebrew/agpin.rb` and the tap, which
[`packaging/homebrew/README.md`](packaging/homebrew/README.md) covers. The
formula cannot be updated before the release, because until it exists there is
no sum to pin.

## Licence

`agent-profile` is licensed under the GNU General Public License version 3 or
later (GPL-3.0-or-later). See `LICENSE` for the full text.

Use it on any machine, for any customer, for any purpose, free of charge. The
one condition is on redistribution: if you hand out a modified copy, or a
repackaged one, you must publish those modifications under the same licence.
