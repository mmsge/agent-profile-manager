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

Put `bin/agent-profile` somewhere on your `PATH`:

```sh
ln -s "$PWD/bin/agent-profile" /usr/local/bin/agent-profile
```

No dependencies beyond a stock macOS. It is one bash script, written to bash
3.2 because that is what `/bin/bash` is on macOS, and it uses `python3` from the
Command Line Tools only to read JSON. No Homebrew, no `jq`.

## Use

```sh
agent-profile new bouvet          # create root, app data dir and registry entry
agent-profile run bouvet          # run Claude Code pinned to that profile
agent-profile shell bouvet        # a subshell pinned to that profile
eval "$(agent-profile env bouvet)"  # pin the shell you are already in
agent-profile which               # what am I pinned to?
agent-profile list                # every profile, its account and session count
agent-profile doctor              # is the separation actually holding?
```

Adding a fourth account is one command and no edit to any file.

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
| D07 | A root is not mode 700 |
| D08 | A project directory is not an encoded path |
| D09 | A `claude-cli://` handler is installed and cannot be pinned |
| D10 | A stored root is not in the form its credential is keyed on |
| D11 | A credential exists for the default root, so something ran pinned to it |
| D12 | Keychain credential entries belong to no known root |

D05 is exact rather than a guess: the Keychain service name is
`Claude Code-credentials-<first 8 hex of sha256 of the config root path>`, with
the account set to `$USER`. Existence is checked with `find-generic-password`
and its output discarded, never with `-g`, so no secret is read.

Two things follow from that naming, and each has its own rule. The hash covers
the **literal path string**, so `~/.claude-work` and `~/.claude-work/` are two
different logins (D10, and `new` normalizes to prevent it). And the suffix is
present whenever the variable is **set at all**, so pinning to the default root
is a different login from not pinning, which D11 reports.

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
| 1 | Usage error, unknown profile or agent, missing dependency |
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

The check that earns the command is **F11**: transcripts record their own `cwd`.
`doctor`'s D03 is built on it. If a future version stops recording `cwd`, D03
finds nothing and reports a clean machine, which is worse than failing. `verify`
catches exactly that and tells you not to trust `doctor` until it is fixed.

If the desktop app updated, also run:

```sh
bash tools/probe-claude-desktop.sh
```

It works in a throwaway root, never touches a real one, never reads credential
content, and answers the questions that need a real Mac. Paste its output into
`docs/FACTS.md`.

`agent-profile explain` states the scheme in plain language and shows where this
machine's data currently lives, for when you come back to this in six months.

## Two things that are not what they look like

**Pinning to the default root is not the same as not pinning.** Setting
`CLAUDE_CONFIG_DIR=~/.claude` produces a different layout from leaving it unset,
because the state file moves inside the root. `doctor` never treats the two as
equivalent.

**A config root cannot be moved or renamed.** Credentials are keyed to the root
path, so a root at a new path reads a different Keychain entry and a different
`.credentials.json`. That is why there is no `rename` and no `move`, and why
`new` refuses to repoint an existing profile. Create a new profile instead.

## Status

macOS only. The terminal half is complete, and the Keychain, URL handler and
state-file questions are answered (see [`docs/FACTS.md`](docs/FACTS.md)).

The desktop half, `desktop` and `app`, is not implemented yet. Whether the
desktop app honours `CLAUDE_CONFIG_DIR` from its process environment decides
that half's architecture and is still unanswered: the first probe run confirmed
the app starts and that `--user-data-dir` works, but was interrupted before a
Code session ran, and the embedded Claude Code writes nothing until one does.
Re-run the probe and answer its prompt to settle it.

## Development

```sh
tests/run.sh              # 67 tests, no dependencies
shellcheck bin/agent-profile tools/*.sh tests/run.sh tests/cases/*.sh
tools/lint-bash32.sh      # refuse bash 4 constructs
```

CI runs the suite on macOS under both `/bin/bash` (the real 3.2) and Homebrew's
latest bash. Tests never touch a real config root: every path the script
resolves comes from `HOME` or an `AGENT_PROFILE_*` variable, and the harness
redirects all of them into a throwaway tree.

Versioning is semantic. `Z` for fixes, `Y` for backwards-compatible features,
`X` for breaking changes.
