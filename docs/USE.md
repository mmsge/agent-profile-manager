# Daily use

Everything after setup: the commands, the guard, the picker, pinning a
shell, completions, the output levels and the sessions server. Every output
shown is generated from a real run of the tool.

## The commands

```sh
agpin                     # ask which profile, and terminal or desktop
agpin new brygga          # create root, app data dir and registry entry
agpin brygga              # run Claude Code pinned to that profile
agpin run brygga          # the same thing, spelled out
agpin shell brygga        # a subshell pinned to that profile
eval "$(agpin env brygga)"  # pin the shell you are already in
agpin which               # what am I pinned to?
agpin list                # every profile, its account, sessions and server state
agpin mcp status          # is each profile's sessions server on, off or stale?
agpin mcp off brygga      # turn one off; mcp on turns it back on
agpin doctor              # is the separation actually holding?
agpin doctor --json       # the same audit, as one JSON document
agpin doctor --report audit  # audit.json and audit.md, dated, to hand over
agpin version --check     # am I running the newest release?
agpin desktop brygga      # launch the desktop app pinned
agpin app brygga          # build its Dock launcher
agpin code brygga ~/src/x   # launch VS Code pinned, --app Cursor for Cursor
agpin idea brygga ~/src/x   # the same for the JetBrains IDEs
agpin shellrc             # the rc-file lines, in your own shell's dialect
eval "$(agpin guard)"     # refuse to run the agent unpinned
claude brygga             # with the guard on, this pins and runs
```

Adding a fourth account is one command and no edit to any file.

**The tool names itself by whichever name you invoke.** Run it as `agpin` and
every message, error and suggested fix says `agpin`; run it as `agent-profile`
and they say that. That matters because a finding telling you to run a
command not on your `PATH` is worse than no suggestion at all. The built-in
help is the full reference, and it is generated here so it cannot drift:

<!-- BEGIN GENERATED: example help (tools/gen-doc-examples.sh) -->
```sh
agpin help
```

```
agpin: Agent Profile Manager

Keeps several agent accounts separate on one machine by giving each its own
config root, and audits that the separation actually holds.

USAGE
  agpin                  Ask which profile and where to open it.
  agpin <command> [arguments]

PROFILES
  new <name> [--agent NAME] [--root PATH] [--app-data PATH] [--explain]
                          Create a config root, an app data dir and a registry
                          entry, and register the profile's sessions server in
                          the root. Nothing is copied into the root from
                          anywhere. Safe to run twice. Default output is a few
                          lines: what happened and the next command. --explain
                          restores the full rationale.
  list [--json]           Every profile with its root, account, session count
                          and whether its sessions server is on.
  remove <name> [--purge] Retire a profile. It removes the registry entry and
                          prints everything else the profile still has on this
                          machine, with the command that deletes each one.
                          --purge deletes the root, the app data dir and the
                          launcher too, after you type the name back at a
                          prompt, and only from a terminal. It never touches
                          the credential, in either form.

PINNED EXECUTION
  <name> [args...]        Run the agent's CLI pinned to that profile. A bare
                          profile name is short for run.
  run <name> [args...]    Run the agent's CLI pinned to a profile.
  shell <name>            Open an interactive subshell pinned to a profile.
  env <name>              Print exports. Use: eval "$(agpin env work)"
  path <name>             Print a profile's config root.
  which [--label] [--explain]
                          Which profile this shell is pinned to, if any.
                          --explain adds why an unpinned shell matters.

IDEs
  code <name> [path] [--app NAME] [--new-instance]
                          Launch VS Code pinned to a profile, opening PATH if
                          given. --app names another application in the same
                          family, such as --app Cursor. Refuses when that
                          editor is already running, because the launch would
                          land in the running instance and be pinned to
                          whatever it was started with; --new-instance starts a
                          separate one, with its own settings kept under this
                          profile, so the pin applies anyway.
  idea <name> [path] [--app NAME]
                          The same for the JetBrains IDEs, IntelliJ IDEA by
                          default; --app PyCharm and so on. It refuses on a
                          running IDE for the same reason, and has no
                          --new-instance: quit it and run this again.
                          An IDE started any other way runs its Claude Code
                          extension unpinned, because the extension takes the
                          config root from the IDE's own process environment
                          and a Dock or Spotlight launch carries none. doctor
                          reports an installed extension as D16.

DESKTOP
  desktop <name>          Launch the desktop app pinned to a profile. Running
                          agpin with no arguments asks instead.
  app <name> [--applet PATH] [--icon PNG] [--explain]
                          Generate or repair the AppleScript applet that
                          launches a profile from the Dock. Safe to run twice,
                          and it says which of the two happened. --icon takes a
                          1024px PNG; at Dock size only a single initial and a
                          distinct colour per account are legible. --explain
                          restores the full rationale and how to confirm the
                          pin actually took.

SESSIONS SERVER
  mcp on <name>           Register the profile's sessions server: an MCP
                          server, started by Claude Code inside that profile's
                          sessions, that answers questions about the
                          transcripts in that profile's root and nothing else.
                          new does this already; this is for a profile that
                          was turned off, or created before claude was on PATH.
  mcp off <name>          Remove it from the root's state file. Off means gone,
                          not hidden, and the file is read back to check.
  mcp status [name]       on, off or stale for each profile, read from the
                          root's state file. Nothing is written.
  mcp serve --root PATH   What the registration runs. Claude Code starts it;
                          it refuses unless CLAUDE_CONFIG_DIR is PATH.

SHELL
  shellrc [--shell bash|zsh|fish] [--explain]
                          Print the three lines worth adding to your shell rc
                          file, in one shell's dialect and no other, with the
                          file they belong in. The shell comes from --shell,
                          or from $SHELL; --explain prints all three forms and
                          what each line does. Nothing is written anywhere.
  guard [--shell bash|zsh|fish]
                          Print a shell function that refuses to run the agent
                          unpinned, and turns a leading profile name into a
                          pinned run. bash and zsh share one form; fish gets
                          its own, chosen by --shell or by reading $SHELL when
                          --shell is not given. Add to your rc file:
                            eval "$(agpin guard)"
  completion bash|zsh|fish
                          Print a completion script covering every subcommand,
                          its flags, and profile names. Profile names are
                          looked up when the shell asks, not baked into the
                          script, so a new profile completes without
                          re-sourcing anything. Add to your rc file:
                            eval "$(agpin completion bash)"    # bash
                            eval "$(agpin completion zsh)"     # zsh
                            agpin completion fish | source     # fish

AUDIT
  doctor [--json] [--report FILE] [--keychain-scan] [--quiet] [--explain]
                          Check that the profiles are actually isolated.
                          --keychain-scan also enumerates the whole login
                          Keychain for orphaned entries (D12), which reads
                          every item's attributes and is slow on a large
                          Keychain, so it is off by default.
                          --json prints the audit as one JSON document.
                          --report writes FILE.json and FILE.md, a dated
                          audit of this machine to hand to someone else.
                          The exit code is the same either way.
                          --quiet prints nothing on a clean run and exits 0;
                          a finding still prints in full and exits as always,
                          for cron and shell hooks. Findings are the product,
                          so --explain adds nothing here today.
                          Schema: docs/AUDIT-SCHEMA.md
  verify [--json] [--quiet] [--explain]
                          Re-check the behavioural assumptions this tool rests
                          on. --quiet and --explain work as they do for doctor.
  explain                 Explain the scheme and where each profile's data
                          lives, in full, always. Not the --explain flag above:
                          this is its own command, for when the reader wants
                          the whole layout rather than one command's rationale.

OTHER
  version [--check]       Print the version. --check compares it against the
                          newest release and exits non-zero when this one is
                          behind. It downloads nothing and installs nothing.
  help

OUTPUT LEVELS
  new, app, which and doctor's and verify's --explain, plus running with
  AGENT_PROFILE_EXPLAIN=1 set, all mean the same thing: print the reasoning
  behind a line, not only the line. Nothing here changes what a command does,
  what it exits with, or what --json or --report FILE contain -- those are
  the same document at every level. Only the terminal gets shorter or longer.

EXIT CODES
  0  success, nothing to report
  1  usage error, unknown profile or agent, missing dependency,
     version --check found a newer release, or remove was aborted or
     could not delete everything it was asked to
  2  doctor found an isolation problem
  3  verify found an assumption that no longer holds
  4  verify could not check something it wanted to check

Nothing is ever shared, copied or symlinked between two config roots.
```
<!-- END GENERATED: example help -->

## Just asking

Run it with no arguments and it asks:

<!-- illustrative: the picker needs a terminal, and its prompts and the answers typed at them cannot be captured from a pipe -->
```
Which profile?
  1) brygga
  2) havnelab
  3) torg

Profile [1-3, Return to cancel]: 2

Where?
  1) desktop app
  2) terminal
  3) subshell

Open [1-3, Return to cancel]: 1
```

Five characters and two keystrokes, which beats `agpin desktop havnelab` when
you open pinned apps all day. "subshell" is the third surface: a pinned
interactive shell, the same one `agpin shell havnelab` opens, for when you
want more than one command against that profile without leaving the terminal.

An empty answer cancels rather than defaulting to the first profile: silently
picking one is how you end up in the wrong account without noticing.

The prompt only appears on a terminal. Piped or scripted, the bare command
still prints help and exits non-zero exactly as before, so nothing reading the
output can hang waiting for an answer.

## Pinning a shell

`run` pins one invocation. `shell` opens a subshell that stays pinned until
you `exit`. `env` prints the export for the shell you are already in:

<!-- BEGIN GENERATED: example env (tools/gen-doc-examples.sh) -->
```sh
agpin env brygga
```

```
export CLAUDE_CONFIG_DIR='/Users/alex/.claude-brygga'
```
<!-- END GENERATED: example env -->

`which` says what the current shell is pinned to, derived from the pinned
root every time rather than from anything stored:

<!-- BEGIN GENERATED: example which-pinned (tools/gen-doc-examples.sh) -->
```sh
eval "$(agpin env brygga)"
agpin which
```

```
Pinned to brygga
  agent     claude
  CLAUDE_CONFIG_DIR=/Users/alex/.claude-brygga
  profile   brygga
```
<!-- END GENERATED: example which-pinned -->

<!-- BEGIN GENERATED: example which-unpinned (tools/gen-doc-examples.sh) -->
```sh
agpin which
```

```
Not pinned to any profile.
Pin with: eval "$(agpin env <profile>)"
```
<!-- END GENERATED: example which-unpinned -->

`which --label` prints the label and nothing else, and exits non-zero when
nothing is pinned, which is what makes it safe in a prompt:

```sh
PROMPT='$(agpin which --label 2>/dev/null) %~ %# '
```

The label is stored nowhere, so it cannot drift away from the root it names;
an unpinned shell shows no label rather than a stale one. That guarantee, and
the one root where it has to work differently, are explained in
[A prompt that cannot lie](DESIGN.md#a-prompt-that-cannot-lie). If the label
is calling `agpin` on every command more often than you would like,
[Faster: caching the label per shell](DESIGN.md#faster-caching-the-label-per-shell)
has a zsh and a starship form that only call out when `CLAUDE_CONFIG_DIR`
actually changes.

A per-command pin, `CLAUDE_CONFIG_DIR=… claude`, pins that one invocation
without ever touching the shell's own environment, so the prompt keeps
showing whatever the shell was already pinned to, or nothing. Run `agpin
which` for the true state of the invocation you are about to make, not the
prompt.

## Refusing to run unpinned

```sh
eval "$(agpin guard)"
```

This is the only real mitigation for the one hole the audit cannot close. An
unpinned run writes to the default root, and if a profile owns that root,
`doctor` can no longer tell the two apart. Stopping the run is what is left.

The function refuses, names the profiles you have, and shows how to pin:

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

An explicit `command claude` still works, because an escape hatch you can see
beats one people find by deleting the guard from their rc file.

**A leading profile name is the shortcut**, so the refusal is rarely the end of
it:

```sh
claude brygga              # runs pinned to brygga
claude torg --continue     # arguments after the name are passed straight on
```

The tool takes the same shortcut, so `agpin brygga` is short for
`agpin run brygga`. There a subcommand always wins: every command is matched
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

**fish gets its own form**, because fish functions are not bash or zsh
functions:

```fish
agpin guard --shell fish | source
```

Same refusal, same leading-profile-name shortcut, same `command claude`
escape hatch, spelled in fish: `$argv` rather than `"$@"`, `$status` rather
than `"$?"`. With no `--shell`, `guard` reads `$SHELL` and chooses the bash and
zsh form unless it ends in `fish`, so `eval "$(agpin guard)"` and
`agpin guard --shell fish | source` both do the right thing without you having
to say which shell you are in.

What the guard cannot see, scripts, cron jobs, MCP servers that spawn the CLI
and the `command claude` hatch itself, is listed in
[What this does not protect against](LIMITS.md).

## Completions

```sh
eval "$(agpin completion bash)"     # bash
eval "$(agpin completion zsh)"      # zsh
agpin completion fish | source      # fish
```

Tab-completes every subcommand, its flags, and profile names, whichever name
you invoke it as. Profile names are looked up by calling back into `agpin` at
completion time rather than being written into the script, so a profile
created after you last sourced it still completes; nothing needs re-sourcing
except when a new release adds a subcommand.

Printed rather than installed, for the same reason `guard` is: this tool never
writes to a completion directory or your rc file. Add the line above to it
yourself, once, and `agpin shellrc` prints it beside the other two lines worth
having, already in the right dialect for your shell.

## Output levels

Default output states what happened and the next command, in a few lines,
because `new`, `app` and `which` run many times over a profile's life and the
reader has seen the reasoning before. `--explain` on any of those, or on
`doctor` and `verify`, restores the full rationale, and setting
`AGENT_PROFILE_EXPLAIN=1` does the same for every command at once. Compare
`agpin new brygga` and `agpin new brygga --explain` in
[the setup guide](SETUP.md#step-2-create-one-profile-per-account).

`doctor --quiet` and `verify --quiet` go the other way: nothing at all on a
clean run, and the exit code carries the answer, for cron entries and shell
hooks. A finding still prints in full.

<!-- BEGIN GENERATED: example doctor-quiet (tools/gen-doc-examples.sh) -->
```sh
agpin doctor --quiet
```
<!-- END GENERATED: example doctor-quiet -->

Neither level changes what a command does, what it exits with, or what
`--json` and `--report FILE` contain: those are the same document at every
level. Only the terminal gets shorter or longer. `--quiet` wins over
`--explain` whichever order they are given in. How that falls out of the way
output is produced is in [One stream, two renderings](DESIGN.md#one-stream-two-renderings)
and [the audit schema](AUDIT-SCHEMA.md).

## The sessions server

Every profile's root holds a month or more of transcripts, and the only way
back into them used to be `claude --resume`, one session at a time. So each
profile gets a small MCP server over its own `projects/` directory, and a
session can ask what an earlier one did without leaving Claude Code:

| Tool | What it returns |
| --- | --- |
| `list_projects` | one row per working directory, with counts and the retention window |
| `list_sessions` | identity columns and a 200-character first-prompt preview, filterable by project, date range, branch and a substring, paged |
| `session_summary` | last reply, tool histogram, files touched, subagents; no conversation |
| `get_session` | messages by record range, 2,000 characters each, tool results and thinking left out unless asked for, 40,000 characters per call at most |
| `get_message` | one message whole, up to a hard cap |
| `search` | substring or regex over prompts and replies, returning pointers |

`new` registers it, in the root's own state file and through `claude mcp add
--scope user` pinned to that root, which is why the root is no longer
strictly empty after `new` (docs/FACTS.md F23). The registered command is
`agpin mcp serve --root <root>`: this tool's own launcher, at its installed
path, which finds the server's Python environment beside itself and refuses
to start unless `CLAUDE_CONFIG_DIR` names that same root. Claude Code hands a
stdio server its own environment (F24), so the pin and the server's scope are
the same variable in the same process tree, and a registration copied into
another root fails visibly in `/mcp` instead of serving the wrong account's
transcripts. The server itself opens `projects/` and nothing else: never the
credential, never the account block of the state file, never `history.jsonl`
or the paste cache. It is stdio only, one per session, with no port.

<!-- BEGIN GENERATED: example mcp-status (tools/gen-doc-examples.sh) -->
```sh
agpin mcp status
```

```
brygga         on      /Users/alex/.claude-brygga/.claude.json
havnelab       on      /Users/alex/.claude-havnelab/.claude.json
```
<!-- END GENERATED: example mcp-status -->

<!-- BEGIN GENERATED: example mcp-off (tools/gen-doc-examples.sh) -->
```sh
agpin mcp off brygga
```

```
Sessions server: off (removed from /Users/alex/.claude-brygga/.claude.json)
```
<!-- END GENERATED: example mcp-off -->

<!-- BEGIN GENERATED: example mcp-on (tools/gen-doc-examples.sh) -->
```sh
agpin mcp on brygga
```

```
Sessions server: on (registered in /Users/alex/.claude-brygga/.claude.json)
```
<!-- END GENERATED: example mcp-on -->

`mcp status` is read-only, `mcp off` means gone from the state file and read
back to check, and `mcp on` is the same registration `new` makes. `list`
shows the same state, `doctor` reports a registration that names another root
or a command that is gone as D19, and a `sessions` entry that is somebody
else's is shown as `foreign` and never touched. Off means the next session in
that root starts no server; a server already running inside an open session
lives until that session exits.

The server runs on Python and the framework FastMCP. Its environment is built
once, at install time, beside the installed tree, from a lockfile that ships
inside the signed release: [Install](INSTALL.md#the-sessions-servers-environment)
says how, and what it costs on a Mac with no developer tools. A session start
then takes about one second longer and touches no network. The design, the
measurements behind it and what it renegotiates in
[Why nothing is shared](DESIGN.md#why-nothing-is-shared) are in
[the proposal](proposals/2026-09-15-sessions-mcp.md); the server's own README
is [`server/README.md`](../server/README.md).

## explain

`agpin explain` states the scheme in plain language and shows where this
machine's data currently lives, for when you come back to this in six months.
It is the whole layout, always, and not the `--explain` flag above:

<!-- BEGIN GENERATED: example explain (tools/gen-doc-examples.sh) -->
```sh
agpin explain
```

```
THE SCHEME

A profile is one account, kept apart from every other account by giving it its
own config root. The root is chosen by an environment variable, and everything
the agent stores goes under it: settings, session transcripts, auto memory,
commands, skills, agents, plugins, plans, backups, the credential and the state
file. Two profiles therefore share no file at all.

Credentials are keyed to the root path. That is what makes separate roots give
genuinely separate logins, and it is also why a root can never be moved or
renamed: doing so invalidates its login. Create a new profile instead.

Pinning to the default root is not the same as not pinning. When the variable
is set, the state file moves inside the root, so the two produce different
layouts. Anything that runs with nothing pinned writes to the default root,
which is exactly what doctor reports.

TWO IDENTITIES, AND THEY CAN DISAGREE

A profile has two of them. The app data directory selects the desktop app's own
login, the one whose name you see in the app. The config root selects where its
embedded agent writes. They are independent, and they have already been seen
disagreeing: the app showed the right account for weeks while its sessions were
writing into another account's root. So the app naming an account is not
evidence that anything is pinned. Read both, always.

The terminal and the desktop are pinned by different means. In a terminal the
variable is exported, by run, shell or env. The desktop app gets it through
`open --env`, which is what `desktop` runs and what the applet `app` generates
contains. There is no third way that works: a bundle wrapping a shell script
never launches, and running the app binary from a terminal kills it when the
shell exits.

One more asymmetry worth knowing. A status line shows which root a terminal
session is using, but the desktop pane renders none, so there is no equivalent
indicator inside the app. For the desktop, the launcher is the guarantee and
doctor's D13 is the check.

NOTHING IS SHARED

No symlinks, no shared parent, no copied settings, no seeding a new root from an
old one, no template. A new root holds nothing from any other profile. That
means it also has none of the hooks or guardrails your other profiles have, and
the fix for that is to set them up in the new root directly, never to copy them
across. The one thing new does put into a root is a registration for the root's
own sessions server, one line in the root's state file written by the agent's
own CLI: it names this tool and this root, it is the same shape in every root,
and it points at nothing outside the root, so two roots still share no file and
no content. mcp off takes it out again.

WHAT THIS TOOL STORES

Only the registry, at the path shown below, outside every config root. One
plain key=value file per profile holding the agent, the root, the app data
directory, the applet that launches it and the creation date. Nothing else. The
label you see in a prompt is
derived from the pinned root every time it is needed, so it cannot drift away
from the root it names.

The tool never reads, writes or moves a credential, never edits the agent's own
state files by hand, and never migrates data between roots. The one change it
makes to a state file, the sessions server registration, goes through the
agent's own CLI pinned to the root, so the file is only ever written by the
program that owns it.

ON THIS MACHINE

  registry    /Users/alex/.config/agent-profiles

  claude
    variable       CLAUDE_CONFIG_DIR
    binary         claude
    default root   /Users/alex/.claude
    unpinned state /Users/alex/.claude.json
    desktop app    /Applications/Claude.app

  profiles
    brygga       root      /Users/alex/.claude-brygga
                 app data  /Users/alex/Library/Application Support/Claude-Brygga
                 launcher  (none; agpin app brygga)
    havnelab     root      /Users/alex/.claude-havnelab
                 app data  /Users/alex/Library/Application Support/Claude-Havnelab
                 launcher  (none; agpin app havnelab)

AFTER AN AGENT UPDATE

  Run: agpin verify
  It re-checks the behavioural assumptions this tool rests on and says
  which it could not check. The answers and their evidence are recorded
  in docs/FACTS.md in the repository.

  There is no single agent version on a machine like this. Each desktop
  profile downloads its own copy under its app data directory, so they
  update independently of each other and of the CLI.
```
<!-- END GENERATED: example explain -->
