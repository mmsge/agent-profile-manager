# The audit

`doctor` is the command this tool exists for. It exits non-zero and names the
offender, so it works from a cron entry or a shell hook. This page has the
rules, what each one reads, the JSON document and the report, `verify`, the
leak test that settles any argument, and the exit codes. Every output shown is
generated from a real run of the tool.

## The rules

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
| D12 | Keychain credential entries belong to no known root (only with `--keychain-scan`) |
| D13 | A desktop launcher does not pin its profile |
| D14 | A desktop launcher exists that no profile claims |
| D15 | More than one profile is registered at the same root |
| D16 | A Claude Code IDE extension is installed and cannot be pinned |
| D17 | The desktop app itself is in the Dock, so it can be launched unpinned |
| D18 | The default app data directory has been written to by an unpinned launch |
| D19 | A sessions server registration names another root, or a command that is gone |

The reasoning behind the trickier rules, D05's exact Keychain check, D13 and
D14 on the desktop side, and D03's use of each transcript's own working
directory, is in
[The audit, rule by rule](DESIGN.md#the-audit-rule-by-rule).

A clean run looks like this:

<!-- BEGIN GENERATED: example doctor-clean (tools/gen-doc-examples.sh) -->
```sh
agpin doctor
```

```
Orphaned Keychain entries were not checked (D12). Run "agpin doctor --keychain-scan" to check them.

No isolation problems found across 2 profile(s).
```
<!-- END GENERATED: example doctor-clean -->

The first line is not a finding. D12 enumerates the whole login Keychain,
which is slow on a large one and reads every item's attributes, so it is off
unless `--keychain-scan` asks for it, and what it reports today is a count,
which [issue #61](https://github.com/mmsge/agent-profile-manager/issues/61) will turn into dates. Every other rule runs on
every call.
A finding names the rule, the offending path, what it means and the fix:

<!-- BEGIN GENERATED: example doctor-first-run (tools/gen-doc-examples.sh) -->
```sh
agpin doctor
```

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
     /Users/alex/.claude-torg
     Register it, or remove it if it is left over.
     Unregistered roots are invisible to every other check here.

D14  a desktop launcher for profile 'brygga' is not registered
     /Users/alex/Desktop/Claude Work.app
     It pins /Users/alex/.claude-brygga, which profile 'brygga' owns, but no profile
     names this applet, so the launcher audit has never read it.
     An unregistered launcher is invisible to every other check here.
     Fix with: agpin app brygga --applet '/Users/alex/Desktop/Claude Work.app'

D09  a claude-cli:// handler is installed and cannot be pinned
     /Users/alex/Applications/Claude Code URL Handler.app
     LaunchServices passes no environment, so a deep link opens against the
     default root whatever this tool has configured. Treat links as a leak
     path: open the project through a pinned shell instead of clicking them.

Orphaned Keychain entries were not checked (D12). Run "agpin doctor --keychain-scan" to check them.

5 finding(s).
```
<!-- END GENERATED: example doctor-first-run -->

What each of those means and how it is resolved is walked through in
[the setup guide](SETUP.md#what-the-first-doctor-run-tells-you).
`doctor --quiet` prints nothing on a clean run and only the findings
otherwise, for cron; see [Output levels](USE.md#output-levels).

## A document, not a screenshot

`doctor`, `list` and `verify` take `--json` and print one JSON document
instead of prose. The exit code is the same either way, so a cron entry or a
CI step can read the document and still branch on the status.

```sh
agpin doctor --json | python3 -m json.tool
```

The document opens with a header saying when it was produced, in UTC, by which
version of this tool, against which agent version, on which host and as which
user. Then the registered profiles with their roots, app data directories,
accounts and organisation ids, then every rule with a status, then the findings
themselves. The full schema is in [the audit schema](AUDIT-SCHEMA.md).

The rules array is the part worth knowing about. It lists every rule, not
only the ones that fired, and a rule that did not run says so rather than
appearing to pass:

<!-- BEGIN GENERATED: example doctor-json-d12 (tools/gen-doc-examples.sh) -->
```sh
agpin doctor --json | python3 -c 'import json, sys
rules = json.load(sys.stdin)["rules"]
print(json.dumps([r for r in rules if r["rule"] == "D12"][0], indent=2))'
```

```
{
  "rule": "D12",
  "title": "Keychain credential entries belong to no known root",
  "status": "not_run",
  "findings": 0,
  "reason": "the Keychain was not scanned, because --keychain-scan was not given"
}
```
<!-- END GENERATED: example doctor-json-d12 -->

`not_run` is also what `D11` and `D12` get where there is no Keychain to ask,
`D13` and `D14` where `osadecompile` is missing so no launcher can be read, and
`D17` and `D18` anywhere but macOS, where there is no Dock and no
`~/Library/Application Support` to look in. `D05` without a Keychain is
`limited`, because it falls back to a weaker question, and so is `D17` on macOS
itself: it reads the Dock, and the login items cannot be listed without root or
a consent dialogue. A clean `doctor` on a Linux box is a much smaller claim than
a clean `doctor` on a Mac, and the document is where that shows.

Prose and JSON cannot drift apart, because they are two renderings of one
record stream: every line these three commands produce goes through a single
function, and neither format is written anywhere else. The design is in
[One stream, two renderings](DESIGN.md#one-stream-two-renderings).

`doctor --report FILE` writes both `FILE.json` and `FILE.md` side by side, the
same document twice, one for a machine and one for a person. Either extension
on the argument is dropped, so `--report audit.json` writes `audit.json` and
`audit.md` rather than `audit.json.json`. A directory in the path that is not
there yet is created, and the run says which one; a path it cannot create
fails naming that directory, before anything claims to have been written:

<!-- BEGIN GENERATED: example doctor-report (tools/gen-doc-examples.sh) -->
```sh
agpin doctor --report ~/audits/brygga-2026-09-08
```

```
Orphaned Keychain entries were not checked (D12). Run "agpin doctor --keychain-scan" to check them.

No isolation problems found across 2 profile(s).
Created /Users/alex/audits
Wrote /Users/alex/audits/brygga-2026-09-08.json
Wrote /Users/alex/audits/brygga-2026-09-08.md
```
<!-- END GENERATED: example doctor-report -->

No credential value is in any of it. There is none to leak: the tool never
reads one.

## What doctor reads

Every rule reads only what it needs to answer one yes or no question, and
this table says what that is: which files and directories it looks at, which
Keychain query it makes, and which external command it runs, if any.

<!-- BEGIN GENERATED: what doctor reads (tools/gen-doctor-reads.sh) -->
| Rule | Reads |
| --- | --- |
| D01 | Whether the default root exists, and a count of `*.jsonl` filenames under `<default root>/projects` (names only, not their content), plus the registry, to see whether a profile claims that root. |
| D02 | Whether the agent state file beside the default root exists and sits outside every registered root. When it does, the `oauthAccount` block of that file: the account's email and organisation id, the same identity `list` already prints. |
| D03 | Every transcript (`*.jsonl`) under each registered root's `projects` directory, read line by line only until the first record carrying a `cwd` field. Only that field is kept; the rest of the transcript, including its conversation content, is never read. |
| D04 | The registry, and whether each registered root exists on disk. |
| D05 | On macOS, whether a Keychain entry named `<service>-<hash>` exists for the profile's root (attributes only, via `security find-generic-password`), and whether `.credentials.json` exists in the root (existence only, never opened). Without a Keychain, falls back to the same `oauthAccount` block D02 reads, but from the profile's own root rather than the stray file's location. |
| D06 | The directory listing of `$HOME` for entries matching the agent's root prefix (`.claude-*`), and the registry, to see which are unclaimed. |
| D07 | The file mode of each registered root and its app data directory, via `stat`. No file content. |
| D08 | The directory listing under `<root>/projects`. Directory names only, not the transcripts inside them. |
| D09 | Whether the deep-link handler bundle exists on disk. |
| D10 | The registry's stored root string, compared against its own canonical form. A string comparison, no filesystem or Keychain read. |
| D11 | On macOS, whether a Keychain entry exists for the default root's own service name (attributes only, via `security find-generic-password`). |
| D12, only with `--keychain-scan` | The entire login Keychain's item list, via `security dump-keychain`. Attributes only, specifically the `svce` field of each entry; no entry's secret data is read. |
| D13 | The AppleScript source of the applet named in the profile's registry entry, or its default conventional path if none is registered, decompiled with `osadecompile`. Only its single `do shell script` launch line is read. |
| D14 | Every `.app` bundle up to five levels deep under `$AGENT_PROFILE_APPLET_DIRS` (by default `~/Applications`, `~/Desktop` and `/Applications`) whose compiled script mentions the agent's config variable, decompiled the same way as D13. |
| D15 | The registry only. No filesystem or Keychain access. |
| D16 | Directory names one level under `~/.vscode/extensions` and `~/.cursor/extensions`, and one level under `~/Library/Application Support/JetBrains`, `~/Library/Application Support` and `~/Library/Application Support/Google` for a `plugins/claude-code-jetbrains-plugin` inside. Names only; no file in an extension is ever opened, and the IDE's own `--list-extensions` is deliberately not run. |
| D17 | On macOS, the `persistent-apps` key of the `com.apple.dock` preference domain, via `defaults read com.apple.dock persistent-apps`, and from each tile in it only the `_CFURLString` file URL, which is the path of the pinned application. Nothing is read for the login items: that half of the rule is reported as unchecked, because every way to list them needs root or a consent dialogue. |
| D18 | On macOS, whether the default app data directory exists and holds any entry at all (names only, nothing inside it is opened), the directory's own modification time, and, when a state file is there, the `oauthAccount` block of it: the account's email and organisation id, the same identity `list` prints for a root. |
| D19 | The `mcpServers` block of each registered root's state file, and of the stray state file beside the default root: the `sessions` entry's command and arguments only, never the `oauthAccount` block or any other key. |
<!-- END GENERATED: what doctor reads -->

No rule ever reads a credential value. The two Keychain queries above,
`find-generic-password` and `dump-keychain`, both stop at attributes; neither
is ever called with `-g` or `-w`, which is what would print a secret. The
account identity read by D02 and D05 is an email address and an organisation
id, not a token, and it is the same identity `list` already shows on every
run.

`--json` and `--report` add two reads of their own, outside any rule. The
document header runs the agent's own `--version`, which is the only time
`doctor` starts another program, and the profile inventory reads each root's
`oauthAccount` block, the same one D02 and D05 read and the same one `list`
prints. Neither happens on a plain `doctor` run.

### What the table is derived from

The table is generated. `tools/gen-doctor-reads.sh` rebuilds it from
`bin/agent-profile`, and CI fails when the checked-in table and a regenerated
one differ, so a table nobody updated cannot survive a change to the rules.
Run it after changing a rule, and commit the change it makes to this page.

Two different things go into a row, and it is worth knowing which is which.

The rules come from the code. The generator reads `doctor_rule_catalog()`, the
same list `doctor --json` reports, so the rows, their order and the fact that
every rule has one are the program's own answer rather than a second list
somebody has to remember. A rule added to the code without a row fails the
check by name, which is the part of the table that cannot go stale.

What each rule reads does not come from the code. It is a declaration written
beside the rule, a `# doctor reads (D07):` comment above the rule's own body,
and the generator copies it into the table without understanding it. A
declaration can be left behind by a change to the code under it, exactly as
this table used to be. It sits next to what it describes, which is the best
place for it, and the generator refuses to build a table with a declaration
missing, unparseable or naming a rule that does not exist. That narrows the
gap between the document and the code. It does not close it: nothing short of
reading the rule does.

## The leak test

Whatever else you check, this is the one that settles an argument. Run a real
session, then:

```sh
find "$HOME"/.claude* -name '*.jsonl' -mmin -3
```

The path it prints is the root that is really in use. It needs no throwaway
root, no probe and no documentation, and it works the same for the terminal,
the desktop and an IDE. `agpin app <name> --explain` prints the same command
after building a launcher, because that is the moment to run it.

## After a Claude Code update

Claude Code changes monthly, and some of what this tool depends on is
undocumented. That is why `verify` exists.

```sh
agpin verify
```

It re-checks the assumptions the tool rests on against the version actually
installed, and says plainly which it could not check. The record of every
assumption, its evidence and the version it was last checked against lives in
[`docs/FACTS.md`](FACTS.md). Its output depends on the Claude Code installed
on the machine it runs on, which is why no run of it is shown here.

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
directory, so they update independently of each other and of the CLI. The VS
Code extension is a third case: it bundles a copy of its own and updates with
the extension. There is no single agent version on a machine like this, and an
assumption can break for one profile while holding for the rest.

If an IDE extension is installed, the leak test settles it there too. Launch
with `agpin code <name> <path>`, start a session, and run the `find`
above; then launch the same IDE from the Dock and run it again. The two answers
should differ, and if they stop differing, F19 has changed and D16's advice is
wrong.

`agpin explain` states the scheme in plain language and shows where this
machine's data currently lives, for when you come back to this in six months;
it is in [Daily use](USE.md#explain).

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
