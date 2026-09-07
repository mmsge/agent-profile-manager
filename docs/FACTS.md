# Verified facts

Everything `agent-profile` depends on behaviourally, what the evidence for it
is, and when it was last checked. Claude Code changes monthly and several of
these behaviours are undocumented, so this file is the thing that stops the
tool quietly rotting.

`agent-profile verify` re-checks the ones that can be checked automatically and
tells you which it could not. Run it after an agent update, then update this
file if anything moved.

**Last full review:** 2026-09-07, against Claude Code **2.1.263**.

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

**Status:** `UNVERIFIED`. Undocumented.

This is why `doctor`'s D05 does not treat a missing `.credentials.json` as
proof that a root has no credential: on macOS the credential is in the
Keychain. D05 only reports when the root also records no signed-in account.

The tool must never read credential content and must never call `security` with
`-g`. Establishing the naming means reading entry *metadata* only.

**How to check:** `bash tools/probe-claude-desktop.sh`

### F04 What does `~/Applications/Claude Code URL Handler.app` launch?

**Status:** `UNVERIFIED`. If `claude-cli://` links cannot be pinned to a
profile, they are a leak path and `doctor` should grow a rule for them.

**How to check:** `bash tools/probe-claude-desktop.sh`

### F05 Does an app update replace or relocate the Claude binary?

**Status:** `UNVERIFIED`. Decides whether generated `.app` bundles need a
version-independent way to resolve the binary, or can hard-code the path.

**How to check:** `bash tools/probe-claude-desktop.sh`, then again after an
update. It records the path, inode and `CFBundleShortVersionString`.

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

**Status:** `UNVERIFIED` in this repository; observed by the owner.

`CLAUDE_CONFIG_DIR=~/.claude` is claimed to produce a different layout from
leaving it unset, because `.claude.json` moves inside the root. The owner
observed two `.claude.json` files holding different accounts' state on the
machine this tool was written for.

The documentation is genuinely ambiguous here: `~/.claude.json` is not literally
a `~/.claude` path, so F08's sweeping statement does not settle it.

This is why `doctor` never treats "pinned to the default root" as equivalent to
"unpinned", and why D01 says so in its output.

**How to check:** `bash tools/probe-claude-desktop.sh` reports it.

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
