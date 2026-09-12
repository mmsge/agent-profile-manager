# The audit schema

`doctor`, `list` and `verify` take `--json` and print one JSON document to
standard output. `doctor --report FILE` writes the same document to `FILE.json`
and a Markdown rendering of it to `FILE.md`, so an engagement can end with a
dated audit of the machine rather than a screenshot of prose.

The exit code is unchanged by either flag. A machine-readable audit that
reported a problem in its body and success to the caller would be worse than
no audit at all.

## Why the two formats cannot disagree

Every user-facing line these three commands produce goes through a single
function in `bin/agent-profile`, `emit`. A record carries a level, a kind and
that kind's fields. The prose you read and the document a consumer parses are
two renderings of the same record stream, so a rule cannot start reporting
something in one and not the other: there is no second place where either is
written.

The level is `always`, `normal`, `detail`, `data` or `prose`. `data` is
recorded but never printed, which is how `doctor`'s prose stays silent about
healthy profiles while the document still names every one of them. `prose` is
printed but never recorded, which is how the line saying where a report was
written stays out of the report. The three ordered levels exist so that a
quieter or a more explanatory mode is a threshold change rather than a
rewrite: `doctor --quiet` and `verify --quiet` raise the threshold so only
`always` reaches the terminal, and `--explain` (or `AGENT_PROFILE_EXPLAIN=1`)
lowers it to `detail`. Either way the record stream itself, and therefore
every document below, is captured in full regardless of the threshold: a
level governs what `report_shows` lets reach the terminal as prose, never
what reaches `--json` or `--report FILE`. See
[Output levels](../README.md#output-levels) for what `--quiet` and
`--explain` do on the terminal.

## Common fields

Every document, whichever command produced it, opens with the same header.

| Field | Meaning |
| --- | --- |
| `schema` | `agent-profile/doctor`, `agent-profile/list` or `agent-profile/verify` |
| `schema_version` | Integer. `1` today. Incremented when a field changes meaning or leaves |
| `command` | The command that produced the document |
| `generated_at` | UTC, `YYYY-MM-DDTHH:MM:SSZ` |
| `tool` | The name the tool was invoked as, so an install under another name says so |
| `tool_version` | The version of this tool |
| `verified_against` | The agent version `docs/FACTS.md` was last checked against |
| `agents` | One entry per agent the tool knows: `agent` and the `version` installed, or `null` when it is not on `PATH` |
| `hostname` | `uname -n` |
| `user` | `$USER`, empty when unset |
| `platform` | `uname -s`, or whatever `AGENT_PROFILE_PLATFORM` was set to |
| `registry` | Where the registry lives, outside every config root |
| `notes` | Lines of prose that carry no structure of their own |
| `summary` | Counts, and the `exit_code` the command exited with |

Reading `agents[].version` runs the agent's own `--version`. That happens only
when a document is being produced, so an ordinary `doctor` run starts no extra
process.

## `doctor`

Adds `profiles`, `rules` and `findings`.

```json
{
  "schema": "agent-profile/doctor",
  "schema_version": 1,
  "command": "doctor",
  "generated_at": "2026-09-08T09:14:02Z",
  "tool": "agpin",
  "tool_version": "0.9.0",
  "verified_against": "2.1.263",
  "agents": [{ "agent": "claude", "version": "2.1.263" }],
  "hostname": "mbp.local",
  "user": "markus",
  "platform": "Darwin",
  "registry": "/Users/markus/.config/agent-profiles",
  "profiles": [
    {
      "name": "bouvet",
      "agent": "claude",
      "root": "/Users/markus/.claude-bouvet",
      "root_exists": true,
      "app_data": "/Users/markus/Library/Application Support/Claude-Bouvet",
      "account": "markus@bouvet.no",
      "organization": "3f0b...",
      "sessions": 214
    }
  ],
  "rules": [
    {
      "rule": "D12",
      "title": "Keychain credential entries belong to no known root",
      "status": "not_run",
      "findings": 0,
      "reason": "the Keychain was not scanned, because --keychain-scan was not given"
    }
  ],
  "findings": [
    {
      "rule": "D01",
      "summary": "the default claude root holds 3 session(s)",
      "subject": "/Users/markus/.claude",
      "detail": ["Something ran without a profile pinned and wrote here."]
    }
  ],
  "notes": [],
  "summary": { "findings": 1, "exit_code": 2 }
}
```

### `profiles`

One entry per registered profile, in registry order. `account` and
`organization` are the account identity `list` already prints, and are `null`
when the profile is not signed in. `app_data` is `null` when the registry entry
records none.

### `rules`

Every rule the audit can report, whether or not it found anything. `status` is
one of:

| Status | Meaning |
| --- | --- |
| `pass` | The rule ran and found nothing |
| `fail` | The rule ran and found something; `findings` says how many |
| `not_run` | The rule did not run. `reason` says why |
| `limited` | The rule ran in a weaker form than it would on a machine that had what it wanted. `reason` says how |

A rule that did not run is never reported as passing. That distinction is the
point of the array: `D12` is opt-in behind `--keychain-scan`, and a document
that quietly called it `pass` would be claiming a check that never happened.
The same applies to `D11` and `D12` where there is no Keychain to ask, to `D13`
and `D14` where `osadecompile` is missing so no applet can be read, to `D05`,
which without a Keychain falls back to asking only whether an account is on
record and is reported as `limited`, and to `D16`, which off macOS knows two of
the three places an IDE extension can live and is reported as `limited` too.

`reason` is `null` unless a status was recorded for the rule, which happens
when it could not run or ran in a weaker form. A rule can both run weakly and
find something: `D05` and `D16` each can, and such a rule is reported as `fail`
with its reason still attached, because "it found three of these and could not
look for the fourth kind" is two facts and the document owes the reader both.

### `findings`

One entry per finding, in the order `doctor` prints them. The fields are the
ones the prose shows: the `rule` that fired, its one-line `summary`, the
`subject` it names, which is the path or the service to look at, and the
`detail` lines beneath it. `subject` is `null` for a finding that names none.

`findings` is empty when nothing was found, and `summary.exit_code` is then
`0`. Otherwise it is `2`.

## `list`

Adds `profiles`, the same array `doctor` carries, and a `summary` of
`profiles` and `exit_code`.

## `verify`

Adds `checks`: one entry per assumption, in the order `verify` prints them.

| Field | Meaning |
| --- | --- |
| `status` | `ok`, `broken`, `unchecked` or `note` |
| `fact` | The fact id in `docs/FACTS.md`, or `----` for the agent version line |
| `summary` | The one-line result |
| `detail` | The lines printed under it, possibly empty |

`summary` carries `broken`, `unchecked` and `exit_code`: `3` when anything is
broken, `4` when nothing is broken but something could not be checked, `0`
otherwise.

## What is never in a document

No credential value, in any field, in any command. The tool never reads one:
it asks the Keychain whether a named entry exists and never passes `-g` or
`-w`, and it never opens `.credentials.json`. There is therefore no secret in
the record stream for a renderer to leak. `tests/cases/50-isolation.sh` asserts
both halves of that, against the source and against the JSON itself.

The account identity that does appear, an email address and an organisation id,
is the identity `list` has always printed on every run.

## Failure

A usage error, a missing dependency or an unwritable report path exits `1` with
a message on standard error and prints no document. Standard output carries a
document or nothing, never a half of one.

## Stability

`schema_version` is `1`. Adding a field is not a breaking change and does not
increment it; changing what an existing field means, or removing one, does.
Rule ids and fact ids are the stable vocabulary underneath, which is why they
are what a consumer should key on rather than the summary text.
