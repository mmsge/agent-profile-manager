# Feature-gap review: Agent Profile Manager

> `agent-profile`, installed as `agpin`, keeps several Claude accounts apart on
> one Mac by giving each its own config root, pins the terminal, the desktop
> app and the IDEs to that root, audits that the separation holds, and gives
> each profile a read-only server over its own transcripts. This review asks
> what it does not do yet, for the people it is meant for.

Reviewed at version 0.11.0, commit `7c73641`, on 2026-09-15, one week after
[the September tool review](2026-09-07-tool-review.md). The review was done by
Claude Code with Markus interviewed on the lens, the output, the team and the
decisions each finding turned on. Nine research agents each took one area of
the tool, ran it in throwaway fixtures on Linux, read the code, the tests and
the documentation, and wrote up their findings with `file:line` evidence. Two
of them were allowed on the web: one read the current Claude Code
documentation, the other the documentation of Codex CLI, Copilot CLI, Gemini
CLI and ollama. Nothing ran on a Mac, so every claim that depends on macOS
behaviour says so and carries a re-check recipe in the style of
[the facts file](../FACTS.md).

## Scope and method

The whole repository was read: the 5,287-line script, the 451 bash tests and
their harness, the Python sessions server and its tests, the installer, the
three workflows, the packaging, and every document under `docs/`. The tool
was run the way the harness runs it, with `HOME` and every `AGENT_PROFILE_*`
variable redirected into a throwaway tree, against the real Claude Code 2.1.272
where a registrar was needed and against the harness's stand-ins for `open`,
`osacompile`, `osadecompile`, `security`, `defaults` and `pgrep` where a macOS
path was exercised. The full suite passes on Linux. Fixture roots, invented
transcripts and invented credentials were built by hand for every rule that
had to be made to fire; no real root, transcript or credential was read.

The nine areas were the first run, daily use from the terminal, the audit,
the launch paths outside the terminal, the sessions server, the team rather
than the individual, portability, what Claude Code itself now offers, and what
the other agents would need. The working files behind this document are not
committed; the findings that survived cross-checking are here.

Decisions from the interview. The ranking follows from them.

| Question | Answer |
| --- | --- |
| What counts as a gap | Gaps for the coworker audience, gaps against other approaches, and gaps for the team. The author's own daily use is out of scope |
| Output | This report, plus one issue per gap accepted |
| What coworkers have said | Nobody has tried it yet. Many are on Windows |
| How deep the research may go | Read the code and run the tool in fixtures. Claude Code's documentation and the other vendors' documentation may be read |
| The team | Managed Macs under Jamf or Intune. Several coworkers share one customer, including the same repository under different accounts |
| Other agents that matter | Codex CLI, Copilot CLI or Gemini CLI, and ollama |
| A declared map of directories to profiles | Yes, opt-in, feeding both the audit and the pin. D03 stays as it is |
| What the audit may read | Claude Code's settings files, managed settings, shell rc files and LaunchAgents, for a known set of keys. Never run the agent's own CLI to answer a question |
| Managed settings that set the config directory or force an organisation | Report it, and `new` refuses on such a machine |
| Windows | No preference stated. The probe is the gate and both recipes are carried below it |
| `remove --purge` on a root holding a credential file | Leave the file, delete the rest, say so |
| The evidence report | Per engagement, scoped to one profile, read by the customer's security officer unaided |
| `doctor` on a normal developer machine | Must be able to exit 0. D09 and D16 become advisory |
| The sessions server | Keep it. Drop regex search. Export comes first, delete waits |
| Writes outside the registry, the roots and the applets | None. No rc file block, no Dock plist, no seeded editor settings |
| The bigger half of the audience | An even split between the desktop app and the IDE |
| Small bugs found on the way | Fix them in a separate pull request now |
| Other agents, in what order | Codex first, Gemini next, Copilot as a limits paragraph and two rules, ollama as a different noun later. After the Windows question is settled |

Every suggestion names a model and an effort level, as the September review
did: Claude Fable 5.1 (`claude-fable-5-1`) for long-horizon architectural
work, Claude Opus 5 (`claude-opus-5`) for design and security work, and
Claude Sonnet 5 (`claude-sonnet-5`) for well-specified documentation and
polish. Effort is one of `low`, `medium`, `high`, `xhigh` or `max`.

## Summary

The premise holds. Claude Code 2.1.272 has no account switcher, no `--profile`
and no per-project account; `/login` still replaces the one credential a root
holds, and `CLAUDE_CONFIG_DIR` is now recommended by Anthropic's own hosting
documentation for per-tenant isolation. Nothing has overtaken the tool. Two
things have grown up beside it that it cannot see: Anthropic profiles under
`~/.config/anthropic`, a credential store outside every root that can outrank
a working login, and managed settings that can set the config directory or
refuse a login for a whole machine.

Three themes decide the ranking.

**The audit cannot see a consistent mistake.** D03 catches a repository that
appears under two roots. It does not catch a repository worked under the wrong
root and never the right one, which is the mistake a stale tmux pane, a global
export or a redirect in a settings file produces, and it never includes the
default root, so an unpinned run that touched a customer's repository is
reported as a count and never named. Identity is checked for presence only,
so two profiles signed in to the same account pass. Nothing reads the settings
files, rc files, launch agents and policy files that can pin or redirect the
agent from outside this tool. These are the gaps that let one customer's data
reach another, and the interview answers open every one of them to a rule.

**The first run and the fleet.** Nobody has tried the tool yet, and the first
run is an eight-step document with five hand-offs, no `status`, a `doctor`
that exits 2 on a correct machine before login and can never exit 0 once an
IDE extension is installed, a guard that is a manual rc edit nothing audits,
and a sessions server that reports `on` when its environment was never built.
For a team on managed Macs there is nothing an MDM can deploy, no version
pinning, no inventory, and a shared repository makes `doctor` red for good.

**Windows is still the biggest signal, and Linux is unstated.** Six Windows
facts, none verified, and one hour on one machine settles five of them. The
whole terminal half of the tool runs on Linux and therefore in WSL, the suite
passes there, and no document says so; the README opens with "one Mac" and
the formula refuses anything else. On that platform `--purge` deletes the
credential file while printing that it never touches credentials.

Alongside the gaps the agents found a dozen bugs. Those are fixed in a
separate pull request rather than filed, and listed at the end.

## Findings by area

### The first run

Part 1 of the setup guide works exactly as written in a fixture: install,
`new` twice, the rc lines, `doctor`, `app`. What a newcomer meets around it is
the problem. `agpin new` on a Mac without a working `python3` dies with a raw
`python3: command not found` and then `could not create root ''`, because
`cmd_new` is the one command without the `need python3` check and the
prerequisite table names `cosign` and `uv` but not `python3` or the Command
Line Tools. The installer avoids `python3` so that the Command Line Tools
dialogue never opens during an install, and the dialogue arrives one command
later instead.

Nothing records which account a profile is for. Two profiles signed in to the
same account produce a clean `doctor`, which is the copy-paste slip the README
opens with. The guard is a manual rc edit that nothing installs or audits, and
it fails open: uninstall the tool or lose `~/.local/bin` from `PATH` and
`claude` runs unpinned again with one ignorable shell error. The printed rc
block mixes a bash completion line with a zsh prompt line. `doctor` cannot
tell "setup unfinished" from "isolation broken": a correct three-profile
machine before login prints three D05 findings and exits 2, the same code as a
real leak, which makes `--quiet` in cron useless. On an adopted machine D01,
D02 and D09 are permanent findings no command resolves and nothing records an
acknowledgement, so the handover report never comes back clean. The sessions
server is unaudited in both directions: `mcp status` says `on` while `mcp
serve` cannot start for want of `server/.venv`, and a profile created before
`claude` was on `PATH` stays `off` forever with no note. There is no second
machine story and `version --check` prints the curl one-liner to Homebrew
installs.

### Daily use from the terminal

The daily command is good and underadvertised: with the guard on,
`claude brygga` is thirteen characters. The central gap is that the pin is
per shell and the work is per directory. Once pinned, the guard passes
straight through, `run` overrides an existing pin silently, and a tab pinned
to one customer in the morning runs that account against another customer's
repository in the afternoon with nothing noticing. direnv wins this axis in
one line and the repository never mentions it. tmux makes the mistake happen
by accident: measured twice, a window opened from a shell pinned to one
profile got the tmux server's environment, which was another profile's root,
because `update-environment` does not list the variable. The guard cannot
refuse, because something is pinned.

There is no `agpin exec`, so scripts, Makefiles and cron have to hand-export
the path, which is the duplication the README opens by claiming to remove.
Nothing audits cron, launchd, editor tasks or an MCP server that spawns the
CLI. fish gets a guard, completion and a prompt, but `env` prints `export`
with no fish form while the fish guard tells the user to eval it.
`which --label` prints a label for a root that does not exist and for a
profile removed a minute ago. Completion registers only for `agpin`, so
`claude bry<TAB>` completes nothing, and the picker offers three targets when
five exist.

Claude Code itself has not overtaken any of this. Its help on 2.1.272 contains
no occurrence of "profile", "account" or "config dir". What has moved is the
surrounding surface: `claude auth status --json` now reports the config
directory, `project purge` does part of offboarding, and `setup-token`,
`--bare`, `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` open an
authentication path that sits outside the per-root Keychain model nothing
here inspects.

### The audit

A 33-row leak-path table was built and every row checked against the rules.
The residue of an unpinned run is caught; the launch itself never is, which is
by design. The misses that matter are the consistent ones. D03 never includes
the default root, so a transcript for a customer's repository in `~/.claude`
and in that customer's root produces D01 and no D03, and the repository is
never named; no finding carries a date; D01 counts subagent transcripts as
sessions. A repository worked only ever under the wrong root is invisible,
because nothing declares which repository belongs to which profile. No rule
reads rc files, `settings.json` `env` blocks, managed settings or
LaunchAgents: a global export in `.zshenv`, an `env` block redirecting the
config directory and a LaunchAgent running `claude -p` all produced a clean
run. Identity is presence only: two roots with the same account pass, an
empty `.credentials.json` passes, and `list` and D05 disagree about "signed
in" in two directions.

The evidence report is not yet evidence: `tool_version` is self-reported, the
document records neither the `AGENT_PROFILE_*` overrides in force nor which
`security`, `defaults` and `osadecompile` answered (the harness's stand-ins
produced real-looking Darwin documents), the machine identity is `uname -n`
and a possibly empty `$USER`, there is no scope, no retention, no hash and no
baseline diff, though two runs a second apart differ only in `generated_at`,
so a diff is cheap. `doctor` and `verify` do not talk: after an agent update
`doctor` prints D05 for every profile with no drift hint while `verify` says
"fix the tool", and `verify` exits 4 as the steady state on any Mac without
an IDE. No cron or launchd recipe exists despite the docs promising cron use,
and `applet_scan` swallows `find` errors, so a TCC denial on `~/Desktop` from
a job would make D14 pass silently. D13 misreads a second `--env` after the
pin as `wrongroot` and reads only the first `do shell script` line, so an
applet with a second, unpinned launch line passes.

### The launch paths

The IDE-first coworker has no morning. `code` and `idea` refuse into a
running editor, and `ide_running` asks whether any VS Code is up rather than
whether one sharing this user data directory is, so after one `--new-instance`
every plain launch is refused until the editor is quit. `doctor` can never
come back clean on a machine with a Claude Code extension: a perfect fixture
exits 0, then exits 2 forever after `mkdir ~/.vscode/extensions/anthropic.claude-code-*`.
Nothing inside the app or the IDE window names the account; the only reliable
answer is a `find` in a terminal, which is where the person who opened the
app is not. `desktop` and `app` never check whether the app is running, so
`app` says "Repaired" and the next click focuses the instance still carrying
the old pin. `app` generates no icon, so two customers' Dock tiles are
identical. D17 reads `persistent-apps` only and says so only in the JSON.
Three holes in the launcher audit each hide a wrong launcher: a shell-script
launcher is invisible to D14, an applet one folder deeper than
`~/Applications` is past `find -maxdepth 5`, and `app` writes a launch line
pointing at a bundle that is not on disk while `desktop` refuses. Raycast,
Alfred, Shortcuts, login items and the browser extension appear nowhere, and
the docs never say the useful half, that a Spotlight or Raycast hit on the
applet is pinned. `ide_def` knows three IDEs; Windsurf and Zed are unknown to
D16, and `code --app Zed --new-instance` hands Zed a VS Code flag.

### The sessions server

Confinement holds: with a planted symlink under `projects/` into a second
root, a `tool-results/` symlink to `.credentials.json` and a transcript naming
a traversal path, the store returned only the one real session and no canary
reached the output. Around that core: a server whose environment was never
built reports `on` in `mcp status`, nothing in `doctor`, and only "Connection
closed" in `/mcp`. `search` returns the newest twenty hits with no cursor and
no total. `search(regex=True)` is a backtracking hazard: a six-character
pattern against a 200-character cap, 24 repeated characters cost 1.6 seconds
and 40 did not return in two minutes, hanging the session's tools, and the
model chooses the pattern, so stored text can trigger it. `session_summary`
returns two uncapped lists in a design that caps everything else. There is no
export, no redaction, no delete and no statistics; bare dates are UTC. The
launcher compares paths as strings while the server compares real paths; the
launcher hands the session's `PYTHONPATH` to the interpreter; the store holds
the whole root in memory for the session's life, measured at 74 MB resident
for 53 MB on disk. Upgrades that move the install path go stale per root with
no `mcp on --all`, and `install.sh --uninstall` leaves a dead registration in
every root after deleting the command that removes it. The desktop app is
verified and undocumented in the desktop guide; the IDE extensions have no
fact at all. The Python tests need `uv` and the network, the no-`uv` install
path is never exercised in CI, and the bash suite does not run the Python
half. And the documentation now says of the transcript format that "scripts
that parse these files directly can break on any release".

### The team rather than the individual

Nothing an MDM can deploy: a release is a tarball, a checksum file and two
Sigstore bundles, every location is an environment variable and nothing reads
a file, so a Jamf or Intune payload has no file to write. The Homebrew formula
on `hovud` pins v0.10.0, whose tag has no `server/`, while its install block
runs `uv sync` on it, so `brew install agpin` fails until v0.11.0 ships. No
inventory: `version --check` is per machine with no `--json`, `doctor --json`
is the only machine-readable state and nothing collects it, and there is no
fleet, customer or run identifier to key ten documents on. Nothing installs
or audits the guard. A shared repository makes `doctor` red for good, with
the wording "One of these accounts has worked in the other's project", which
in the scenario Markus describes is the intended workflow. Profile identity is
machine-local: the registry holds no customer, label or owner, `created=` is
written and never read, and the registry directory is created world-readable.
Claude Code's managed settings are the one baseline mechanism that costs the
"nothing is shared" invariant nothing, and the tool cannot see them. `remove`
never calls `emit`, so it has no `--json` and no `--report`, and afterwards
the machine cannot tell "removed" from "never existed". The evidence document
names every other customer on the machine. There is no support bundle.

This changes the recommendation in issue #22. Managed settings by MDM now
beats the marketplace plugin for hooks and permissions: no network fetch at
`new` time, no second unsigned channel, no per-root step to forget. Option 1,
visibility, should land regardless. Option 2 is the only one that breaks the
invariant. Option 3 stays right for plugin content. And D19 is taken.

### Portability

Linux runs the entire terminal half: `new`, `list`, `env`, `path`, `which`,
`run`, `shell`, `guard`, `completion`, `mcp on|off|status`, `doctor`,
`verify`, `explain` and `remove` all work, eleven rules run, two are limited,
six report `not_run` with an honest reason, and the suite is 451 tests and no
failures. No user-facing document says so. The README opens with "one Mac",
the install guide says "no dependencies beyond a stock macOS", the formula
carries `depends_on :macos`, and the only Linux sentence a user could find is
in the middle of the audit guide. `new` on Linux creates
`~/Library/Application Support/Claude-<Name>`, a macOS path with no meaning
there.

Two bugs sit on that platform. `remove --purge` deletes `.credentials.json`
out of the root while printing that the tool never touches credentials, then
prints a `security delete-generic-password` line for a Keychain that does not
exist; the test meant to catch it only asserts that `security` was not called.
D16 fires for an installed extension and tells the reader to launch it pinned
with `agpin code`, which refuses on Linux. In a WSL remote window the
extension lives under `~/.vscode-server/extensions`, which D16 does not scan,
and D17 and D18 say "this is Linux" when the true statement is that a
Windows-side root and app data directory are three centimetres away and were
not looked at. A clean `doctor` off macOS prints one green line and nothing
about the six rules it skipped.

Windows: six facts, none verified. The 671-line probe is ready and careful,
and needs one machine, Claude Code, a signed-in desktop app and one human
minute for W05's pin. A Windows coworker has no recipe today although W01,
W02, W04 and W05 already contain a working per-window PowerShell function,
both traps and a leak test. A PowerShell `agpin` is the one candidate to skip:
even a four-rule `doctor` subset duplicates D01, D02, D03 and D05 and creates
a second producer of the audit schema.

### What Claude Code itself now offers

The account question is answered above. The rest of the surface, from the
current documentation: `claude auth login|logout|status` are `/login` and
`/logout` hoisted out of a session, and `auth status --json` exits 1 when
logged out, a free per-root login check. Anthropic profiles in
`~/.config/anthropic`, selected by `ANTHROPIC_PROFILE` or an active-profile
file, with an `oidc_federation` profile outranking a working `/login`, are the
one genuinely new credential mechanism and they sit outside every root.
`CLAUDE_CONFIG_DIR` may be set in the managed `env` block, and
`forceLoginOrgUUID` makes Claude Code exit at startup for a login to another
organisation; on a customer-managed Mac both are fatal and invisible. Project
and local settings can no longer set `CLAUDE_CONFIG_DIR`, `HOME` or `TMPDIR`
since v2.1.251, which closes a repository-side attack the tool had no rule
for. `CLAUDE_CODE_PLUGIN_SEED_DIR`, `--settings` and `syncClaudeAiSkills`
each give a baseline without copying a file into any root, while
`CLAUDE_CODE_PLUGIN_CACHE_DIR` can move plugins out of a root entirely and
`plansDirectory` can move plans into the repository. The background-session
supervisor runs per root and outlives the terminal, and `claude agents --json`
lists its sessions without a TTY. claude.ai connectors are fetched only for
the active login, so per-root separation already separates connectors, which
the docs never say. The desktop app's Customize set syncs through the claude.ai
account and follows neither the app's login nor the root, so F18's two
identities are three.

FACTS drift is scope, not contradiction. F08's list of what a root owns has
roughly tripled and matches a 2.1.272 root, with `todos/` now documented as
legacy. F09, F12, F23, F24 and F25 are confirmed unchanged. F11 carries the
new warning about the transcript format. F20's count of extension settings is
stale by at least two. `LIMITS.md` is missing an Anthropic profile, a managed
`env` block, `claude --cloud` from a pinned shell, and a background supervisor
still running for a root after its terminal is gone.

### The other agents

Codex CLI fits, and fits better than Claude does. `CODEX_HOME` is resolved in
one function, everything lives under it, and the credential follows in both
storage modes: `$CODEX_HOME/auth.json` in file mode, or a keyring entry under
service `Codex Auth` with the account derived from the canonicalised path.
Two inversions from Claude's facts: Codex canonicalises before hashing, so
D10 loses its cause and gains a symlink caveat, and `CODEX_HOME=~/.codex`
appears to be the same login as unset, so D11 has nothing to report. Gemini
CLI fits: `GEMINI_CLI_HOME` overrides the home directory and every global path
is built from it, `oauth_creds.json` is a plain file inside the tree, and D05
becomes an existence check with no Keychain at all; the frictions are that
the variable names a home rather than the root, a Workspace profile needs
`GOOGLE_CLOUD_PROJECT` exported beside it, and the runtime directory can be
`~/.cache/.gemini`. Copilot CLI does not fit: `COPILOT_HOME` moves config,
sessions and logs, but the OAuth token goes to the system keychain under the
flat service name `copilot-cli`, so two roots read one credential; it has
native multi-account instead, and its seat usually comes on the consultant's
existing GitHub identity, so there is no second login to keep apart in the
common case. ollama fits partly and the premise barely applies: no account,
no `OLLAMA_HOME`, `OLLAMA_MODELS` moves the blobs only, and the one real
exposure is Ollama Cloud, whose control is `OLLAMA_NO_CLOUD=1`.

The seam is more Claude-shaped than its comment suggests. Five `agent_def`
fields carry, seven need a different shape (the credential must become a
probe with three answers rather than a service string; the hash needs a
per-agent width, prefix and canonicalise flag; the Keychain scan pattern and
the `-a "$USER"` are Claude-only), four new fields are needed, five rules and
the identity reader know Claude's layout directly, the ledger cannot say a
rule does not apply to an agent, and the `which --label` fast path is
single-agent by construction and is where a silently wrong prompt would come
from. Codex and Copilot are both first-class on Windows, so settling the port
question before `KNOWN_AGENTS` grows is cheaper than after.

## Suggested improvements

Ranked. The first four close the audit's blind spots on leakage, which is what
the tool sells; the next six make the first run and the fleet workable; then
the launch paths, the sessions server, portability, the other agents and the
documents. Numbers for new rules and facts are "the next free one" rather
than fixed here, because D19 and F25 are the last taken and several
suggestions each add one.

### 1. Bind directories to profiles, and refuse a pin that disagrees

**Why this matters:** The pin is per shell and the work is per directory.
Once pinned, the guard passes through and `run` overrides silently, so the
one-sided mistake, a customer's repository worked under another customer's
root and never the right one, is invisible to D03 until the correct account
happens to work there later. Markus accepted an opt-in declaration that feeds
both the audit and the pin. D03 is untouched: it needs no configuration and
must keep needing none, and the new rule reports its own coverage, so an
empty declaration reads as `not_run` with a reason rather than as a pass.

**Labels:** security, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Add an opt-in, repeatable `paths=` key to a profile's registry entry, set
> by `agpin bind <profile> <dir>` and removed by `agpin unbind <profile> <dir>`,
> absolute paths only, canonicalised the way roots are. Add a `doctor` rule at
> the next free number that reads the same transcript `cwd` values D03 reads
> and reports a transcript under root A whose `cwd` lies under a directory
> bound to profile B, and a transcript under the default root whose `cwd`
> lies under any bound directory, naming the repository, the roots and the
> oldest and newest transcript modification times. When no profile binds
> anything the rule is `not_run` with the reason "no directories are bound",
> never `pass`. Teach the guard one comparison: with a pin in place and the
> current directory bound to another profile, refuse with the same shape of
> message it uses for the unpinned case, naming both profiles and offering
> `agpin <right-profile>` and `command claude`. Give `agpin which` a `PATH`
> argument that answers which roots hold transcripts whose `cwd` is that
> directory, with counts and last dates, and have plain `agpin which` print
> the binding for the current directory beside the pin, saying when they
> disagree. Document direnv and tmux in `docs/USE.md`: `agpin env <name>` is
> the right line for an `.envrc`, and `set -ga update-environment ' CLAUDE_CONFIG_DIR'`
> in `~/.tmux.conf` is what stops a new window taking the server's pin. Keep
> the bindings in the registry, never in a marker file inside the customer's
> repository. Cover it in `tests/cases/`, update `docs/AUDIT.md`, the doctor
> reads declaration and the schema, and run the generators.

**Done when:**

- `bind`, `unbind` and `which PATH` exist with tests.
- The new rule fires on the one-sided fixture that D03 stays silent on, and
  reports `not_run` when nothing is bound.
- The guard refuses a pin that disagrees with the current directory's binding.
- `docs/USE.md` covers direnv and tmux.

### 2. Make D03 name the repository and the date, include the default root, and accept a dated shared declaration

**Why this matters:** The customer's security officer asks one question: did
my repository ever run under another account, and when. Today D03 never
includes the default root, so an unpinned run that touched a customer's
repository is D01 "holds N session(s)" and the repository is never named, no
finding carries a date, and D01 counts subagent transcripts as sessions. For a
team sharing a customer, the same repository under two roots is the intended
workflow, and D03's wording asserts a leak forever. Issue #61 proposes dating
for D12; this is the same change applied to the rules that carry the actual
leak, and the two should land as one design.

**Labels:** security, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Extend D03's input with the default root as a pseudo-root labelled
> `unpinned` when no profile claims it, so a `cwd` shared between `~/.claude`
> and a profile root becomes a D03 finding naming the path. Give D01 and D03
> findings `first_written` and `last_written` fields from the modification
> times of the oldest and newest transcript involved, names and `stat` only,
> rendered in prose as "between 2026-06-01 and 2026-09-12", and give D12 the
> same fields so that issue #61 closes with this. Count sessions as top-level
> `*.jsonl` under each project directory and report subagent transcripts
> separately in `list`, D01 and the document. Add a repeatable, dated
> `shared=<absolute path>` key to the registry entry, set by
> `agpin share <profile> <path>` and removed with `--remove`, and split D03's
> output: a path declared shared by every profile it was found under is
> reported at a new, lower kind, `note`, naming the profiles and the date of
> each declaration; a path declared by some and not others stays a finding,
> because that asymmetry is the mistake worth catching; undeclared overlap
> behaves exactly as today. On macOS compare `cwd` values case-insensitively
> and also by real path when the directory still exists. Keep every field in
> the JSON document and update `docs/AUDIT-SCHEMA.md`.

**Done when:**

- A transcript for one path in the default root and in a profile root
  produces a D03 finding naming the path.
- D01, D03 and D12 findings carry dates in prose and in the document.
- A path declared shared by every profile that holds it is a `note`, and one
  declared by only some is still a finding, with tests for both.

### 3. Read the configuration outside the roots that can pin or redirect the agent, and refuse to create a profile a policy would defeat

**Why this matters:** A global export in a shell startup file, a
`CLAUDE_CONFIG_DIR` in a `settings.json` `env` block, a managed policy that
sets it or that forces an organisation, a LaunchAgent running `claude -p`, an
Anthropic profile in `~/.config/anthropic` whose federation mode outranks a
working login, and `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` in the
environment each pin or authenticate every session on the machine from
outside this tool, and every one of them produced a clean `doctor`. A
redirect in `~/.claude/settings.json` is worse than leaking to the default
root, because D01 and D18 then go quiet. Markus allowed the audit to read
these files for a known set of keys and never to run the agent's own CLI, and
chose that `new` refuses on a machine whose policy would defeat the profile.
The tool's own facts file asserts that a settings-file `CLAUDE_CONFIG_DIR`
cannot take effect; the 2.1.272 binary's own text and the current
documentation say it does, so a fact has to be settled first.

**Labels:** security

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Establish three facts in `docs/FACTS.md` first, each with a re-check recipe:
> what a `CLAUDE_CONFIG_DIR` in the `env` block of `~/.claude/settings.json`
> does to an unpinned launch at 2.1.272 (the leak test after such a launch
> settles it); where the machine-level managed settings live on macOS
> (`/Library/Application Support/ClaudeCode/managed-settings.json`, its
> `managed-settings.d/` directory and the `com.anthropic.claudecode` managed
> preferences domain, per the current documentation) and which keys among
> `env.CLAUDE_CONFIG_DIR`, `forceLoginOrgUUID`, `forceLoginMethod`,
> `managedMcpServers`, `allowManagedMcpServersOnly` and
> `strictPluginOnlyCustomization` they can carry; and how an Anthropic profile
> under `~/.config/anthropic` is selected and when it outranks `/login`. Then
> add one rule, "something outside this tool sets the config root or the
> login", reading only: the `env` key of `~/.claude/settings.json` and of every
> registered root's `settings.json`; the managed sources above, by key name;
> assignments of `CLAUDE_CONFIG_DIR`, `ANTHROPIC_PROFILE`, `ANTHROPIC_API_KEY`
> and `CLAUDE_CODE_OAUTH_TOKEN` in `~/.zshenv`, `~/.zprofile`, `~/.zshrc`,
> `~/.bash_profile`, `~/.bashrc`, `~/.profile` and `~/.config/fish/config.fish`,
> matched by a pattern that captures the variable name and the value and
> nothing else on the line; every `~/Library/LaunchAgents/*.plist` whose
> program names the agent binary, with its `EnvironmentVariables` block, read
> with `plistlib` from the file; the names under `~/.config/anthropic/configs/`
> and each profile's `auth_mode` field and nothing else; and the same auth
> variables in the running environment. Report a value naming no registered
> root as a finding and a value naming one as a note, report a managed policy
> that sets the config directory or forces an organisation as a finding that
> says every profile on this machine is pinned to one root or one login by
> policy, and tell the reader that the server-managed half is visible only
> through `/status` inside a session. Make `new` refuse on a machine where a
> managed source sets `CLAUDE_CONFIG_DIR` or `forceLoginOrgUUID`, with the
> message naming the file and the key, and an `--anyway` for the person who
> knows. Carry the findings in the JSON as a `managed_settings` object. Add
> managed settings, Anthropic profiles, LaunchAgents, `claude --cloud` from a
> pinned shell, the background supervisor, `--bare` and token authentication to
> `docs/LIMITS.md`. Correct the aside in F20. Never run `claude` to answer any
> of this.

**Done when:**

- The three facts are recorded with statuses and recipes.
- The rule fires on a global export, an `env` block redirect, a LaunchAgent,
  an Anthropic profile and a managed policy, each in a fixture, and stays
  quiet on a clean machine.
- `new` refuses on a fixture with a managed `CLAUDE_CONFIG_DIR`.
- `docs/LIMITS.md` names every path above.

### 4. Record which account a profile is for, and report two profiles on one account

**Why this matters:** Identity is checked for presence only. Two profiles
signed in to the same account pass the audit wearing the tool's own labels,
which is the setup the tool exists to prevent. A re-login into the wrong root
has nothing to compare against because the registry holds no expected
account, an empty credential passes, and `list` and D05 disagree about
"signed in" in two directions. The same-account rule needs no configuration
at all and would catch the copy-paste slip on every machine.

**Labels:** security

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Add a rule at the next free number that reports two registered roots
> carrying the same `organizationUuid` and `emailAddress`, using the identities
> `emit_profiles` already reads, so no new file is opened. Add optional
> `account=` and `organization=` keys to the registry entry, set by
> `agpin new --account <email>` or by `agpin claim <profile>`, which copies the
> root's current identity into the registry once, and a companion rule that
> reports a root whose `oauthAccount` no longer matches its record. Add an
> optional free-text `note=` key, set by `agpin new --note` or `agpin note
> <profile>`, shown by `list` and `explain`, so a machine can say which
> customer `torg` is six months later. Give `list` a three-state identity line,
> "signed in", "account on record, no credential" and "credential, no
> account", and make `list` say which of the two tests it is reporting. Say
> in `docs/LIMITS.md` that validity of a credential is out of reach without
> running the agent's CLI, which the audit does not do. Tests, schema, the
> doctor reads declaration and the generators as usual.

**Done when:**

- Two roots with the same account produce a finding in a fixture.
- A root whose account differs from its `account=` record produces a finding.
- `list` distinguishes the three identity states.

### 5. Let `doctor` reach exit 0 on a normal machine: advisory rules, finding classes and acknowledged findings

**Why this matters:** `doctor` can never come back clean on a machine with a
Claude Code IDE extension, because D09 and D16 report a launch path that
exists on every run, so exit 2 stops being information and an audit that is
permanently red is one people stop reading. A correct machine before login
exits 2 for three D05 findings, the same code as a real leak, so `--quiet` in
cron is useless. On an adopted machine D01, D02 and D09 are permanent
findings no command resolves and nothing records that someone has read them.
Markus chose that a normal developer machine must be able to exit 0. Issue
#58 covers only the duplicate half of D16.

**Labels:** ux, security

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Give rules a fifth status, `advisory`, beside `pass`, `fail`, `limited` and
> `not_run`: reported once in prose and in the document, never counted as a
> finding and never setting exit 2. Move D09 and D16 to it, and fold issue #58
> in so D16 reports once per IDE. Give findings a class, `leak`, `hygiene` or
> `pending`: D01, D02, D03, D13 and the rules from suggestions 1 to 4 are
> `leak`; D05 with no account on record yet, a sessions server never
> registered and a profile with no launcher are `pending`; the rest are
> `hygiene`. Print the classes in separate blocks with separate counts, carry
> the class per finding in the JSON, and make the exit code 2 only for `leak`
> or `hygiene`, with a new code, 5, for a machine that is clean but
> unfinished, documented in the exit code table and in `docs/AUDIT-SCHEMA.md`.
> Add `agpin accept <rule> [--profile <name>] --reason "..."`, stored in the
> registry directory beside the profiles and never in any root, so an accepted
> finding still appears in prose and in the document, marked `accepted` with
> the reason and the date, in its own section of the Markdown report, and
> stops counting toward the exit code; `agpin accept --list` and `--remove`
> complete it. On a clean run, print one line naming the rules that were
> advisory, limited or not run, in the shape of the existing D12 line. Update
> `docs/AUDIT.md`, `docs/SETUP.md` Part 2 and `docs/OFFBOARDING.md`, and every
> test that asserts exit 2 on a launch-path-only fixture.

**Done when:**

- A fixture with an IDE extension and a URL handler and nothing else exits 0
  and prints both as advisory.
- A correct machine before login exits 5, not 2.
- An accepted D02 appears in the report's accepted section and does not set
  the exit code.

### 6. `agpin status`: one table that says how far the first run got, and whether the sessions server can start

**Why this matters:** The first run is eight steps with five hand-offs and no
command that says how far you got. `list` says profiles exist; it does not say
that nobody has logged in, that two profiles have no launcher, or that the
sessions server's environment was never built, in one place. `mcp status`
reports `on` for a server that cannot start, because it checks that the
registered command exists and never the interpreter it would exec, and a
profile created before `claude` was on `PATH` stays `off` forever with no
note. Markus's setup guide already invites a coworker's own Claude Code
session to do the setup, so the table needs a `--json` an agent can resume
from as much as a person can read it.

**Labels:** ux

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Add `agpin status [--json]`: one row per profile with columns for root,
> account (the three states from suggestion 4), credential, sessions server,
> launcher, and a final block for the guard, the shell and the tool's install
> route, everything derived from disk on every call and stored nowhere. Widen
> `mcp_registration`'s `on` test to "the command exists and the interpreter it
> will exec exists and is executable", so `mcp status`, `list`, `status` and
> D19 report `on, not built` with "run the installer again" as the fix; add a
> low-noise note for `off`, in the shape of the D12 opt-out line, saying
> `agpin mcp on <name>` turns it on or that off is fine deliberately. Add
> `agpin mcp on --all` and `off --all`. Have `new` end with a first-run
> checklist naming what the root does not have, which is issue #22's option 1.
> Have the guard function export `AGENT_PROFILE_GUARD=<version>` when it
> defines itself, add `agpin guard --check` that reads only the process
> environment, and make the printed function end with a line that prints a
> loud warning when `agpin` is no longer on `PATH`, so a lost install fails
> closed rather than open. Add a `doctor` rule that reads the user's rc files
> for the guard line and reports its absence as `hygiene`, `limited` when the
> shell cannot be told, reading only. Do not write any rc file; Markus
> declined that. Have `version --check` and `status` resolve the running
> script's own path and print the update command for the route in use,
> `brew upgrade agpin` for a keg, `git pull` for a `--dev` link, the one-liner
> otherwise, and add a footer to `help` and `version` naming the local docs
> directory and the repository.

**Done when:**

- `agpin status` and `--json` exist with tests, and an agent following
  `docs/SETUP.md` is told to use it.
- A never-built server reports `on, not built` in `mcp status`, `list` and
  D19.
- `guard --check` reports whether the guard is loaded, and a rule reports an
  rc file without it.
- `version --check` prints the right update command for a Homebrew install.

### 7. Make the evidence report evidence: scoped to one engagement, with integrity, scope, retention and a diff

**Why this matters:** The report is read by the customer's security officer
without Markus in the room, and today it names every other customer on the
machine with their account addresses and organisation ids, self-reports its
own version, records neither the overrides in force nor which system
binaries answered, identifies the machine by `uname -n` and a possibly empty
`$USER`, says nothing about what directories each rule scanned or how long
the transcripts it counts will remain, and cannot be compared with last
month's. `remove` produces no record at all, so the three things a customer
asks for at engagement end, the transcripts gone, the Keychain entry gone and
proof of both, are done, left to the person and not produced. Signing is
deliberately not proposed: a key on a consultant's laptop is a worse thing to
own than an unsigned report, the same reasoning the release process applies.

**Labels:** security, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Add `--for <profile>` to `doctor --report` and `--json`: the same claims,
> the same rule ledger and the same exit code, with the profile table reduced
> to the named profile plus "N other profiles on this machine, not named in
> this report", and every finding that names another profile's root reduced to
> the rule and the fact that a finding exists elsewhere. Extend the document
> header with: `tool_sha256` over the running script resolved through its
> symlink, with the release's `SHA256SUMS` extended to list `bin/agent-profile`
> on its own so the two can be compared; a `helpers` block with the resolved
> path and sha256 of `security`, `defaults`, `osadecompile`, `open` and
> `python3`, flagging any outside `/usr/bin`, `/bin` and `/usr/sbin`; an
> `overrides` block listing every `AGENT_PROFILE_*` variable set; a `machine`
> block with `id -un`, the uid and the hardware UUID read from `ioreg`; a
> `scope` block per rule naming the directories it scanned and, in prose, its
> known blind spots; a `retention` block per profile with `cleanupPeriodDays`
> from the root's `settings.json` and the oldest and newest transcript
> modification times; the install route from suggestion 6; and a
> `document_sha256` printed to the terminal and into the Markdown. Add
> `--baseline FILE` that classifies findings as new, resolved or unchanged by
> rule and subject. Add a short "What this document proves and what it does
> not" paragraph to the Markdown renderer. Route `remove` through `emit` and
> give it `--json` and `--report FILE`, recording the profile, its note, the
> paths, the session count at deletion, what was deleted, what was declined
> and why, the Keychain service name and the command that deletes it. Make
> `doctor --keychain-scan --json` list the service names it counts as
> orphaned, so a second run after the `security` command is the proof. Add two
> sentences to `remove`'s output and to `docs/OFFBOARDING.md`: close any shell
> still pinned to this root, and check for background sessions, which outlive
> the shell. Say in `docs/OFFBOARDING.md` that the unscoped report is for the
> consultancy and the scoped one for the customer, and correct the example
> filenames.

**Done when:**

- `--for brygga` produces a document that names no other profile's account,
  with tests asserting it.
- The header carries the tool hash, helpers, overrides, machine, scope and
  retention blocks, and the release lists the script's own sum.
- `--baseline` classifies findings, and `remove --report` writes a dated pair.

### 8. Make `doctor` say when the tool has drifted from Claude Code, and give unattended use a recipe that stays honest

**Why this matters:** After a Claude Code release, `doctor` prints D05 for
every profile with no hint that the tool rather than the machine changed,
while `verify` says "fix the tool", and nobody who has not read the facts
file knows to run `verify` first. `verify` exits 4 as the steady state on a
Mac without an IDE, so cron cannot tell a new unchecked fact from the usual
one. The docs promise cron use and give no recipe; on macOS a cron job
outside the GUI session meets a locked Keychain and a TCC-protected Desktop,
and `applet_scan` swallows `find` errors, so D14 would pass silently. The
sessions server and D03 both parse a format the documentation now disowns,
and nothing would report the day a key disappears.

**Labels:** enhancement, security

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Have `doctor` print a `drift` note, in prose and in the document, when the
> agent version differs from `AGENT_PROFILE_VERIFIED_AGAINST`, reading the
> version from directory names only: the extension directory (F21), each app
> data directory's `claude-code/<version>/` (F17) and the native install's
> version directory. Add a `rests_on` list per rule to the JSON (D03 on F11,
> D05 and D11 on F03, D13 on F13, D16 on F21, D17 on F22, and the rest as
> declared), and run `verify`'s binary-free checks, F07 and F11, inside
> `doctor`, downgrading the affected rules to `limited` with a reason when
> they fail. Extend the F11 check to the keys the sessions server depends on,
> `cwd`, `sessionId`, `timestamp`, `version`, `gitBranch`, `type` and
> `message`, read from one record of each of three transcripts, so a broken
> reader is reported by the tool rather than discovered as an empty answer,
> and say in `server/README.md` which versions the reader was checked
> against. Give `verify` `--expect-unchecked F21,F05` so exit 4 means "newly
> unchecked", and make F05 honour `AGENT_PROFILE_APP_BUNDLE`. Make
> `applet_scan` and `ide_scan` record a directory they could not read and
> have D14 and D16 report `limited` naming it. Add `--report-dir DIR` that
> names the pair by host and UTC timestamp. Write `docs/UNATTENDED.md` with a
> launchd user agent plist running `agpin doctor --quiet --report-dir` weekly,
> a plain statement of what cron cannot do on a Mac, and the convention for a
> shared report directory that suggestion 7's `--baseline` reads.

**Done when:**

- `doctor` on a fixture with a newer agent version prints the drift note and
  the document carries `rests_on`.
- A missing transcript key downgrades D03 to `limited` and fails the new
  `verify` check.
- D14 reports `limited` naming a directory it could not read.
- `docs/UNATTENDED.md` exists with a working plist.

### 9. Give a fleet something to deploy, a way to pin a version, and one document per machine to collect

**Why this matters:** The team runs managed Macs, and a release produces
nothing a Jamf or Intune payload can push and no file it can write: every
location is an environment variable. `brew install agpin` fails today because
the formula pins a tag without `server/` while its install block builds it,
and `version --check` tells Homebrew users to curl a second copy into
`~/.local/bin`. Ten machines on four versions means the audit rules differ per
machine and a report cannot be read against a known rule set. Nothing
collects state, and ten documents cannot be keyed on anything but hostname.
The registry directory is created world-readable and holds customer names.

**Labels:** distribution, security, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Add a machine-level defaults file, `/Library/Application Support/agent-profile/config`,
> read once at startup before the `: "${AGENT_PROFILE_*:=}"` block, in the
> registry's `key=value` shape, carrying only what a fleet decides: the applet
> search path, a `fleet=` identifier, a `baseline=` identifier for issue #22,
> and a report directory; environment variables keep winning, the tool never
> writes it, and `explain` and `doctor` say which settings came from it. Have
> `tools/install.sh` record its own provenance beside the unpacked tree,
> naming the route (`release`, `pkg`, `brew`, `dev`), the version and whether
> the signature was verified, and document the pinned one-liner
> `curl ... | bash -s -- --version vX.Y.Z` as the scripted rollout form. Add a
> `.pkg` to `release.yml` that installs under `/usr/local/lib/agent-profile/<version>`
> and links both names in `/usr/local/bin`, published beside the tarball with
> its own `SHA256SUMS` row and Sigstore bundle; state in the pull request
> whether it is signed with a Developer ID, which needs a certificate in
> repository secrets that the release design has so far refused, or shipped
> unsigned with its Sigstore bundle as the trust anchor, and let Markus decide.
> Add `agpin report --json [--out PATH]` that combines `doctor`, `verify`, the
> install provenance and the `explain` layout into one document for a Jamf
> extension attribute or an Intune script, with `%h`, `%u` and `%t` in the
> output name and the `fleet=` identifier in the header, emitting and never
> posting. Add `--support` to it, redacting account addresses to a stable hash
> and organisation ids to a prefix by default, and assert the redaction in
> `tests/cases/50-isolation.sh`. Make `new` create the registry directory at
> mode 700 and extend D07 to audit it. Add a CI check that the formula's
> install block names only directories the pinned tag contains, one
> `git ls-tree` against the version in the formula, and let
> `homebrew-formula.yml` open its pull request against the tap as well.

**Done when:**

- The defaults file is read, never written, and shown by `explain`.
- `version --check` prints the update command for the install route in use.
- The release publishes a `.pkg`, with the signing question answered by
  Markus.
- `agpin report --json` and `--support` exist, and the redaction is tested.
- The formula check fails on today's pin.

### 10. Give the team a shared layout: customer identifiers, a plan file, and a second-machine story

**Why this matters:** The registry holds no customer, label or owner, so two
machines cannot be compared and "the Brygga profile" means whatever each
person typed. There is no second-machine or replacement-machine story
anywhere in the docs, no export and no import. The team half of issue #22 is
the same gap one level up.

**Labels:** ux, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Add optional `customer=` and `label=` keys beside the `account=` and
> `note=` keys from suggestion 4, set by `new --customer <id>` and
> `agpin label <profile>`, and read `created=` back, so `profiles[]` in every
> document carries `customer`, `label` and `created`. Add `agpin plan > team.json`,
> which emits the names, agents, root shapes (the `~/.claude-<name>` convention
> rather than the resolved path), customers, labels, bound and shared paths
> and expected accounts, and `agpin apply team.json`, which creates every
> profile that is missing, leaves every one that exists alone, re-derives
> roots from the running machine's `$HOME` and never copies them from the
> file, and prints the logins still to do. The plan carries names and
> conventions only, never settings, hooks, skills or anything from inside a
> root, or it becomes the copying mechanism the design rules out. Add an
> "Agreeing a layout" section to `docs/SETUP.md` covering the one irreversible
> thing, that a name is permanent because the credential is keyed to the root
> path, and a "Second machine" section built on `plan` and `apply`.

**Done when:**

- `plan` and `apply` round-trip a three-profile fixture without copying a
  path or a setting, with a test that the plan carries nothing from inside a
  root.
- The document carries `customer`, `label` and `created`.
- `docs/SETUP.md` has both sections.

### 11. Revise issue #22: managed settings by MDM for hooks and permissions, visibility now, plugins for content later

**Why this matters:** Issue #22 recommended a marketplace plugin because it
uses Claude Code's own mechanism rather than copying files between roots.
With managed Macs there is a second mechanism that costs the invariant
nothing and costs less: a machine-level managed settings file delivered by
the MDM applies to every root without a network fetch at `new` time, a second
unsigned channel or a per-root step to forget. Three more mechanisms now give
a baseline without a copy: `--settings <file>` merged above user settings,
`CLAUDE_CODE_PLUGIN_SEED_DIR`, and `syncClaudeAiSkills`. Option 2 is the only
one that breaks the invariant. D19 is taken.

**Labels:** enhancement, ux

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `medium`, for the
issue update; the implementation follows whatever is decided there

**Implementation prompt:**

> Comment on issue #22 with the revised recommendation: managed settings by
> MDM for hooks and permission rules, delivered as the consultancy's own
> policy; option 1's visibility now, meaning `new` ends with a first-run
> checklist and a rule reports a root with no `settings.json` as a `hygiene`
> note; option 3 for plugin content when a marketplace exists, folding the
> sessions server into it as the proposal anticipates; option 2 rejected as
> the one that copies. Add the `--settings` route as a fourth option for a team
> without an MDM: an optional `baseline=` key in the registry or in the
> machine-level config, one file outside every root, passed by `run` and
> `shell` as `--settings`, reported by `explain`, and reported by `doctor`
> when it is missing from disk, so "nothing is shared" survives literally
> because no file moves and no root gains content. Note that D19 is taken and
> that whatever rule lands needs the managed-settings read from suggestion 3
> so a root is not reported as bare when the fleet policy gave it hooks.

**Done when:**

- Issue #22 carries the revised options and recommendation.
- The decision is taken on the issue.

### 12. The IDE-first coworker: a separate editor instance per profile by default, and the forks and remote hosts D16 cannot see

**Why this matters:** `code` and `idea` refuse into a running editor, and
`ide_running` asks whether any VS Code is up rather than whether one sharing
this profile's user data directory is, so after one `--new-instance` every
plain launch is refused until the editor is quit. A consultant with three
customers and one editor open all day gets "quit your editor" or "run a
second one". The refusal is right, and it should not be the common path.
D16 knows three IDEs: Windsurf and Zed are unknown, Cursor's extension
directory is unverified, and a WSL or remote extension host under
`~/.vscode-server/extensions` is invisible. Markus declined seeding editor
settings; a bare second instance that opens once is not seeding.

**Labels:** security, ux

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> First establish on a Mac that a second, differently pinned VS Code started
> with its own `--user-data-dir` does not forward to a running one, for a
> plain second instance as well as the first: `agpin code brygga ~/src/a --new-instance`,
> then the same for a second profile, then two directories under
> `~/Library/Application Support/Claude-*/ide/` each stamped at its own
> launch, and two different emails in the two Account & Usage panels. Record
> it as a fact. If it holds, make the separate instance the default for
> `code`: every profile owns one editor instance under its app data directory,
> two profiles can be open side by side, and `ide_running` checks for an
> instance sharing this user data directory rather than any instance; keep
> `--shared-instance` for the old behaviour, and say on the first launch of
> a profile that the editor opens bare once because extensions are shared and
> settings are not. Keep the refusal for `idea`, which has no equivalent. Add
> `windsurf` to `ide_def` as a `vscode` kind with `~/.windsurf/extensions`,
> add `~/.vscode-server/extensions` and `~/.cursor-server/extensions` to the
> VS Code family's directories so a remote or WSL install is seen, open a
> fact for Zed rather than guessing, and mark the Cursor and Windsurf
> directories `UNVERIFIED` with the `--list-extensions` re-check recipe. Add
> `code` and `idea` to the picker's second question. Off macOS, make
> `agpin code` export the variable and exec the editor from the pinned
> environment, with the same running-editor check, if the pinned-shell route
> is verified on WSL, and otherwise print the honest line.

**Done when:**

- The fact is recorded, and `code` defaults to a separate instance per
  profile on macOS with `--shared-instance` as the opt-out.
- D16 sees a planted `~/.vscode-server/extensions/anthropic.claude-code-*`.
- The picker offers the IDEs.

### 13. Tell two profiles apart: the server named after the profile, a running-instance check, and `doctor --recent`

**Why this matters:** Nothing inside the desktop app or the IDE window names
the account, and the app's own login is not evidence. `desktop` and `app`
never ask whether the app is already running, so a repaired launcher's next
click focuses the instance still carrying the old pin, and the command meant
to fix a pin says "Repaired". Nothing proves a pin still works after an app
update except a `find` somebody has to remember, and D01 catches the outcome
undated and goes quiet once a profile owns the default root. The sessions
server is already an in-app surface, per root, and verified in the desktop
app.

**Labels:** ux, security

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Register the sessions server under `sessions-<profile>` rather than the
> constant `sessions`, so the app's MCP panel and the IDE extension's both
> read the profile's name, with `mcp on` migrating an old registration and
> D19 accepting both names; verify on a Mac first that the panel shows the
> name, using F24's recipe. Add a `whoami` tool to the server returning the
> profile name, the root and the account from `<root>/.claude.json`, so
> "which account am I in" is answerable inside the app in one sentence. Make
> `desktop <name>` call `ide_running` against the app's executable and refuse,
> or warn, when an instance is up whose `--user-data-dir` is not this
> profile's, failing closed when it cannot tell; make `app <name>` print one
> extra line after a repair, that the app must be quit before the launcher is
> clicked or the click focuses the instance with the old pin. Add
> `agpin running`, which lists the live desktop and editor instances with the
> profile each is pinned to, from `ps` output, outside `doctor`. Add
> `agpin doctor --recent [MINUTES]`, arguing openly with the decision in
> `docs/DESIGN.md`: it walks every known root plus the default root, reads
> transcript names, modification times and the `cwd` of the newest record,
> and prints one line per root that received a session in the window, with
> the working directory for the default root, never transcript text. Print
> D17's `limited` reason as prose at normal level, naming System Settings,
> General, Login Items and Extensions as the place to look by eye.

**Done when:**

- The registration name carries the profile, verified in the desktop app's
  panel, and `whoami` exists with a test.
- `desktop` refuses or warns on a running instance with another pin, in a
  fixture with the stand-in `pgrep`.
- `doctor --recent` names the root and the directory of a fresh unpinned
  session in a fixture.

### 14. Launchers: generated icons, the launcher table, and the three holes in D13 and D14

**Why this matters:** Two customers' Dock tiles are identical because `app`
generates no icon and `--icon` is the reader's own homework, which is the
wrong-click mechanism. Raycast, Alfred, Shortcuts, login items and the browser
extension appear nowhere, and the docs never say that a Spotlight or Raycast
hit on the applet is pinned. A shell-script launcher pinning the wrong root is
invisible to D14, an applet one folder deeper than `~/Applications` is past
the scan depth, `app` writes a launch line for a bundle that is not on disk,
and D09 tests one directory rather than asking LaunchServices who owns the
scheme. The icon is written into the applet the tool already owns, which is
inside what Markus allowed.

**Labels:** ux, security

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Add `app <name> --icon auto`, on by default for a new applet with
> `--no-icon` to opt out: the profile's initial on a colour derived
> deterministically from the name, rendered as a one-page PDF written by hand
> and converted with `sips`, then installed through the existing
> `applet_set_icon` path; verify on a Mac first that `sips` reads a PDF, and
> fall back to `qlmanage` or say it cannot be done in bash. Add
> `--icon-colour` for a brand colour. Raise `applet_scan`'s depth to 8 with
> the reason in the comment, teach it a second shape, a regular file under the
> same directories whose text holds `--env <var>=`, reported by D14 with its
> own wording, and make `app` check the bundle the way `desktop` does,
> refusing rather than writing a line to a bundle that is not on disk and
> naming `AGENT_PROFILE_APP_BUNDLE`. Make D09 read the LaunchServices binding
> for the scheme rather than one directory's existence, after recording the
> fact with `lsregister -dump`. Add `app <name> --print-command`, which prints
> the exact `open --env` line for a Raycast script command, an Alfred workflow
> or a Shortcuts shell action. Add a launcher table to `docs/DESKTOP.md`, one
> row per launcher, whether it carries a pin, and what to do instead: Spotlight
> or Raycast on the applet, pinned; on `Claude`, not; Shortcuts "Open App",
> not; "Run Shell Script" calling `agpin`, pinned; a login item pointing at the
> applet, pinned and unreadable by `doctor`; the URL handler, never.

**Done when:**

- A new applet gets a generated icon on macOS, verified by hand and recorded
  as a fact.
- D14 reports a script launcher and a deep applet in fixtures, and `app`
  refuses a missing bundle.
- The launcher table exists and `--print-command` prints a line D13 calls
  correct.

### 15. Sessions server: paging and totals, export with redaction, statistics, local dates, and a bounded cache

**Why this matters:** "What did we decide about X" is the headline use and
`search` returns the newest twenty hits with no next page and no count. The
second thing asked for is a record to hand to the customer, and the only
route today is the model reading capped text and retyping it, which is the
one step where a secret would be copied without anyone deciding to. Bare
dates are UTC, so an evening session lands on the wrong day for a consultant
in CEST. The store holds the whole root in memory for the session's life.
Markus chose export before delete; delete waits and needs the open argument
the registration had.

**Labels:** enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Give `search` the `cursor` and `next_cursor` that `list_sessions` has and a
> `matched` count, and give `list_sessions` a total. Add
> `agpin sessions export <profile> <session-id> --to FILE [--redact PATTERN...]`
> in the bash tool, not the server, reading that profile's `projects/` with the
> store's confinement rules, writing Markdown outside every root and refusing
> a path inside one, applying the redaction list before writing, with
> `--since` and `--cwd` forms that export a project's sessions as one
> document. Add a `session_stats(group_by, since, until, cwd, branch)` tool
> returning counts, summed prompts, replies and tool calls and the span per
> group, no transcript text, and accept a timezone offset on bare dates so a
> day means the caller's day. Surface the session name where one exists. Bound
> the store's cache by a byte budget with least-recently-used eviction, keep
> only identity columns for sessions nobody has opened, and do not hold
> `thinking` unless it was asked for once. Write the desktop app's verified
> behaviour into `docs/DESKTOP.md`, and establish the IDE extension case as a
> fact with an `envprobe` server in a pinned VS Code. Leave delete for a later
> decision and say so in `docs/USE.md`.

**Done when:**

- `search` pages and counts, with tests.
- `sessions export` writes a redacted Markdown file outside the root and
  refuses a path inside one, with tests.
- `session_stats` exists, dates honour an offset, and memory on the 300-session
  fixture is bounded and measured.

### 16. Sessions server packaging: the no-uv path in CI, the requirements export check, and the Python tests in the suite

**Why this matters:** The no-`uv` install path, which is the path a fresh Mac
takes, is never exercised in CI, and `requirements.txt` is regenerated by hand
with nothing checking it still matches the lockfile, so a dependency bump with
a forgotten export ships a release whose two install paths install different
things, or fail on a hash, on the machines least able to diagnose it. The
Python tests need `uv` and the network, and the bash suite's count is the bash
half only.

**Labels:** distribution, enhancement

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `medium`

**Implementation prompt:**

> Add two CI steps: re-run `uv export --frozen --no-dev --no-emit-project --format requirements-txt`
> and fail on any diff against the committed file, and a leg that builds the
> environment with `python3 -m venv` plus `pip install --require-hashes` and
> runs the same refusing-to-start smoke test the uv leg runs. Add
> `tests/run.sh --with-server` that runs pytest when an environment exists and
> skips with one clear line when it does not, and say in `docs/CONTRIBUTING.md`
> which parts of the suite cover which half. Export a second requirements
> file with the dev group so a contributor without `uv` has the same recipe
> the installer uses. Have `tools/install.sh --uninstall` print the roots that
> still hold a registration with the one `claude mcp remove` line each needs,
> and mention the sessions server in `docs/OFFBOARDING.md`. Say in
> `docs/LIMITS.md` that the server is portable and only its launcher and
> registration are macOS-shaped, with the `claude mcp add` line a Windows user
> could run by hand against their own environment.

**Done when:**

- CI fails on a stale `requirements.txt` and passes the pip leg.
- `tests/run.sh --with-server` runs the Python tests where an environment
  exists.
- Uninstall prints the registrations it leaves.

### 17. Say that Linux and WSL are supported for the terminal half, and make the audit honest there

**Why this matters:** The WSL half of the Windows audience is the part
reachable today, and it is turned away at the front door. `new` creates a
macOS app data directory on Linux, the picker offers a desktop app that then
fails, a clean `doctor` says nothing about the six rules it skipped, D16 does
not see a WSL extension host, and on WSL the `not_run` reasons say "this is
Linux" when the true statement names a Windows-side root that was not looked
at. The two Linux bugs are fixed in the separate pull request; this is the
statement and the honesty.

**Labels:** portability, docs

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Record two facts first: that Claude Code on Linux honours `CLAUDE_CONFIG_DIR`
> and where a real login puts `.credentials.json` (the variable half was
> verified here; the login half needs a Linux login), and, for WSL, where the
> extension lives and whether a pinned WSL shell reaches its extension host
> (`~/.vscode-server/extensions`, then `eval "$(agpin env work)"; code .` and
> the leak test, with and without killing the server first). Write a
> supported-platforms statement in the README and a Linux and WSL section in
> `docs/INSTALL.md`: which commands work, which six rules do not run and why,
> that the credential is a file in the root, that `code`, `idea`, `desktop` and
> `app` are macOS only, and that on WSL the Windows-side desktop app and VS
> Code are outside what this audit can see. Do not create the macOS app data
> directory off Darwin and drop "desktop app" from the picker there. Detect WSL
> from `/proc/version` or `WSL_DISTRO_NAME` and, where true, change D17's and
> D18's `not_run` reasons to name the Windows side, and add a rule that reports
> the presence of a Windows-side default root under `/mnt/c/Users/<user>/.claude`
> without opening anything in it. Add `tests/cases/15-platform.sh`, run only
> when the host is not Darwin, asserting the Linux answers: the `not_run` and
> `limited` reasons, the macOS-only refusals, and `--purge` leaving the
> credential file. Lift `depends_on :macos` from the formula only if the
> server's launcher is verified on Linux Homebrew; otherwise say why it stays.

**Done when:**

- The facts are recorded with statuses.
- The README and `docs/INSTALL.md` state the Linux and WSL support.
- `new` on Linux creates no macOS path, and the platform case file passes on
  the Ubuntu leg.

### 18. Windows: run the probe, ship the PowerShell recipe on documented facts, and sharpen issue #15

**Why this matters:** This is the strongest signal in the review, and the
answer today is a link to a probe nobody has been told to run and a link to
an unstarted rewrite. One hour on one machine settles five of the six facts.
A Windows coworker has no recipe although the facts contain a working
per-window PowerShell function, both traps and a leak test. A PowerShell
`agpin` is the one candidate to skip, because even a four-rule `doctor`
subset duplicates the audit and creates a second producer of the schema. The
Go rewrite's specification has three holes this review found. Markus stated
no preference on the Windows questions, so the probe is the gate and the
recipe ships ahead of it, labelled.

**Labels:** portability, docs

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `medium`, for the
recipe; the probe is Markus's hour

**Implementation prompt:**

> Write `docs/WINDOWS.md` of about one page: one `Set-ClaudeProfile` function
> for the PowerShell profile that sets `$env:CLAUDE_CONFIG_DIR` per window and
> nothing else, one paragraph saying never to use `setx` or the User scope and
> why, the leak test from W04, and a plain statement of what this does not give
> them, which is any audit, any desktop pinning and any detection of the day
> somebody forgets. Mark it as resting on `DOCUMENTED` facts with the probe
> named as what turns them `VERIFIED`. Add two questions to the Windows section
> of `docs/FACTS.md`: what a Windows `CLAUDE_CONFIG_DIR` value has to look like
> (trailing separator, forward slashes, UNC, and whether two spellings give one
> root or two), and what command shape Claude Code on Windows can start a stdio
> MCP server with. Add three things to issue #15's specification: a "does this
> platform keep the credential inside the root, and if so protect it" concept
> on the `Platform` interface, so `--purge` cannot delete a credential file in
> Go; the IDE launcher for Linux, which the prompt leaves unstated while D16's
> fix line depends on it; and the sessions server's per-platform launch shape,
> the bash launcher and `.venv/bin/python` on POSIX against `.venv\Scripts\python.exe`
> on Windows. Note in #15 that it should not start before the probe, and that
> the Linux platform case file from suggestion 17 becomes its Linux acceptance
> criteria for free.

**Done when:**

- `docs/WINDOWS.md` exists and `docs/INSTALL.md`'s Windows section points at
  it.
- The two questions are in `docs/FACTS.md`.
- Issue #15 carries the three specification additions and the ordering.

### 19. Design the agent seam before the second agent, and record what Copilot and ollama cannot get

**Why this matters:** The tool is named for agents and the seam is one
function that holds sixteen Claude-shaped fields. Codex fits the mechanism
better than Claude does and is the right first second agent; Gemini fits;
Copilot cannot be isolated this way because its token lives under one flat
Keychain name, and a `new --agent copilot` that produced a root would be a lie
on disk; ollama has no account to isolate. Five rules and the identity reader
know Claude's layout directly, the ledger cannot say a rule does not apply to
an agent, and the `which --label` fast path is single-agent by construction.
Markus chose Codex first, Copilot as a limits note, and after the Windows
question is settled, because Codex and Copilot are first-class on Windows and
every field written in macOS terms is one more thing a port has to unpick.

**Labels:** enhancement, portability

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Do not add a second agent yet. Reshape the seam so one can be added: make
> the credential a per-agent probe with three answers, "in the root", "keyed
> on the root" and "shared across roots", and have `new` refuse the third
> outright with a message naming what does not separate; give the hash a
> per-agent width, prefix and canonicalise flag; make the Keychain scan
> pattern per agent; add `root_is_home`, `root_must_exist`, an `extra_env`
> allowlist of variable names per agent that `run_pinned` exports as a set
> while `env` prints exactly the same set, and `default_root_is_same_login`;
> add two seam functions, one listing an agent's transcripts under a root and
> one reading an account identity out of a root, and make D01, D03, D05 and
> D08 call them rather than name paths; add a `not_applicable` status with an
> agent and a reason to the ledger and a per-agent rule table to the document;
> generate the `which --label` fast path from the same table with a test that
> fails when the two disagree, and let the label name the agent when more than
> one is pinned; allow `agent/name` addressing while bare names keep working
> when unambiguous. Write the questions the other agents need into
> `docs/FACTS.md` as `UNVERIFIED` entries with recipes: whether the ChatGPT
> app's embedded Codex honours `CODEX_HOME`, the Codex keyring naming, whether
> `CODEX_HOME=~/.codex` is the same login as unset, whether a Codex rollout
> and a Gemini chat record their working directory, whether `GEMINI_CLI_HOME`
> moves the credential and when the runtime directory moves, whether the
> Copilot Keychain entry is keyed on anything but its service name and where
> a second Copilot account lives, whether the Codex and Gemini extensions take
> the root from the IDE's environment, whether any of the three registers a
> URL scheme, and whether `~/.ollama/id_ed25519` is shared whatever
> `OLLAMA_MODELS` is. Add to `docs/LIMITS.md` that Copilot separates work but
> not identity, and that ollama has no account to isolate with
> `OLLAMA_NO_CLOUD=1` as the real control, and qualify the README's sentence
> about ollama. Add two rules for Copilot: a flat `copilot-cli` Keychain entry
> reported as unpinnable in D09's style, and `GH_TOKEN` or `GITHUB_TOKEN` set
> in a pinned environment.

**Done when:**

- The seam carries the new fields and functions with Claude as the only
  agent, the suite is green and the fast path is generated and tested.
- The facts are recorded as questions with recipes.
- `docs/LIMITS.md` and the README say what Copilot and ollama get.

### 20. Documents: the limits page, the facts drift, the escape hatches in daily use, and one inventory for `explain` and `purge`

**Why this matters:** `docs/LIMITS.md` is missing tmux, Docker and
devcontainers, SSH, worktrees and case variants, managed settings, Anthropic
profiles, `claude --cloud`, the background supervisor, `--bare` and token
authentication, and the Windows side of a WSL desk. F08's list has tripled,
F20's count is stale, F12 has three documented rules D08 should know, and
F11 carries a warning. `explain` lists ten things a root holds and the root
now holds `history.jsonl`, which is every prompt ever typed and is never swept,
plus a dozen more directories, so `remove --purge` describes a root that no
longer exists. Several daily-use gaps are a paragraph or a few lines each.

**Labels:** docs, ux

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `medium`

**Implementation prompt:**

> Add the missing paragraphs to `docs/LIMITS.md`, one honest paragraph each,
> and a launch-path line for `claude --cloud` in `docs/DESKTOP.md` marked
> pinned but invisible. Update F08 to the current inventory of a root with
> `todos/` marked legacy, F20's count, F12 with the three documented rules for
> `CLAUDE_CODE_PROJECT_DIR_NAME` and the note that a pinned name is still found
> by `--resume` and the picker, and F11 with the format warning. Generate both
> the `explain` inventory and the `remove --purge` plan from one table in the
> script, each row a path, a description and whether it is swept by
> `cleanupPeriodDays`, and have purge print at the end what
> `claude project purge --dry-run` would name for the same root. Add
> `agpin exec <profile> -- <command> [args...]`, which is `run_pinned` with a
> caller-supplied command, for scripts, Makefiles and cron. Add `--shell` to
> `env`, defaulting from `$SHELL` the way `guard` does, printing `set -gx` for
> fish, and refuse unknown arguments. Register bash and zsh completion for the
> agent's binary name too, first word only and only when nothing is pinned,
> and stop `run`'s completion offering profile names past the second word.
> Give the "claude is not on your PATH" error its next step. Add an SSH
> paragraph to `docs/USE.md` and a table of every `AGENT_PROFILE_*` variable,
> generated from the script, marking which are for users and which for the
> harness. Add the `--strict-mcp-config` note to the sessions server section
> and the `claude doctor` name collision to `docs/AUDIT.md`. Add `claude auth
> logout` and `claude project purge` to `docs/OFFBOARDING.md` as the agent's
> own complements to `remove`.

**Done when:**

- `docs/LIMITS.md` names every path above.
- F08, F11, F12 and F20 are current.
- `exec` and `env --shell fish` exist with tests, and `claude bry<TAB>`
  completes.

## Bugs found, fixed in a separate pull request

Markus chose to fix these now, apart from the report, on the branch
`claude/feature-gap-fixes`. Each has a test that failed before the fix.

| Bug | Decided behaviour |
| --- | --- |
| `new` on a Mac with no working `python3` dies with a raw shell error and creates a root at the empty path | `need python3` in `cmd_new`, a message naming the Command Line Tools, and the prerequisite in the setup and install guides |
| The printed rc block mixes a bash completion line with a zsh prompt line | The script prints the block for the shell `$SHELL` names; the installer's block is reported for a later change |
| `doctor --report DIR/name` into a missing directory fails with a raw redirect error, and the documented example is such a path | Create the parent directory and say so; a clear message when it cannot |
| `remove --purge` off macOS deletes `.credentials.json` while printing that the tool never touches credentials, and prints a Keychain command for a Keychain that does not exist | Leave the credential file, delete the rest, print the file and the command that removes it; no Keychain line where there is no Keychain |
| D16's fix line off macOS names `agpin code`, which refuses there | Off macOS the fix line says to start the editor from a shell pinned with `agpin shell` |
| A clean `doctor` off macOS says nothing in the terminal about the rules it skipped | One line naming the rules that did not run and why, kept out of `--quiet` |
| D13 reports a second `--env` after the pin as `wrongroot`, and reads only the first launch line, so an applet with a second, unpinned line passes | Parse every `--env` and every launch line; any line that pins nothing or the wrong root is a finding |
| `code <name> --app <other> --new-instance` hands a VS Code flag to any application | Refuse `--new-instance` for an application outside the VS Code family, saying why |
| `search(regex=True)` in the sessions server can be hung by a six-character pattern | The `regex` parameter is removed |
| `session_summary` returns `files_touched` and `subagents` uncapped | Both capped, with a truncation marker and the cap documented |
| The launcher compares `CLAUDE_CONFIG_DIR` with `--root` as strings while the server compares real paths, so a symlinked root is refused by one and accepted by the other | Both canonicalise the same way |
| The launcher passes the session's inherited `PYTHONPATH` to the interpreter | The interpreter starts isolated |

Two things found are not bugs in the code and need Markus rather than a
patch. The Homebrew formula on `hovud` pins v0.10.0 with an install block that
needs `server/`, so `brew install agpin` fails until v0.11.0 is cut and the
formula pull request merged and copied to the tap; cutting the release is the
fix. And the Windows probe needs a machine.

## What is working well

The things the September review praised have held and grown. The behaviour
the tool depends on is still written down with evidence, and the three facts
the sessions server rests on were established the same way, on Linux, with
their macOS re-checks named. Every documented example is now generated from a
real run and checked in CI, so the drift this review would otherwise have
found in the README was gone before it started. The sessions server's
confinement held against planted symlinks and traversal paths; the caps and
the `"source": "transcript"` labelling are the right shape for stored text. The
audit's ledger of `not_run` and `limited` rules with reasons is the best
property of the evidence document and the reason most of this review's gaps
could be stated as "which status, with which reason" rather than "silence".
The Linux half runs, the suite passes there, and the code is kept
Linux-safe on purpose. The daily command is thirteen characters. And the
tool's own messages still never let "already applied" and "never worked"
look the same, which is why a review of feature gaps found so few of the
other kind.
