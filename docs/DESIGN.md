# Design notes

These are the essays behind `agent-profile`: why it works the way it does, in
more depth than the README needs to get someone running. The
[README](../README.md) links here from each place a summary used to be the
whole story.

## Why nothing is shared

**No exceptions.** No symlinks, no shared parent directory, no copying common
commands into every root, no seeding a new root from an existing one, no
template of default settings. `new` creates an empty root.

The cost is real and worth stating: a fresh root has no settings, no hooks and
none of the guardrails your other profiles have. Set those up in the new root
directly. Do not copy them across, because a copied file is a file that drifts.

The tool also never touches credentials beyond checking that one exists, never
edits the agent's own state files, and never migrates data between roots.

## A prompt that cannot lie

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

### Faster: caching the label per shell

A fast path in `bin/agent-profile` now answers `which --label` before the rest
of the script is even read, which is most of what made it slow (docs/FACTS.md
has the numbers). What is left is a process to start, which a prompt still
pays for on every single command. This caches the label in the shell and only
calls out to `agent-profile` again when `CLAUDE_CONFIG_DIR` has actually
changed, which in practice means "when this shell got pinned or re-pinned",
not "every time a prompt is drawn".

The guarantee is unaffected: the caching lives entirely in the shell, and the
value it caches is never anything but what `agent-profile which --label` most
recently answered for the root currently pinned. Pin a different profile and
the next prompt recomputes, because the comparison is against
`$CLAUDE_CONFIG_DIR` itself, not against anything this tool stored.

```sh
# ~/.zshrc
autoload -Uz add-zsh-hook
_agent_profile_precmd() {
    if [ "${CLAUDE_CONFIG_DIR:-}" != "${_agent_profile_label_root:-}" ]; then
        _agent_profile_label_root=${CLAUDE_CONFIG_DIR:-}
        AGENT_PROFILE_LABEL=$(agent-profile which --label 2>/dev/null)
        export AGENT_PROFILE_LABEL
    fi
}
add-zsh-hook precmd _agent_profile_precmd
setopt PROMPT_SUBST
PROMPT='$AGENT_PROFILE_LABEL %~ %# '
```

[starship](https://starship.rs) needs the same hook: starship renders a
prompt, it does not run other tools' prompt logic for you, so nothing calls
`agent-profile` unless something still does. Keep the hook above, drop the
`PROMPT=` line, and point starship at the variable it maintains with an
`env_var` module, which costs starship nothing beyond reading memory that is
already there:

```toml
# ~/.config/starship.toml
[env_var.AGENT_PROFILE_LABEL]
format = "[$env_value]($style) "
style = "bold cyan"
```

## Two identities, and they can disagree

A profile has two. `--user-data-dir` selects the app's own login, the account
name you see in the app. `CLAUDE_CONFIG_DIR` selects where its embedded Claude
Code writes. They are independent, and they have been seen disagreeing: the app
showed the right account for weeks while its sessions were writing into another
account's root. The app naming an account is not evidence that anything is
pinned. `explain` prints both.

## The audit, rule by rule

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

## One stream, two renderings

`doctor`, `list` and `verify` each produce prose and a machine-readable
document, and the obvious way to build that is a second set of print statements
under an `if`. That way the two disagree within a release or two: someone adds a
rule, prints a finding, and forgets the JSON half, and the document quietly
reports a clean machine.

So neither format is written directly. Every user-facing line goes through one
function, `emit`, as a record: a level, a kind and that kind's fields. Prose is
one renderer over that stream and the document is another. A rule that stops
printing stops appearing in the JSON in the same edit, because there is only
one edit to make.

The level is the second half of the idea. It is ordered, `always`, `normal`,
`detail`, with `data` for a record that is never prose and `prose` for a line
that is never recorded. `data` is what lets `doctor`'s prose stay silent about
healthy profiles while the document still lists every one of them, and `prose`
is what keeps the line saying where a report was written out of the report.
Only `normal` is reachable today; the ordering is there so a quieter or a more
explanatory mode is a threshold and a flag rather than a rewrite.

The one thing the document has that the prose does not is the rule ledger:
every rule with a status, not only the ones that fired. That exists because a
rule can fail to run. `D12` is opt-in behind `--keychain-scan`, `D11` and `D12`
need a Keychain, `D13` and `D14` need `osadecompile`. Silence from a check that
never ran looks exactly like silence from a check that passed, and a document
handed to a customer's security officer is the worst possible place for that
confusion. `not_run` and `limited` are statuses of their own, each carrying the
reason. The full schema is in [AUDIT-SCHEMA.md](AUDIT-SCHEMA.md).

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

## Not built, and deliberately

- **`statusline install`.** A per-root status line is the right terminal
  indicator, and it is tamper-proof by construction: a script that lives inside
  one config root can only run while that root is in use, so its label cannot
  name the wrong account. Installing one means writing inside a root, which
  this tool does not do yet, and doing it safely means merging a single key
  into `settings.json` while preserving every key it does not understand. Real
  roots carry hooks, permission blocks and a dozen other settings that a
  rewritten file would destroy.
- **`doctor --recent`**, the leak test the README keeps as a command you run by
  hand rather than one this tool provides.
- **Settings-content validation.** An invalid model id and permission rules
  written as English sentences both sit quietly in a live root today and pass
  every check that only looks at directory layout.
