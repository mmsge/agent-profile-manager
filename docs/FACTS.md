# Verified facts

Everything `agent-profile` depends on behaviourally, what the evidence for it
is, and when it was last checked. Claude Code changes monthly and several of
these behaviours are undocumented, so this file is the thing that stops the
tool quietly rotting.

`agent-profile verify` re-checks the ones that can be checked automatically and
tells you which it could not. Run it after an agent update, then update this
file if anything moved.

**Last full review:** 2026-09-07, against Claude Code **2.1.263** and Claude
Desktop **1.46388.4**, on macOS 26.6.2.

Status values:

| Status | Meaning |
| --- | --- |
| `VERIFIED` | Observed directly, on a real config root or in current documentation |
| `DOCUMENTED` | Stated in current documentation, not independently observed |
| `UNVERIFIED` | Not yet checked. Run the probe |
| `REASONED` | Argued from a verified fact, not directly testable without cost |

---

## Claude Code

### F01 Does the desktop app's embedded Claude Code honour `CLAUDE_CONFIG_DIR`?

**Status:** `UNVERIFIED`. This is the question that decides the architecture of
the desktop half, so nothing has been built around either answer.

The docs say only that on macOS the app "reads your shell profile, such as
`~/.zshrc` or `~/.bashrc`, to extract `PATH` and a fixed set of Claude Code
variables, but other variables you export there are not picked up"
([desktop](https://code.claude.com/docs/en/desktop)). That set is not
published. There is a counter-signal: "Claude Desktop and cloud sessions do not
call `apiKeyHelper` or read these environment variables: they use OAuth"
([authentication](https://code.claude.com/docs/en/authentication)), so the app
demonstrably treats some variables specially.

Note the question is about the app's *process environment*, not the shell
profile. Launching the Mach-O binary directly passes the environment through;
`open -n -a … --args …` does not, because it dispatches through launchd and the
child inherits nothing from the invoking shell.

**Attempted 2026-09-07, inconclusive.** The probe launched the binary with the
variable set and `--user-data-dir` pointed at a throwaway directory. The app
data directory was populated (`Preferences`, `GPUCache`, `blob_storage`,
`claude_desktop_config.json` and more), which proves the app started and that
`--user-data-dir` works. The config root gained nothing, but the run was
interrupted before a Code session was started, and the embedded Claude Code
only writes once it actually runs. So this says nothing about F01 either way.

The probe now asks, at the end, whether a Code session was actually started,
and reports `INCONCLUSIVE` rather than `NO` when it was not. Re-run it and
answer that prompt to settle this.

**How to check:** `bash tools/probe-claude-desktop.sh`

### F02 Does the app's local environment editor set `CLAUDE_CONFIG_DIR` early enough?

**Status:** `UNVERIFIED`. Only matters if F01 is negative.

The editor is per app data directory: environment dropdown, hover **Local**,
gear icon. The docs say variables saved there "are stored encrypted on your
machine and apply to every local session and preview server you start"
([desktop](https://code.claude.com/docs/en/desktop)). If it works, it is a
first-party per-profile mechanism and the better primary route, and the tool's
job becomes configuring and auditing it rather than launching around it.

**How to check:** manual, described in the probe's output.

### F03 What is the Keychain service and account naming for a non-default root?

**Status:** `VERIFIED` 2026-09-07 against 2.1.263, from the implementation and
confirmed against real entries.

The service name is built as:

```
"Claude Code" + OAUTH_FILE_SUFFIX + "-credentials" + suffix
```

`OAUTH_FILE_SUFFIX` is empty by default (`-custom-oauth` and `-local-oauth`
exist for other sign-in modes). `suffix` is empty when `CLAUDE_CONFIG_DIR` is
unset, and otherwise a dash followed by the **first 8 hex characters of
sha256** over the **NFC-normalized raw value of the variable**. The account is
`$USER`.

Confirmed against three real entries on the target machine:

| Path | sha256[:8] | Present |
| --- | --- | --- |
| `/Users/markus.mg/.claude` | `1c128223` | yes |
| `/Users/markus.mg/.claude-bouvet` | `2241c977` | yes |
| `/Users/markus.mg/.claude-tide` | `4c36052e` | yes |

Two consequences the audit depends on.

**The suffix is present whenever the variable is set at all**, not when it
differs from the default. So `CLAUDE_CONFIG_DIR=~/.claude` is a *different
login* from leaving it unset, stored under a different entry. This is the
credential half of F10, and D11 reports it.

**The hash covers the literal string, not a resolved path.** A trailing slash,
a relative path or a non-NFC spelling is a different login. That is why `new`
normalizes a root before storing it, and why D10 reports a stored root that is
not in canonical form.

D05 uses this to check a credential exactly, with
`security find-generic-password -s <service> -a $USER`, discarding the output
and reading only the exit status. Never `-g`, so no secret is touched.

### F04 What does `~/Applications/Claude Code URL Handler.app` launch?

**Status:** `VERIFIED` 2026-09-07. It is a leak path.

Bundle identifier `com.anthropic.claude-code-url-handler`, claiming the
`claude-cli` URL scheme, executing a Mach-O binary at `Contents/MacOS/claude`.

It is launched by LaunchServices, which passes no environment from any shell,
so a `claude-cli://` link cannot carry a config root and opens against the
default root whatever this tool has configured. `open` has the same problem for
the same reason, which is why the desktop launcher execs the app binary
directly.

D09 reports the handler's presence for this reason. There is no fix available
from this tool: the remedy is to open a project through a pinned shell rather
than by clicking a link.

### F05 Does an app update replace or relocate the Claude binary?

**Status:** baseline recorded 2026-09-07. Needs a second reading after an
update to answer the question.

| | |
| --- | --- |
| Bundle | `/Applications/Claude.app` |
| `CFBundleShortVersionString` | 1.46388.4 |
| `CFBundleExecutable` | Claude |
| Binary | `/Applications/Claude.app/Contents/MacOS/Claude` |
| inode | 29735765 |
| size | 120064 |

The path is the conventional one and the executable name is stable in the
bundle metadata, so resolving it through `CFBundleExecutable` rather than
hard-coding `Claude` is the cheap safeguard. Re-run the probe after the next
desktop update and compare.

### F06 Can a config root be relocated without losing its login?

**Status:** `REASONED`, answer: **no**.

It follows from F09: the credential is keyed to the root path, so a root at a
new path reads a different Keychain entry and a different `.credentials.json`.

Not tested directly, because confirming it costs a real login. That is why the
tool has no `rename` and no `move`, and why `new` refuses to repoint an
existing profile rather than silently relocating it.

### F07 What identifies the signed-in account for a root?

**Status:** `VERIFIED` 2026-09-07 against 2.1.263.

`<root>/.claude.json` holds an `oauthAccount` object with `emailAddress`,
`accountUuid` and `organizationUuid`. Observed directly on a live root.

`organizationUuid` is the better discriminator when one person holds accounts
at several organisations, so `list` reports both.

**Re-checked by:** `agent-profile verify`, automatically.

### F08 A config root owns almost everything

**Status:** `DOCUMENTED`.

Setting `CLAUDE_CONFIG_DIR` moves `settings.json`, `projects/` (transcripts and
auto memory), `commands/`, `skills/`, `agents/`, `plugins/`, `plans/`,
`backups/`, `.credentials.json` and `.claude.json` under it. "If you set
`CLAUDE_CONFIG_DIR`, every `~/.claude` path on this page lives under that
directory instead"
([.claude directory](https://code.claude.com/docs/en/claude-directory)).

The [env-vars](https://code.claude.com/docs/en/env-vars) entry explicitly
blesses this use: "Useful for running multiple accounts side by side."

### F09 Credentials are keyed to the config root path

**Status:** `DOCUMENTED`, quoted verbatim.

"If you've set the `CLAUDE_CONFIG_DIR` environment variable, Claude Code keeps
the `.credentials.json` file under that directory instead, including the file
the macOS fallback writes, and keys the macOS Keychain entry to that directory
too, so a session with a different `CLAUDE_CONFIG_DIR` reads a different entry."
([authentication](https://code.claude.com/docs/en/authentication))

Two consequences the whole design rests on: separate roots give genuinely
separate logins, and moving a root invalidates its login (F06).

### F10 Setting the variable to the default path is not a no-op

**Status:** `VERIFIED` 2026-09-07 against 2.1.263.

Running the CLI with `CLAUDE_CONFIG_DIR` pointed at a throwaway root wrote
`.claude.json` and `backups/` **inside that root**. So the state file does move
under the variable, and `CLAUDE_CONFIG_DIR=~/.claude` produces a different
layout from leaving the variable unset.

F03 shows the same split applies to credentials: the hashed Keychain entry
exists whenever the variable is set, including when it is set to the default
path, and that is a separate login from the unsuffixed entry.

This is why `doctor` never treats "pinned to the default root" as equivalent to
"unpinned", and why D01 and D11 are separate rules with separate causes.

### F11 Transcripts record their own working directory

**Status:** `VERIFIED` 2026-09-07 against 2.1.263.

Every `user`, `assistant` and `attachment` record in
`<root>/projects/<dir>/<session-id>.jsonl` carries `cwd` as an absolute path,
alongside `version`, `gitBranch` and `sessionId`. Observed directly: encoded
directory `-home-user-claude-profile-manager`, recorded `cwd`
`/home/user/claude-profile-manager`.

**This is what `doctor`'s D03 rests on.** If `cwd` ever disappears from
transcripts, D03 stops detecting cross-root leakage and would pass silently,
which is the worst possible failure for this tool. `verify` checks it
explicitly for that reason.

**Re-checked by:** `agent-profile verify`, automatically.

### F12 A project directory name is not decodable

**Status:** `DOCUMENTED` and `VERIFIED`.

"`<project>` is your working directory path with non-alphanumeric characters
replaced by `-`", truncated to 200 characters with a hash appended past that
([sessions](https://code.claude.com/docs/en/sessions)).

So `my_repo`, `my-repo` and `my.repo` all encode identically. The mapping is
many-to-one and cannot be inverted. Never try; read `cwd` (F11) instead.

`CLAUDE_CODE_PROJECT_DIR_NAME` (Claude Code 2.1.234 or later) additionally lets
a session name its project directory outright, with no relation to any path
([env-vars](https://code.claude.com/docs/en/env-vars)). `doctor`'s D08 reports
when it sees one, because the name then says nothing at all.

**Re-checked by:** `agent-profile verify`, automatically.

---

## After an agent update

1. `agent-profile verify`
2. If it reports anything broken, fix the tool before trusting `doctor` again.
3. If the desktop app updated, `bash tools/probe-claude-desktop.sh` and compare
   against F05.
4. Update the "Last full review" line and the affected entries above.
