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

It is named for agents rather than for Claude because the same problem will
arrive with ollama, codex and whatever comes next. Claude is the only agent
implemented today.

## What a profile is

One profile is one account, and it owns two directories:

| | |
| --- | --- |
| **Config root** | `~/.claude-<name>`, the value of `CLAUDE_CONFIG_DIR` |
| **App data dir** | `~/Library/Application Support/Claude-<Name>`, the value of `--user-data-dir` |

The config root holds everything the agent stores: settings, session
transcripts, auto memory, commands, skills, agents, plugins, plans, backups, the
credential and the state file. Two profiles therefore share no file at all.

## Why nothing is shared

**No exceptions.** No symlinks, no shared parent directory, no copying common
commands into every root, no seeding a new root from an existing one, no
template of default settings. `new` creates an empty root.

The cost is real and worth stating: a fresh root has no settings, no hooks and
none of the guardrails your other profiles have. Set those up in the new root
directly. Do not copy them across, because a copied file is a file that drifts.

The tool also never touches credentials beyond checking that one exists, never
edits the agent's own state files, and never migrates data between roots.

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

### Adopting a machine you set up by hand

`new` on a root that already exists and holds data adopts it rather than
creating it. Nothing is copied, moved, seeded or removed; the only change is
that the root and its app data directory become mode 700. Point it at what you
already have:

```sh
agent-profile new tide --root ~/.claude-tide \
    --app-data ~/Library/Application\ Support/Claude-Tide
```

It says which of the two it did, and reports the session count it found, so
"adopted your live root" and "made you an empty one" can never be confused.
Check with `agent-profile list` that each profile names the account you expect
before trusting `doctor`.

An account living in the **default** root is a supported case: register it with
`--root ~/.claude` and `doctor` will stop reporting that root as an unpinned
leak, because a profile now claims it. It is still a different login from
running unpinned, and D11 still says so.

It costs you D01 permanently, though, and `new` says so when you do it. An
unpinned run writes to that same root in the same layout, so on disk it is
indistinguishable from that profile's own work. D02 and D03 become the only
rules still watching unpinned use, and moving the root to recover D01 is not an
option because that invalidates the login. The real guard is never running the
agent unpinned at all.

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
and this one would drift silently.

### A prompt that cannot lie

`agent-profile which --label` prints the label and nothing else, derived from
the pinned root every time it is called. It is stored nowhere, so it cannot
drift away from the root it names. It exits non-zero when the shell is pinned to
nothing, so an unpinned shell shows no label rather than a stale one.

```sh
# ~/.zshrc
agent_label() { agent-profile which --label 2>/dev/null; }
setopt PROMPT_SUBST
PROMPT='$(agent_label) %~ %# '
```

One root is an exception, and has to be. A profile living in the **default**
root has a basename of `.claude`, which names no account, and it cannot be
moved somewhere better because relocating a root invalidates its login. For
that root alone the registered name is used, so renaming that one registry
entry does move its label. Every other root keeps the guarantee.

This works in a shell that is actually pinned, which means `agent-profile
shell` or `eval "$(agent-profile env …)"`. It cannot work for a per-command
pin like `CLAUDE_CONFIG_DIR=… claude`, because the variable never enters the
shell and the prompt only redraws once the command has exited.

The same caveat applies one level up: an indicator like this covers the
terminal only. The desktop app renders no status line of its own, so there is
nothing inside it that says which root it is using. For the desktop, the
launcher is the guarantee and `doctor`'s D13 is the check.

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

### Two identities, and they can disagree

A profile has two. `--user-data-dir` selects the app's own login, the account
name you see in the app. `CLAUDE_CONFIG_DIR` selects where its embedded Claude
Code writes. They are independent, and they have been seen disagreeing: the app
showed the right account for weeks while its sessions were writing into another
account's root. The app naming an account is not evidence that anything is
pinned. `explain` prints both.

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

D05 is exact rather than a guess: the Keychain service name is
`Claude Code-credentials-<first 8 hex of sha256 of the config root path>`, with
the account set to `$USER`. Existence is checked with `find-generic-password`
and its output discarded, never with `-g`, so no secret is read.

Two things follow from that naming, and each has its own rule. The hash covers
the **literal path string**, so `~/.claude-work` and `~/.claude-work/` are two
different logins (D10, and `new` normalizes to prevent it). And the suffix is
present whenever the variable is **set at all**, so pinning to the default root
is a different login from not pinning, which D11 reports.

D13 is the desktop's only tell. The app renders no status line, and its own
login can be right while its sessions write elsewhere, so the launch line
inside the applet is the thing to read. It shares one definition of "correct"
with `agent-profile app`, so the audit and the repair cannot disagree. It
reports an applet that pins nothing, pins the wrong root, selects the wrong app
data directory, or puts `--env` after `--args`. It stays quiet about a
hand-tuned line that still pins the right root: that is nobody's business but
its owner's, and a rule that fires on a working setup gets ignored.

D14 exists because assuming launchers live in `~/Applications` is wrong on a
real machine. Two working ones were found sitting on a Desktop, entirely
outside the audit, while `doctor` reported a clean desktop. It searches
`~/Applications`, `~/Desktop` and `/Applications` for bundles whose launch line
mentions the config-dir variable, and reports any that no profile names, saying
which profile owns the root it pins. Set `AGENT_PROFILE_APPLET_DIRS` to search
elsewhere; it is colon-separated like `PATH`.

D03 is the one that catches real leakage, and it needs no configuration. Claude
Code names a project directory after the working directory with every
non-alphanumeric character replaced by `-`, so `my_repo`, `my-repo` and
`my.repo` all collide and the name cannot be decoded. Each transcript records
its own `cwd` as an absolute path instead, and D03 reads that. A path appearing
under two roots means one account has worked in the other's project.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success, nothing to report |
| 1 | Usage error, unknown profile or agent, missing dependency, or `version --check` found a newer release |
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

## Three things that are not what they look like

**Pinning to the default root is not the same as not pinning.** Setting
`CLAUDE_CONFIG_DIR=~/.claude` produces a different layout from leaving it unset,
because the state file moves inside the root. `doctor` never treats the two as
equivalent.

**A config root cannot be moved or renamed.** Credentials are keyed to the root
path, so a root at a new path reads a different Keychain entry and a different
`.credentials.json`. That is why there is no `rename` and no `move`, and why
`new` refuses to repoint an existing profile. Create a new profile instead.

**The app naming an account is not evidence that anything is pinned.** The
app's own login and the config root its embedded Claude Code writes to are two
independent identities, and they have been seen disagreeing for weeks. Read
both, which is what `explain` prints and what D13 checks.

## Status

macOS only. Both halves are implemented.

The question that gated the desktop half is answered: the desktop app's
embedded Claude Code does honour `CLAUDE_CONFIG_DIR` from its process
environment, and `open --env` is what delivers it. That was established on a
real machine during two account migrations and confirmed twice, once per
account. The Keychain naming, the URL handler and the state-file questions are
answered too. The record is [`docs/FACTS.md`](docs/FACTS.md).

Not built, and deliberately:

- **`statusline install`.** A per-root status line is the right terminal
  indicator, and it is tamper-proof by construction: a script that lives inside
  one config root can only run while that root is in use, so its label cannot
  name the wrong account. Installing one means writing inside a root, which
  this tool does not do yet, and doing it safely means merging a single key
  into `settings.json` while preserving every key it does not understand. Real
  roots carry hooks, permission blocks and a dozen other settings that a
  rewritten file would destroy.
- **`doctor --recent`**, the leak test below as a command.
- **Settings-content validation.** An invalid model id and permission rules
  written as English sentences both sit quietly in a live root today and pass
  every check that only looks at directory layout.

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
tests/run.sh              # 177 tests, no dependencies
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
