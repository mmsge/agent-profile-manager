# Verified facts

Everything `agent-profile` depends on behaviourally, what the evidence for it
is, and when it was last checked. Claude Code changes monthly and several of
these behaviours are undocumented, so this file is the thing that stops the
tool quietly rotting.

`agent-profile verify` re-checks the ones that can be checked automatically and
tells you which it could not. Run it after an agent update, then update this
file if anything moved.

**Last full review:** 2026-09-07, against Claude Code **2.1.263** and Claude
Desktop **1.46388.4**, on macOS 26.6.2. F01 and F13-F18 were established
separately, during the Tide and Highsoft migrations, on Claude Desktop
**1.44121.4** and Claude Code **2.1.227**. Those are older versions, so read
those facts as a floor rather than a ceiling: they were true at 2.1.227 and
nothing since has contradicted them.

Status values:

| Status | Meaning |
| --- | --- |
| `VERIFIED` | Observed directly, on a real config root or in current documentation |
| `DOCUMENTED` | Stated in current documentation, not independently observed |
| `UNVERIFIED` | Not yet checked. Run the probe |
| `REASONED` | Argued from a verified fact, not directly testable without cost |
| `MOOT` | The question stopped mattering. Kept so the number is not reused |

---

## Claude Code

### F01 Does the desktop app's embedded Claude Code honour `CLAUDE_CONFIG_DIR`?

**Status:** `VERIFIED` 2026-09-07 against Claude Desktop 1.44121.4 and Claude
Code 2.1.227. Answer: **yes**, from the app's process environment.

Established on the target machine during the Tide and Highsoft migrations, and
confirmed twice, once per account. Before the change, a desktop Code session
opened for the Tide account wrote its transcript into `~/.claude/projects/`.
After the app was launched with the variable in its process environment, the
same test wrote under the pinned root and left nothing under `~/.claude`.

This is the fact the whole desktop half rests on, and it is what makes F13 the
mechanism rather than a curiosity: the app has no need of a wrapper script, an
environment editor or a hand-built bundle, because the variable arrives in its
environment and the embedded Claude Code reads it there.

The docs say only that on macOS the app "reads your shell profile, such as
`~/.zshrc` or `~/.bashrc`, to extract `PATH` and a fixed set of Claude Code
variables, but other variables you export there are not picked up"
([desktop](https://code.claude.com/docs/en/desktop)). That set is not
published, and this fact is about the process environment rather than the shell
profile, so the two do not conflict.

**How to re-check:** launch a profile with `agent-profile desktop <name>`,
start a Code session in the app, then run the leak test:

```sh
find "$HOME"/.claude* -name '*.jsonl' -mmin -3
```

The path it prints is the root actually in use.

### F02 Does the app's local environment editor set `CLAUDE_CONFIG_DIR` early enough?

**Status:** `MOOT`. It only ever mattered if F01 was negative, and F01 is
positive. The heading is kept because F-numbers are referenced by hand from
`agent-profile verify`, the README and the test suite, so the number must not
be reused.

For the record, the editor is per app data directory: environment dropdown,
hover **Local**, gear icon. Nothing in this tool touches it.

### F03 What is the Keychain service and account naming for a non-default root?

**Status:** `VERIFIED` 2026-09-07 against 2.1.263, from the implementation and
confirmed against real entries.

**Established in a session that ran in parallel with the migrations, and not
yet cross-checked against them.** The migration notes still list the Keychain
naming as unknown, simply because neither session saw the other. The evidence
below is the stronger of the two, so it stands; `tools/probe-claude-desktop.sh`
re-reads these three entries on the machine so the two records are reconciled
rather than merely assumed compatible.

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

Established in the same parallel session as F03, and carries the same caveat:
the migration notes still list it as untested. The probe re-reads the bundle
identifier and executable for that reason.

Bundle identifier `com.anthropic.claude-code-url-handler`, claiming the
`claude-cli` URL scheme, executing a Mach-O binary at `Contents/MacOS/claude`.

It is launched by LaunchServices, which passes no environment from any shell,
so a `claude-cli://` link cannot carry a config root and opens against the
default root whatever this tool has configured.

D09 reports the handler's presence for this reason. There is no fix available
from this tool: the remedy is to open a project through a pinned shell rather
than by clicking a link.

**This does not condemn `open`.** The handler leaks because a URL carries no
place to put a variable, not because launching through LaunchServices makes one
impossible. `open --env` injects one explicitly (F13), which is exactly why the
desktop launcher uses `open` and not the app binary. Exec'ing the binary from
an interactive shell is the route that fails outright (F15).

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

This matters less than it did. `desktop` and the applets generated by `app`
launch with `open -n -a /Applications/Claude.app`, which resolves the bundle
rather than a binary inside it, so no executable path is hard-coded anywhere on
the launch path. The reading is kept because the probe still needs to know
whether a bundle moved.

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

Independently confirmed during the migrations, which read
`oauthAccount.emailAddress` out of two live roots to label them. `email` and
then `accountUuid` are the fallbacks if the field is ever absent.

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

Independently confirmed on disk during the migrations, which found three state
files coexisting: `~/.claude.json` at 104 KB written by unpinned invocations
including the desktop app, `~/.claude/.claude.json` at 45 KB written by an alias
that set `CLAUDE_CONFIG_DIR=~/.claude` and **holding a different account**, and
`~/.claude-tide/.claude.json` alongside them. Two files, two accounts, one
directory apart.

This is why `doctor` never treats "pinned to the default root" as equivalent to
"unpinned", and why D01 and D11 are separate rules with separate causes.

**The converse costs the audit a rule.** A profile registered *at* the default
root writes to exactly where an unpinned run writes, in the same layout. On
disk the two are then indistinguishable, so D01 cannot fire for that agent ever
again and `doctor` sees less than it appears to. It is not a defect and there
is no setting that recovers it; it follows from this fact.

Nor can it be undone by moving the root, because of F06. So `new` says it
plainly at registration time, while it is still a choice, and D02 and D03
become the only rules still watching unpinned use. Observed on a real machine,
where one of three accounts lives at `~/.claude`.

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

### F13 `open --env` injects a variable through launchd

**Status:** `VERIFIED` 2026-09-07. This is the entire desktop mechanism.

macOS `open` takes environment variables directly. Verbatim from `open --help`
on the target machine, typo included:

```
--env VAR      Add an enviroment variable to the launched process, where VAR is
               formatted AAA=foo or just AAA for a null string value.
```

**`--env` must come before `--args`**, because everything after `--args` is
passed to the application rather than to `open`. Get the order wrong and the
app launches unpinned while looking correct, which is the exact failure this
tool exists to prevent. That is why the ordering is asserted in the test suite
rather than only commented.

The working form, as the `do shell script` line of an AppleScript applet:

```applescript
do shell script "open -n -a \"/Applications/Claude.app\" --env \"CLAUDE_CONFIG_DIR=/Users/<user>/.claude-tide\" --args --user-data-dir=\"/Users/<user>/Library/Application Support/Claude-Tide\" > /dev/null 2>&1 &"
```

Verified twice, for two separate accounts. `open` hands off to launchd, so the
app is fully detached: it needs no `nohup`, and it survives closing the
terminal that started it.

Note what this does *not* say. `open` passes nothing it inherits from the
invoking shell; a variable reaches the app only because `--env` puts it there
explicitly. Both halves matter, and confusing them is what produced the wrong
sentence F04 used to carry.

**Re-checked by:** `agent-profile verify`, automatically. If `--env` ever
disappears, `desktop`, `app` and D13 are all invalid at once, so `verify`
reports it as broken rather than unchecked.

### F14 A bundle whose executable is a shell script does not launch

**Status:** `VERIFIED` 2026-09-07. Answer: **do not re-attempt this.**

A hand-built `.app` with `CFBundleExecutable` pointing at a `#!/bin/bash`
script fails on current macOS. The Dock icon bounces indefinitely and never
launches, and macOS raises "Support Ending for Intel-based Apps - This version
of 'Claude' will not open in a future release of macOS."

A shell script has no Mach-O header, so LaunchServices cannot determine the
bundle's architecture and treats it as Intel. The wrapper's launch identity
also conflicts with the app it `exec`s, so the launch never completes. An
`X-Y-Z` architecture key in `Info.plist` does not fix it.

AppleScript applets are the launcher form that works. They launch cleanly and
appear in the Dock. This is why `app` generates and patches applets with
`osacompile` rather than assembling a bundle, and why it will never grow a
`--bundle` mode.

### F15 The app binary cannot be launched from an interactive shell

**Status:** `VERIFIED` 2026-09-07.

```sh
CLAUDE_CONFIG_DIR=... /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=... &
```

produces `zsh: error on TTY read: Input/output error`, then `1 jobs SIGHUPed`,
and the shell exits, killing the app. It inherits the terminal's stdin and
Electron does not tolerate that.

Fully detaching it (`nohup`, `</dev/null`, `disown`) would work, but F13 means
the tool never needs this path, so it does not have one.

### F16 The desktop Code pane does not render a custom status line

**Status:** `VERIFIED` 2026-09-07.

Tested directly with a working `statusLine` command configured in a root: the
bar appears in terminal sessions and is absent in the desktop app.

So a status line is a **terminal-only** identity indicator, and anything
promising a visible per-root label has to scope itself to the terminal and say
so. The desktop needs a different tell, and today that is the leak test under
F01 plus the applet audit in D13.

Two related negatives from the same investigation, worth recording because both
look plausible and neither works:

- A status line script that lives inside a config root is tamper-proof by
  construction: it can only run while that root is in use, so its label cannot
  name the wrong account. That property is real and is why the status line is
  the right terminal mechanism.
- The **zsh prompt cannot** show the pinned root when the pin is per-command
  (`CLAUDE_CONFIG_DIR=... claude`), because the variable never enters the shell
  and the prompt only redraws after the command exits. A prompt indicator
  requires actually pinning the shell, which is `agent-profile env` or
  `agent-profile shell`, not `agent-profile run`. This is what
  `which --label` is for, and it exits non-zero when unpinned precisely so an
  unpinned shell shows nothing rather than something stale.

### F17 Each app profile carries its own Claude Code

**Status:** `VERIFIED` 2026-09-07.

The desktop app downloads its own copy of Claude Code per `--user-data-dir`,
at `<app data dir>/claude-code/<version>/`. Observed:
`.../Claude-Tide/claude-code/2.1.258/` while the CLI on the same machine was
2.1.227.

So app profiles are version-independent of each other **and** of the CLI, and
there is no single "Claude Code version" for a machine. Anything reporting one
number would be misleading. It also means each app profile updates on its own
schedule, so an assumption can break for one profile and hold for the rest.

### F18 A profile has two identities and they can disagree

**Status:** `VERIFIED` 2026-09-07.

`--user-data-dir` selects the app's own login. `CLAUDE_CONFIG_DIR` selects the
config root its embedded Claude Code writes to. They are independent.

During the leak, `--user-data-dir` was working correctly the whole time: the
app's login showed the right account while its Claude Code sessions were
writing into another account's root. The app said Tide and meant it, and the
transcripts still went somewhere else.

So "the app says Tide" is not evidence that Code is pinned, and any report that
shows one identity must show the other beside it. `explain` states this, and it
is why `new` records `app_data` and `root` as two separate registry keys rather
than deriving one from the other.

---

## After an agent update

1. `agent-profile verify`
2. If it reports anything broken, fix the tool before trusting `doctor` again.
3. If the desktop app updated, `bash tools/probe-claude-desktop.sh` and compare
   against F05. Do this per profile, not once: F17 means each app profile
   carries its own Claude Code and updates on its own schedule, so an
   assumption can break for one profile while holding for the others.
4. Confirm a real desktop session still lands in the right root (F01):

   ```sh
   agent-profile desktop <name>     # start a Code session in the app, then
   find "$HOME"/.claude* -name '*.jsonl' -mmin -3
   ```

5. Update the "Last full review" line and the affected entries above.
