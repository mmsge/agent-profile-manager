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

## Windows

**No Windows machine has been probed.** Everything in this section was read out
of the published documentation on 2026-09-07, or argued from it. Nothing here
was observed on a running Windows install, so nothing here is `VERIFIED` and
nothing here should be implemented on the strength of a `REASONED` or
`UNVERIFIED` entry alone.

The documentation pages carry no version stamp of their own. The most recent
releases they name a requirement against are Claude Code **v2.1.261** and
Claude Desktop **v1.37937.0**, so they describe at least those. Which versions
a given Windows machine is actually running is a separate question, and F17
applies there too: each desktop profile carries its own copy of Claude Code and
updates on its own schedule.

`tools/probe-claude-windows.ps1` answers W01 to W06 on a real machine. Run it
there, paste its output back into this section, and change the statuses it
settles.

### W01 Does Claude Code on Windows honour `CLAUDE_CONFIG_DIR`?

**Status:** `DOCUMENTED`. Answer: **yes**, as far as the documentation goes.

The Windows default root and the override are stated in one breath:

"On Windows, `~/.claude` resolves to `%USERPROFILE%\.claude`. If you set
`CLAUDE_CONFIG_DIR`, every `~/.claude` path on this page lives under that
directory instead."
([.claude directory](https://code.claude.com/docs/en/claude-directory))

The variable's own entry names no platform, and blesses this exact use:

"Override the configuration directory (default: `~/.claude`). All settings,
session history, and plugins are stored under this path. For credentials, see
where Claude Code stores credentials. Useful for running multiple accounts side
by side: for example, `alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work
claude'`. Set it in your shell, user settings, or managed settings. Ignored in
project and local settings" ([env-vars](https://code.claude.com/docs/en/env-vars))

The same page documents how a variable is set on Windows, in both shells:

```powershell
$env:API_TIMEOUT_MS = "1200000"
claude
```

```batch
set API_TIMEOUT_MS=1200000
claude
```

The uninstall instructions confirm where an unpinned Windows install writes,
which is F10's default case with a Windows path:

```powershell
Remove-Item -Path "$env:USERPROFILE\.claude" -Recurse -Force
Remove-Item -Path "$env:USERPROFILE\.claude.json" -Force
```

([setup](https://code.claude.com/docs/en/setup))

So the variable is documented as platform-neutral and F08 holds with Windows
paths substituted. What is **not** documented is what a Windows *value* may
look like: whether a backslash path, a forward-slash path, a drive-relative
path or a UNC path is accepted, whether Claude Code normalises the string, and
whether a trailing backslash makes a different root. That mattered enormously
on macOS, where the credential is keyed to the literal string (F03), so `new`
normalises before storing. A port cannot reuse `canonical_path` as it stands:
that function is `os.path.normpath` over a POSIX string and knows nothing about
backslashes or drive letters.

**How to re-check:** run the probe. It runs the CLI with the variable pointed
at a throwaway root and lists what appears inside it.

### W02 Where does the credential live without a Keychain, and is Windows Credential Manager used?

**Status:** `DOCUMENTED` for the location and the protection, `UNVERIFIED` for
the access control actually on the file. Answer: `.credentials.json` inside the
root, protected by file permissions, and the Credential Manager is not used.

Quoted verbatim:

"On Windows, credentials are stored in
`%USERPROFILE%\.claude\.credentials.json` and inherit the access controls of
your user profile directory, which restricts the file to your user account by
default."
([authentication](https://code.claude.com/docs/en/authentication))

"If you've set the `CLAUDE_CONFIG_DIR` environment variable, Claude Code keeps
the `.credentials.json` file under that directory instead, including the file
the macOS fallback writes, and keys the macOS Keychain entry to that directory
too, so a session with a different `CLAUDE_CONFIG_DIR` reads a different
entry." (same page, and the same sentence F09 rests on)

"**Secure credential storage**: API keys and tokens are stored in the macOS
Keychain when available, and protected by file permissions on Windows and
Linux." ([security](https://code.claude.com/docs/en/security))

"Claude Code stores sensitive options in the macOS Keychain instead, falling
back to `~/.claude/.credentials.json` when the Keychain rejects the write; on
platforms without a supported keychain, it stores them in
`~/.claude/.credentials.json`."
([settings-reference](https://code.claude.com/docs/en/settings-reference))

The Credential Manager appears nowhere in the documentation, and the security
page is a positive statement rather than a silence: on Windows the protection
**is** the file permissions. Take that as the answer until a probe contradicts
it.

Four consequences for the audit. The first three are `REASONED` from the
quotes above. The fourth is quoted.

**D05 gets simpler and stays exact.** It becomes a test for
`<root>\.credentials.json` and needs no equivalent of `security
find-generic-password`. It still must never read the file.

**D10, D11 and D12 lose their subject.** All three exist because of the macOS
Keychain naming in F03. With no keychain entry there is no hash over a literal
path, so a trailing backslash costs nothing at the credential level, there is
no separate credential trace left by pinning to the default root, and there are
no stray entries belonging to no known root. What replaces D11 on Windows, if
anything, is an open design question rather than a fact.

**D07 has no Windows meaning as written.** Mode 700 is a POSIX concept. The
Windows equivalent is an access control list granting the user alone, and the
documentation leans on inheritance from the profile directory to get it. A root
created outside that directory, on a second drive for instance, inherits that
location's access control list instead, and nothing then restricts a credential
file to one account. A port must read the actual list rather than assume the
sentence above applies wherever a root happens to sit.

**Plaintext is plaintext on every platform.** "Transcripts and history are not
encrypted at rest. OS file permissions are the only protection."
([.claude directory](https://code.claude.com/docs/en/claude-directory))

**How to re-check:** the probe reports whether a credential file appeared in
the throwaway root and prints its access control list. It never reads the
file's content, and it never prints anything from inside it.

### W03 Does Claude Desktop for Windows take `--user-data-dir`, where is it installed, and where is its data directory?

**Status:** `UNVERIFIED`, all three. The values below are reported by others,
recorded so the probe knows where to look, and are not evidence.

**The flag is undocumented on every platform.** `--user-data-dir` appears
nowhere in the Claude Code or Claude Desktop documentation. On macOS the tool
uses it on the strength of direct observation (F13, F17, F18), not of a
published contract. On Windows it is unknown whether the app accepts it, and
the harder half of the question is whether a launcher can hand it over at all
(W05).

**Installation.** The enterprise deployment article describes an MSIX package.
Claude "is packaged as a per-user application"; `Add-AppxPackage -Path
"Claude.msix"` registers it for the current user and
`Add-AppxProvisionedPackage -Online -PackagePath "Claude.msix" -SkipLicense`
stages it for every user on the device
([Deploy Claude Desktop for Windows](https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows)).
Microsoft says where such a package lands and how immovable it is: "App
packages are installed on a per-user basis instead of system-wide. The default
location for new packages on a new machine is under `C:\Program
Files\WindowsApps\<package_full_name>`, with the executable named
*app_name.exe*", and "After deployment, package files are marked read-only, and
are heavily locked down by the operating system (OS)."
([Understanding how packaged desktop apps run on Windows](https://learn.microsoft.com/windows/msix/desktop/desktop-to-uwp-behind-the-scenes))

**Data directory.** Two public issues on the Claude Code tracker report
`%APPDATA%\Claude\` as the desktop app's data directory. One reports that the
packaged process actually reads
`C:\Users\<user>\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\`
while the app's own "Edit Config" button opens the unvirtualised
`%APPDATA%\Claude\`, on Claude Desktop 1.1.3189.0 installed from
`C:\Program Files\WindowsApps\Claude_1.1.3189.0_x64__pzs8sxrjxfjjc\app\Claude.exe`
([issue 26073](https://github.com/anthropics/claude-code/issues/26073)). The
other asks for a way to move `%APPDATA%\Claude\` elsewhere and states there is
none ([issue 57998](https://github.com/anthropics/claude-code/issues/57998)).
Neither is documentation and neither was observed here.

The redirection itself is documented behaviour for a packaged app: "All newly
created files and folders in the user's `AppData` folder (for example,
`C:\Users\<user_name>\AppData`) are written to a private per-user, per-app
location; but merged at runtime to appear in the real `AppData` location."
(same Microsoft page)

**Why this is worse than the macOS case.** On macOS the app data directory is
an ordinary directory and `--user-data-dir` moves it, which is what makes two
app logins possible at once. If Windows redirects `AppData` per package, then a
directory this tool inspects from outside the package may not be the directory
the app reads, and an audit that lists `%APPDATA%` and reports a clean
separation would be reading the wrong files entirely. That is F18's lesson with
a second failure mode stacked on it: the two identities can disagree, and one
of them may not even be where it appears to be.

**How to re-check:** the probe prints the installed package, the executable
path, both candidate data directories, and what appears in each after a launch
with `--user-data-dir` pointed at a throwaway directory.

### W04 Does the desktop app's embedded Claude Code read `CLAUDE_CONFIG_DIR` from the app's process environment?

**Status:** `UNVERIFIED`. This is F01 asked again for Windows, and F01 is the
fact the entire desktop half rests on. It is cheap to settle on a real machine
and it must not be assumed.

Two things point the right way. Neither settles it.

Documented, on what the app inherits:

"The desktop app does not always inherit your full shell environment. On macOS,
when you launch the app from the Dock or Finder, it reads your shell profile,
such as `~/.zshrc` or `~/.bashrc`, to extract `PATH` and a fixed set of Claude
Code variables, but other variables you export there are not picked up. On
Windows, the app inherits user and system environment variables but does not
read PowerShell profiles."
([desktop](https://code.claude.com/docs/en/desktop))

Read that sentence carefully. "User and system environment variables" are the
two scopes Windows keeps in the registry, not a variable placed in the
environment of one launch. Read that way, it promises that a variable written
with `[Environment]::SetEnvironmentVariable(..., "User")` reaches the app, and
that is the one thing a profile manager must never write, because a user-scope
variable pins every process that account starts, this tool's other profiles
included. What the sentence does not say either way is whether one launch's own
environment reaches the app, which is the question W04 asks.

Documented, on the app running the same code:

"If you already use the Claude Code CLI, Desktop runs the same underlying
engine with a graphical interface." (same page)

So the argument runs: the engine reads the variable (W01), and the app is
documented to inherit environment variables on Windows. What is missing is
whether a variable injected into one launch reaches the app process at all,
which is exactly what W05 says is open, and whether the embedded Claude Code
reads it there rather than a value the app resolved for itself.

Until a probe answers this, no Windows desktop launcher should ship. A launcher
that pins nothing looks identical to one that works, which is the whole reason
this file exists: during the migration F18 records, the app named the right
account for weeks while its sessions wrote into another account's root.

**How to re-check:** the probe launches the app with the variable in the
process environment and `--user-data-dir` at a throwaway directory, waits for
the throwaway root to change, and asks whether a Code session was really
started before it draws any conclusion. Nothing is written until a session
runs, so quitting early looks exactly like the app ignoring the variable. The
leak test needs no probe at all:

```powershell
Get-ChildItem "$env:USERPROFILE\.claude*" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-3) }
```

### W05 Which launcher form carries the variable, does it survive a pin, and what is the Windows ordering trap?

**Status:** `UNVERIFIED` for the launcher form and for the pin. `REASONED` for
the three traps, each argued from the documentation quoted below.

macOS has one working answer, `open --env` (F13), and one trap, `--env` after
`--args`. Windows has no `open`. A launcher there has to put the variable into
an environment itself and then start the app, and each available form has a
defect.

| Form | How it carries the variable | Known problem |
| --- | --- | --- |
| `.cmd` file | `set "CLAUDE_CONFIG_DIR=..."` then `start "" "<app>" --user-data-dir=...` | A console window appears while it runs. It carries no icon of its own and is not a shortcut, so pinning it is awkward at best. |
| `.ps1` script | `$env:CLAUDE_CONFIG_DIR = '...'` then `Start-Process` | Double-clicking a `.ps1` opens it in an editor rather than running it, and the execution policy can refuse it. It needs a wrapper before it is a launcher. |
| Shortcut whose target is `cmd /c set ... && start ...` | as the `.cmd` | Has an icon and lives in the Start Menu. Whether a pin keeps the target is the open question. |

**Trap one, and the closest thing to `--env` after `--args`: `setx`.** It is
the obvious way to make the variable stick and it is exactly wrong. Verbatim,
stray word included: "This command writes variables to the master environment
in the registry. Variables set with **setx** variables are available in future
command windows only, not in the current command window."
([setx](https://learn.microsoft.com/windows-server/administration/windows-commands/setx))
So a launcher built on `setx` pins nothing in the run it belongs to, and pins
every later process of that account to one root, which is the opposite of what
a profile manager is for. It also tests as working, because the next window the
tester opens has the variable. The per-window form is the one to use: "The
**set** command, which is internal to the command interpreter (Cmd.exe), sets
user environment variables for the current console window only." (same page)
`[Environment]::SetEnvironmentVariable(..., "User")` has the same defect as
`setx`, and it is what the env-vars page recommends for making a variable
permanent, so the wrong advice is one page away from the right one.

**Trap two: `start` takes a window title first.** Its first parameter is
`"title"`, "Specifies the title to display in the **Command Prompt** window
title bar"
([start](https://learn.microsoft.com/windows-server/administration/windows-commands/start)).
So `start "C:\Program Files\Claude\Claude.exe" --user-data-dir=...` reads
correctly, contains every right string, and launches nothing: the quoted
program path is eaten as a title. The empty first argument, `start "" "C:\..."`,
is the fix. This is the same shape of mistake as `--env` after `--args`, and
the lesser of the two, because it fails loudly.

**Trap three, and the one that may sink the whole approach: shell activation
inherits nothing.** If the app is an MSIX package (W03), a Start Menu entry or
a taskbar pin does not run an executable path. It activates the package by its
Application User Model ID. Microsoft treats activation by that identifier and
launching through an execution alias as different things: "`--with-alias`
Launch the app using its execution alias instead of AUMID activation. The app
runs in the current terminal with inherited stdin/stdout/stderr."
([winapp CLI](https://learn.microsoft.com/windows/apps/dev-tools/winapp-cli/usage))
An activated app is not a child of whatever asked for it, so a variable in the
asking process has no obvious route into it. If that holds, a Start Menu or
taskbar launch is the Windows version of F04's URL handler: a launch path that
cannot carry a config root at all, which the audit can report and cannot fix.
Whether Claude Desktop registers an execution alias, whether that alias takes
`--user-data-dir`, and whether either route carries the environment, are the
three things the probe has to find out.

**Pinning.** Windows identifies what to pin by the Application User Model ID on
the shortcut or the window, and that identifier is also what groups an
application's windows under one taskbar button
([Application User Model IDs](https://learn.microsoft.com/windows/win32/shell/appids)).
A launcher that starts the app through `cmd` produces windows owned by the app
and carrying the app's identity, so the taskbar button the user sees is the
app's own, and pinning that button pins the app rather than the launcher. Since
that pin is what a person will reach for every morning, a launcher that only
works when started from its own shortcut is a launcher that stops being used.
Whether pinning the shortcut file itself preserves the wrapper is what the
probe asks the human to try.

**How to re-check:** the probe writes a `.cmd` launcher and a shortcut to it
into a throwaway directory, proves mechanically whether that form carries the
variable into a process it starts, launches the app through it, and then asks
the reader to pin the shortcut and report what happened. The `.ps1` form is not
tested, because a script that cannot be double-clicked is not a launcher.

### W06 Do the transcript layout and the `cwd` field match F11 and F12, and how is a Windows path encoded?

**Status:** `DOCUMENTED` for the layout and the encoding rule, `REASONED` for
what a drive letter and backslashes become, `UNVERIFIED` for the `cwd` field.

"By default, Claude Code stores transcripts as JSONL at
`~/.claude/projects/<project>/<session-id>.jsonl`, where `<project>` is your
working directory path with non-alphanumeric characters replaced by `-`. For a
working directory whose converted name exceeds 200 characters, Claude Code
truncates the name to 200 characters and appends a hash of the full path, so
the directory name stays within filesystem limits."
([sessions](https://code.claude.com/docs/en/sessions))

With W01's root, that is
`%USERPROFILE%\.claude\projects\<project>\<session-id>.jsonl`, or the same
under a pinned root.

**The encoding rule is platform-neutral, and every character that makes a
Windows path a Windows path is non-alphanumeric.** So `C:\Users\me\src\my-repo`
encodes to `C--Users-me-src-my-repo`: the colon and both separators all become
the same dash. F12's warning gets worse rather than better. Every project on
one drive shares a prefix, and `C:\a\b`, `C:/a/b` and `C-\a\b` collide. Never
try to decode a project directory name; read `cwd`.

That is reasoned from the rule, not observed. Whether Claude Code encodes the
path as typed or after normalising it, and what it makes of a UNC path, which
opens with two separators, is unknown.

**`cwd` is the field D03 reads**, and D03 is the rule that catches real
leakage. F11 records it as observed, on macOS and on Linux. The sessions page
declines to promise it anywhere: "Each line is a JSON object for a message,
tool use, or metadata entry. The entry format is internal to Claude Code and
changes between versions, so scripts that parse these files directly can break
on any release." So on Windows it is unverified until somebody looks.

Two consequences a port must handle even once `cwd` is confirmed present.

**Path comparison changes meaning.** The value will be a Windows path, and
Windows path comparison is case-insensitive: `C:\Src\app` and `c:\src\app` are
one directory. D03 compares paths textually today, so a direct port would miss
a leak between two roots that spell the same directory differently, and D03
failing to find a leak is the worst outcome this tool has.

**D08 still applies.** `CLAUDE_CODE_PROJECT_DIR_NAME` names the project
directory outright, and its documented rules already carry a Windows clause:
"Use 1-64 letters, digits, hyphens, or underscores: don't use a Windows device
name such as `con`." (same page)

**How to re-check:** the probe prints the project directory names under the
throwaway root and the `cwd`, `sessionId` and `version` fields of the first
transcript it finds.

### How these move forward

Someone has to run the probe on Windows, with Claude Code installed and the
desktop app signed in, and paste the output back here.

```powershell
powershell -ExecutionPolicy Bypass -File tools\probe-claude-windows.ps1
```

That settles W02, W03, W04 and W06, and confirms W01 on a real machine rather
than on a documentation page. W05 needs one extra minute from a person: pin the
launcher the probe leaves behind, launch from the pin, and run the leak test to
see which root the session wrote to.

Until then the cross-platform rewrite has a specification with holes in it: the
access control list in W02, the whole of W03, W04 and W05, and the `cwd` field
in W06. W04 is the one that decides whether the Windows desktop half can exist
in the shape the macOS one has.

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
