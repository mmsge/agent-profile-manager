# Tool review: Agent Profile Manager

> `agent-profile`, installed as `agpin`, keeps several Claude accounts apart on
> one Mac by giving each its own config root, pins the terminal and the desktop
> app to that root, and audits that the separation actually holds.

Reviewed at version 0.7.0, commit `c61622c`, on 2026-09-07. The review was
done by Claude Code with Markus interviewed on scope, audience and appetite.
The interview answers are recorded below because the ranking follows from
them.

## Scope and method

Everything in the repository was read: the 2,346-line script, the 152 tests
and their harness, the installer, the desktop probe, `docs/FACTS.md`, the
README and the CI workflow. The suite was run on Linux, where it passes, and
the bash 3.2 lint was run. Install, first run, daily use, offboarding and
the failure paths were traced by reading rather than on a Mac, so anything
below that depends on real macOS behaviour says so.

The tool will be pitched to consultants who each work for several customers.
Security and ease of use are the two things that matter to that audience.

Decisions from the interview:

| Question | Answer |
| --- | --- |
| Platforms in use | Mostly Windows, some macOS |
| Expected install | Homebrew or a one-liner, not `git clone` |
| Licence | Free to use for anything, but redistribution or repackaging must stay open |
| Windows strategy | Rewrite as one cross-platform tool, language to be recommended |
| IDE extensions | Common (VS Code, JetBrains, Cursor) |
| Seeding new profiles with a baseline | Open to suggestions |
| Threats to weigh | Accidental cross-customer leakage, supply chain and tampering, compliance evidence, local data at rest |
| Effort in each suggestion | The Claude Code effort level to run the implementing session at |
| Small bugs found | Fix them in this pull request |

Every suggestion names a model and an effort level. The model is chosen from
the current family: Claude Fable 5.1 (`claude-fable-5-1`) for the one piece
of long-horizon architectural work, Claude Opus 5 (`claude-opus-5`) for
design and security work, and Claude Sonnet 5 (`claude-sonnet-5`) for
well-specified documentation and polish. Effort is one of `low`, `medium`,
`high`, `xhigh` or `max`, set in Claude Code with `/effort` or the `effort`
setting.

## Summary

The engineering is unusually good for a shell tool of this size. The
behaviour it depends on is written down with evidence in `docs/FACTS.md`,
`verify` re-checks that evidence against the installed version, every
`doctor` rule names the offender and a fix, exit codes are contracted so it
runs unattended, and 156 dependency-free tests run under the real bash 3.2 in
CI. Messages are honest to a fault: "already applied" and "never worked" are
never allowed to look the same.

Two themes decide the ranking. First, it solves the macOS problem completely
and the audience is mostly on Windows, so a cross-platform rewrite is the
largest item and everything Mac-specific below it becomes a port
requirement. Second, the security story is deep on accidental leakage
between roots and thin on everything else a consultancy asks about: nothing
covers the IDE extension path or a direct launch of the desktop app, there is
no offboarding, no tagged release or checksum, no machine-readable evidence,
and no licence.

## Findings by area

### Install

The install is `git clone` and `tools/install.sh`, which symlinks the
checkout into `~/.local/bin`. The installer is careful: idempotent, refuses to
replace a real file, warns about `PATH`, and uninstalls only what it made.
Three things work against the audience.

- There are no tags or releases even though the script reports version
  0.7.0, so nobody can install a known version, and there is nothing to
  verify a download against.
- The symlink means `git pull` changes the command silently, and because
  `eval "$(agpin guard)"` runs at every shell start, anyone who can push to
  the repository, or tamper with the checkout, runs code in every coworker's
  shell. The README presents this as a feature.
- `python3` is used for JSON. On a fresh Mac that triggers the Command Line
  Tools install dialog on first use, which the README's "no dependencies
  beyond a stock macOS" does not prepare a reader for.

### Use and UX

Daily use is good. The bare `agpin` picker, `claude bouvet` through the
guard, the derived prompt label, and `app` repairing a launcher in place are
all the right shape, and the tool naming itself by whichever name it was
invoked as is a detail most tools get wrong.

- There is no way to remove a profile. When an engagement ends, the registry
  entry, the root full of customer transcripts, the app data directory, the
  launcher and the Keychain entry all have to be found and removed by hand.
- Output is long. Every command prints paragraphs of rationale, which is
  wonderful the first time and noise the fortieth. There is no `--quiet` and
  no `--json`.
- No shell completions for commands or profile names, and the guard is a
  bash and zsh function only, so fish users get nothing.
- A coworker who has used Claude Code unpinned for months gets a wall of
  D01, D02 and D06 findings on the first `doctor`. The adoption flow that
  resolves it is documented, but far down the README.
- `which --label` in the prompt parses the whole script on every redraw. It
  is probably fine, but nobody has measured it.

### Documentation

`docs/FACTS.md` is the best part of the project: every assumption, its
evidence, its status and the version it was checked against. The README is
thorough and well written, but it is an essay about why the tool is the way
it is, and a new coworker needs a ten-minute start, a migration recipe and a
plain statement of what the tool does not protect against. There is no
licence, no changelog, no contributing guide, and no troubleshooting section.

### Security

Strengths: roots are mode 700, the tool never reads a secret and the source
is tested for it, the Keychain check is exact rather than heuristic, the
desktop launch line is audited against one shared definition of correct, and
the record of why each rule exists is written down.

Gaps, in the order they matter to a consultancy:

- **IDE extensions bypass everything.** VS Code, JetBrains and Cursor spawn
  the CLI from the IDE process with the IDE's environment. The shell guard
  never runs, no applet is involved, and `doctor` has no rule for it.
- **A direct launch of Claude.app is unpinned.** Spotlight, Launchpad, the
  real app in the Dock, or Open at Login all start the app with the default
  app data directory and no config root. The default app data directory is
  never audited, and D01 only fires after a Code session has already
  written a transcript.
- **No offboarding.** Customer data has no end of life.
- **No supply chain story.** No tagged releases, checksums, signed tags or
  pinned installs; see Install above.
- **No evidence.** `doctor` output is prose. A customer's security officer
  cannot consume it, and it carries no timestamp, version or host.
- **D12 enumerates the whole login Keychain** with `security dump-keychain`
  to find orphaned entries. It reads attributes only, but a security-minded
  coworker will want to know that before running it.
- Three concrete bugs, fixed in this pull request: the app data directory
  was created with the umask default and never audited although it holds the
  desktop app's own login; temporary files were named from `$$`; and the two
  source-invariant tests grepped the test shim instead of the script, so they
  passed without checking anything.

### Portability

macOS only, by design, in bash 3.2 with `security`, `open --env`,
`osacompile`, `sips` and `iconutil`. The suite runs on Linux, which is a good
sign for the pure-logic parts, but the credential check, the desktop half and
the launcher audit have no equivalent anywhere else. Windows users could run
the bash tool inside WSL for the CLI only, and the desktop app would stay
unpinned.

## Suggested improvements

Ranked from most to least recommended. Each carries the labels for its
GitHub issue, the model and effort to run the implementing session at, and a
prompt that session can act on directly.

### 1. Establish the Windows facts before any port

**Why this matters:** Every macOS behaviour the tool rests on is recorded in
`docs/FACTS.md` with evidence. Nothing equivalent exists for Windows, and a
port built on guesses would repeat the migration mistakes F13 to F18
document. The questions are few and concrete: does Claude Code on Windows
honour `CLAUDE_CONFIG_DIR`; where does it keep the credential when there is
no Keychain; does Claude Desktop for Windows accept `--user-data-dir`; does
its embedded Claude Code read the variable from the process environment; and
what launcher form can carry an environment variable, given that a shortcut
cannot.

**Labels:** portability, docs

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Add a Windows section to `docs/FACTS.md` with facts W01 to W06, using the
> same status vocabulary as the existing F entries: W01 Claude Code on
> Windows honours `CLAUDE_CONFIG_DIR`; W02 where the credential lives without
> a Keychain (expected `.credentials.json` inside the root, confirm its
> permissions); W03 Claude Desktop for Windows accepts `--user-data-dir` and
> where its default data directory is; W04 the embedded Claude Code reads
> `CLAUDE_CONFIG_DIR` from the app's process environment; W05 the launcher
> form that carries an environment variable (a `.cmd` or PowerShell script,
> or a shortcut whose target is `cmd /c set ... && start`), and whether it
> survives a Start Menu pin; W06 the transcript layout and `cwd` field match
> F11 and F12. Write `tools/probe-claude-windows.ps1` in the style of
> `tools/probe-claude-desktop.sh`: throwaway root and data directory,
> never reads a secret, prints answers a human pastes back into the file.
> Mark every fact `UNVERIFIED` until the probe has been run on a real Windows
> machine, and say in the section header which Claude Code and Claude
> Desktop versions it was run against.

### 2. Rewrite as one cross-platform tool, in Go

**Why this matters:** Most of the audience is on Windows and the tool is a
bash 3.2 script wrapped around macOS-only commands. A PowerShell sibling
would mean two implementations of fifteen audit rules drifting apart. One
binary per platform from one codebase is the only shape that keeps `doctor`
meaning the same thing on every coworker's machine.

Go is the recommendation. It cross-compiles to darwin, windows and linux
from one machine, produces a single static binary with no runtime, which
also removes the `python3` dependency, and goreleaser turns a tag into
signed archives, checksums, a Homebrew tap and winget and scoop manifests
with almost no configuration, which is exactly what suggestion 3 needs.
C# with single-file publish would also work and fits a Microsoft shop, but
the binaries are an order of magnitude larger, start slower, and packaging
for brew, winget and scoop is not the well-trodden path. Rust would produce
an equally good binary at a slower pace of iteration for no gain a tool of
this size can use.

**Labels:** portability, enhancement

**Run with:** Claude Fable 5.1 (`claude-fable-5-1`), effort `xhigh`. Claude
Opus 5 at `xhigh` is the cost-conscious alternative.

**Implementation prompt:**

> Port `bin/agent-profile` to Go as a single binary with the same command
> surface, messages, exit code contract and registry format, so an existing
> Mac user upgrades with no change to `~/.config/agent-profiles`. Structure
> it around two seams: an `Agent` interface (Claude today, with the
> per-agent constants from `agent_def`) and a `Platform` interface with
> darwin, windows and linux implementations covering the default root, the
> state file, the credential existence check (Keychain on darwin, the
> credentials file elsewhere until W02 says otherwise), the desktop launcher
> (`open --env` and an applet on darwin, a script launcher on windows per
> W05, none on linux), and the launcher scan. Keep every D rule and every
> `verify` check, and make a rule that cannot run on a platform report
> itself as unchecked rather than silent, the way `verify` already does.
> Port the 156 shell tests as Go tests with golden output files, and run
> them on ubuntu, macos and windows runners. Treat the Windows facts in
> `docs/FACTS.md` as the specification for the windows platform and refuse
> to implement anything they mark UNVERIFIED. Keep the bash script under
> `legacy/` until the Go binary passes the same suite on macOS, then remove
> it.

### 3. Tagged releases, checksums, signed tags and package-manager installs

**Why this matters:** Coworkers will run this at every shell start on
machines that hold customer data. Today the only install is a symlink to a
git checkout that changes whenever `git pull` runs, there is no tag to pin
to and no checksum to verify. The interview asked for Homebrew or a
one-liner, and both need a release artifact to point at.

**Labels:** distribution, security

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Add a release process. Tag `v0.7.1` and every later version with an
> annotated, signed tag, and add a GitHub Actions workflow that on a tag
> builds a tarball of `bin/`, `tools/` and `docs/`, writes `SHA256SUMS`,
> signs it with Sigstore (`cosign sign-blob`, keyless), and publishes a
> GitHub Release. Change `tools/install.sh` so that its default mode
> downloads a named release (`--version vX.Y.Z`, default latest), verifies
> the checksum and signature, and installs a copy rather than a symlink;
> keep the symlink mode behind `--dev` for people working on the tool.
> Publish a Homebrew tap formula that installs from the release tarball and
> pins its sha256. Add `agpin version --check` that compares the running
> version to the latest release and says so, without ever updating itself.
> Document the one-liner in the README and say plainly that the old symlink
> install executes whatever is in the checkout. When the Go rewrite lands,
> replace the workflow with goreleaser and add winget and scoop manifests.

### 4. Add a copyleft licence: GPL-3.0-or-later

**Why this matters:** There is no LICENSE file, so legally nobody may copy
the tool anywhere, including to a coworker's laptop. The requirement from
the interview is free use for any purpose, with redistribution or
repackaging required to stay open. That is strong copyleft, and
GPL-3.0-or-later is the standard licence that says exactly that. MPL-2.0 is
the weaker alternative if you would rather allow the files to be embedded in
a larger closed tool as long as the files themselves stay open. AGPL adds
nothing here because the tool is not a network service.

**Labels:** docs

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `low`

**Implementation prompt:**

> Add the GNU General Public License version 3 as `LICENSE` at the
> repository root, verbatim from gnu.org. Add an SPDX line,
> `# SPDX-License-Identifier: GPL-3.0-or-later`, immediately under the
> shebang of `bin/agent-profile`, every script in `tools/`, `tests/run.sh`
> and every file in `tests/cases/`, and make `tools/lint-bash32.sh` and the
> shellcheck job tolerate it. Add a short "Licence" section at the end of the
> README saying the tool is GPL-3.0-or-later, that using it on any machine
> for any customer is fine, and that redistributing a modified copy means
> publishing the modifications under the same licence. Make `agpin version`
> print the licence identifier on a second line.

### 5. Cover the IDE extension leak path

**Why this matters:** The interview says IDE extensions are common. The
Claude Code extensions for VS Code, JetBrains and Cursor spawn the CLI from
the IDE process, so the shell guard never sees the call, the desktop
launcher is not involved, and the CLI inherits whatever environment the IDE
was launched with, which for a Dock or Spotlight launch is no
`CLAUDE_CONFIG_DIR` at all. Every session started from an IDE today writes
to the default root, and `doctor` has no rule that says so.

**Labels:** security, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Close the IDE gap in three steps. First, establish the facts and record
> them in `docs/FACTS.md` as F19 to F21: whether the VS Code, JetBrains and
> Cursor extensions honour `CLAUDE_CONFIG_DIR` from the IDE's process
> environment, whether any of them exposes a setting for it, and where each
> extension records its installed presence on disk. Second, add a `doctor`
> rule D16 that reports an installed Claude Code IDE extension as an
> unpinnable launch path unless the IDE itself is launched pinned, with the
> same tone as D09, and add `verify` coverage so a change in how extensions
> are installed reports as unchecked rather than silent. Third, add a
> supported way to launch an IDE pinned, `agpin code <profile> [path]` for
> VS Code and Cursor and `agpin idea <profile> [path]` for JetBrains, using
> `open --env` on macOS in the same way `desktop` does, and document in the
> README's threat model that an IDE opened any other way runs the extension
> unpinned. Write tests with a stand-in extension directory the way
> `70-desktop.sh` uses stand-in tools.

### 6. Audit direct launches of the desktop app

**Why this matters:** The applets built by `app` are the only pinned way to
open Claude Desktop, but nothing stops a coworker opening the real
`Claude.app` from Spotlight, Launchpad, the Dock or Open at Login. That
launch uses the default app data directory and no config root, and it is
the most likely mistake a new user makes on day one. `doctor` audits the
applets it knows about and the default config root, but never the default
app data directory at `~/Library/Application Support/Claude`, so a desktop
account living there is invisible.

**Labels:** security, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Add two `doctor` rules for the desktop app itself. D17 reports when the
> real app bundle, rather than an applet, is pinned in the Dock (read
> `defaults read com.apple.dock persistent-apps` and look for the bundle
> path from `agent_def app_bundle`) or registered as a login item, and says
> that either launches it unpinned. D18 reports when the default app data
> directory exists and holds a login, which means the desktop app has been
> run unpinned, and names the account it finds there using the same
> approach `list` uses for a root if the app stores one, otherwise reports
> the directory and its modification time. Both rules run only on macOS and
> report as unchecked elsewhere. Add a `doctor` hint after D17 suggesting
> the user drag the applets into the Dock and the real app out of it.
> Record how the Dock and login items are read as F22 in `docs/FACTS.md`,
> add stand-in `defaults` output to the test fixtures, and add the two rules
> to the README table.

### 7. Offboarding: a `remove` command and an engagement-end checklist

**Why this matters:** Consultants end engagements. Today the only way to
retire a profile is to delete a registry file by hand and then find the
root, the app data directory, the applet and the Keychain entry yourself.
That is exactly when customer data gets left behind on a laptop. The tool's
promise to never touch credentials can be kept while still telling the user
precisely what to delete.

**Labels:** security, ux

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Add `agpin remove <profile>`. With no flags it removes only the registry
> entry and prints, in order, everything else that still exists for the
> profile: the root with its session count, the app data directory, the
> applet, and the Keychain service name derived by `cred_info`, each with
> the exact command to delete it. With `--purge` it deletes the root, the
> app data directory and the applet itself after the user types the
> profile name back at a prompt, and it still only prints the
> `security delete-generic-password -s <service> -a $USER` command for the
> credential, because the tool never touches credentials. Refuse `--purge`
> when stdin is not a terminal. Print a final "left on this machine" list
> so nothing is silently retained. Add a section to the README called
> "When an engagement ends" that walks through `remove --purge`, running
> `doctor` afterwards to confirm D06, D12 and D14 are quiet, and what to do
> about the D12 orphan that remains if the Keychain entry is not deleted.
> Cover it with tests in a new `tests/cases/90-remove.sh`.

### 8. Machine-readable `doctor --json` and a timestamped evidence report

**Why this matters:** The interview asks for compliance evidence. A customer's
security officer wants to know that their data is isolated on the
consultant's machine, and today the only answer is a screenshot of prose.
`doctor` already has a stable rule vocabulary and exit codes, so the data
is there.

**Labels:** security, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `medium`

**Implementation prompt:**

> Add `--json` to `doctor`, `list` and `verify`. The `doctor` document
> carries `generated_at` in UTC, `tool_version`, `verified_against`, the
> installed agent version, the hostname and user, the registered profiles
> with root, app data directory, account email and organisation id, and a
> `findings` array where each entry has `rule`, `summary`, `subject` and
> `detail`, matching the fields `finding()` already prints. Keep the human
> output unchanged and keep the exit codes. Then add `doctor --report FILE`
> that writes the JSON document and a Markdown rendering side by side, so
> a consultant can hand a customer a dated audit of their machine. Route
> all output through one function so JSON and prose cannot drift apart.
> Document the schema in `docs/AUDIT-SCHEMA.md` and add tests that parse
> the JSON with `python3 -m json.tool`.

### 9. Baseline guardrails for new profiles

**Why this matters:** `new` creates an empty root, on purpose, and the
README explains why copying settings across roots produces files that
drift. The audience will feel the cost immediately: every customer profile
starts with no hooks, no permission rules and no company baseline, and the
tool prints that as a warning and leaves it there. The interview left this
open, so three options are laid out. The recommendation is the third,
because it uses Claude Code's own mechanism instead of the tool copying
files.

1. Keep the policy, and make the gap visible: `new` prints a first-run
   checklist and a `doctor` rule reports a root with no `settings.json`.
2. An explicit `new --from DIR` that copies once, records `seeded_from=` in
   the registry, and never syncs again.
3. Publish the company baseline as a Claude Code plugin in a private
   marketplace, and have `new` print the one `claude plugin install`
   command to run inside the fresh profile. Each root installs its own
   copy through Claude Code, updates come from the marketplace, and the
   tool still never shares or copies a file between roots.

**Labels:** ux, enhancement

**Run with:** Claude Opus 5 (`claude-opus-5`), effort `high`

**Implementation prompt:**

> Implement the plugin route for baseline guardrails. Add an optional
> `baseline=` key to the registry, set by `new --baseline <marketplace>/<plugin>`
> or by a `AGENT_PROFILE_BASELINE` default, and have `new` end its output
> with the exact `claude plugin install` command to run pinned to the new
> profile. Add a `doctor` rule D19 that reports a profile whose root has no
> `settings.json` at all, worded as "this profile has no guardrails", and
> when a baseline is registered, reports a root where that plugin is not
> installed by reading the root's plugin directory only, never writing to
> it. Keep the no-sharing invariant intact: the tool must not copy, link or
> write anything inside a root, and `tests/cases/50-isolation.sh` must
> still pass. Write a short `docs/BASELINE.md` explaining how a team
> publishes its baseline plugin and why this is preferred over copying
> settings.

### 10. A ten-minute start, a migration recipe and a threat model in the docs

**Why this matters:** The README is a well-argued design document, and a
coworker who wants to be safe by lunch has to read all of it to find the
four commands that matter. The pieces are all present but in the wrong
order, and the one document a security-minded reader looks for first,
what the tool does not protect against, does not exist.

**Labels:** docs, ux

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `medium`

**Implementation prompt:**

> Restructure the documentation without losing content. Put a "Ten-minute
> start" at the top of the README: install, `new` for each account, the two
> rc-file lines, `doctor`, and `app` for the desktop, each with the exact
> command and the output to expect. Follow it with "Moving a machine you
> already use", the adoption recipe that now sits far down the page,
> including what the first `doctor` run will report on a machine that has
> run unpinned for months and how each finding is resolved. Add a
> "What this does not protect against" section listing the URL handler,
> IDE extensions, direct launches of the desktop app, `command claude`,
> scripts and cron jobs that call `claude`, MCP servers that spawn the CLI,
> roots outside `~/.claude-*` that D06 cannot see, and Windows. Add a
> troubleshooting section built from the existing error messages. Move the
> design essays to `docs/DESIGN.md` and link to them. Keep every fact and
> every command the README carries today, and keep the writing style:
> commas and full stops, hyphens only in compounds.

### 11. Shorter default output, with `--explain` for the rationale

**Why this matters:** The messages are the tool's best feature on first use
and its most tiring on the fortieth. `new` prints eleven lines of
explanation for a profile at the default root, `app` prints a paragraph on
what a second run looks like, and `which` explains what unpinned means.
None of it is wrong, and none of it needs to be printed every time.

**Labels:** ux

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `medium`

**Implementation prompt:**

> Introduce two output levels without changing what any command does.
> Default output states what happened and the next command, in at most
> three lines for `new`, `app`, `desktop` and `which`. A global `--explain`
> flag, or `AGENT_PROFILE_EXPLAIN=1`, restores the full rationale exactly
> as it prints today. `doctor` findings keep their detail lines, because
> they are the product. Add `--quiet` to `doctor` and `verify` so they
> print nothing on a clean run and rely on the exit code, for cron and
> shell hooks. Update the tests that assert on the long form to run with
> `--explain`, and add tests for the short form. Keep the self-naming: every
> line still uses `$SELF`.

### 12. Shell completions, a fish guard and a `shell` choice in the picker

**Why this matters:** Profile names are typed many times a day and the
tool knows them all. Completions for commands and profile names cost
little and remove the copy-paste slip the README opens with. The guard is a
bash and zsh function only, and fish is common enough among consultants
that a fish user today gets no protection at all.

**Labels:** ux, enhancement

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `medium`

**Implementation prompt:**

> Add `agpin completion bash|zsh|fish` that prints a completion script
> covering every subcommand, its flags, and profile names from
> `profile_names`, printed rather than installed for the same reason
> `guard` is. Add a fish variant of `guard`, selected by `guard --shell
> fish` or by reading `$SHELL`, that refuses an unpinned run and forwards a
> leading profile name exactly like the bash and zsh function. Add
> "subshell" as a third choice in the interactive picker so the picker
> covers everything `run`, `shell` and `desktop` do. Document the rc-file
> lines for all three shells in the README's quick start and test the
> completion output with a stand-in shell the way `80-install.sh` tests the
> guard.

### 13. CI on Linux as well as macOS, and a release workflow

**Why this matters:** The suite passes on Linux today, which is where most
automation and any future Go port will run first, but CI never tries it, so
a GNU versus BSD drift in `stat`, `sed` or `find` would ship unnoticed.
The lint job also runs on a macOS runner, which is the slowest and most
expensive runner GitHub has, for work that needs neither macOS nor bash 3.2.

**Labels:** distribution

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `low`

**Implementation prompt:**

> In `.github/workflows/ci.yml` add an `ubuntu-latest` entry to the test
> matrix that runs the suite under the system bash, keeping the two macOS
> entries. Move the shellcheck and bash 3.2 lint job to `ubuntu-latest` and
> install shellcheck with apt. Add a `release.yml` workflow triggered by a
> `v*` tag that runs the same test matrix and then performs the release
> steps from the distribution issue. Make the test step fail if the number
> of tests run differs from the count in the README, so the two cannot
> drift.

### 14. Measure and trim the per-prompt cost of `which --label`

**Why this matters:** The README recommends putting `agpin which --label`
in the prompt, and `guard` runs the tool once more at every shell start.
Each call parses a 100 KB script and reads the registry. That is probably
ten to thirty milliseconds, which is at the edge of what people notice in a
prompt, and nobody has measured it.

**Labels:** ux

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `medium`

**Implementation prompt:**

> Measure `agpin which --label` and `agpin guard` with `hyperfine` or a
> loop of one hundred runs under `/bin/bash` on macOS, and record the
> numbers in `docs/FACTS.md` as a note. If the label call is above ten
> milliseconds, add a fast path at the top of `bin/agent-profile` that
> handles `which --label` before any other function is defined, reading
> only the environment and, for the default-root exception, the one
> registry file it needs. Add a `precmd`-based zsh snippet to the README
> that caches the label per shell and refreshes it only when
> `CLAUDE_CONFIG_DIR` changes, and a matching starship snippet. Keep the
> guarantee that the label is derived from the pinned root on every call
> and never stored.

### 15. Make the Keychain enumeration in D12 opt-in and document what doctor reads

**Why this matters:** D12 runs `security dump-keychain` to find orphaned
credential entries. It reads attributes only and the source is tested for
that, but it enumerates every item in the login Keychain, which is slow on
a large Keychain and is the kind of thing a security-conscious coworker
wants to have been told about before running an audit tool. The other
Keychain rules only ask about specific service names and are fine.

**Labels:** security

**Run with:** Claude Sonnet 5 (`claude-sonnet-5`), effort `low`

**Implementation prompt:**

> Move the D12 orphan scan behind `doctor --keychain-scan`, keeping D05 and
> D11 as they are because they query named services only. When the flag is
> absent, print one line saying that orphaned Keychain entries were not
> checked and how to check them. Add a section to the README called "What
> doctor reads" that lists every file, directory, Keychain query and
> external command each rule uses, generated from a comment block above
> each rule so it cannot drift, and state explicitly that no rule ever
> reads a credential value. Update the D12 tests in
> `tests/cases/60-credentials.sh` to pass the flag.

## Fixed in this pull request

- The two source-invariant tests in `tests/cases/50-isolation.sh` grepped
  the harness's shim instead of `bin/agent-profile`, so they passed without
  checking anything. They now read the script, the credential rule forbids
  only the flags that print a secret, and the case proves it is reading the
  right file.
- The app data directory was created with the umask default and never
  audited. `new` sets it to 700 and reports tightening an existing one, and
  D07 reports one that is not 700.
- Temporary files and directories were named from `$$`. They come from
  `mktemp` now, and a source invariant refuses the `$$` form.
- The comment claiming `dump-keychain` reads secrets with `-g` now names the
  right flag, `-d`.
- Version bumped to 0.7.1.

## What is working well

- `docs/FACTS.md` and `verify` together are a model for any tool that
  depends on undocumented behaviour of something that updates monthly. F11
  in particular, catching the case where `doctor` would pass silently, is
  the right instinct.
- The `doctor` rules each name an offender, a cause and a fix, and the exit
  code contract makes the tool usable from cron. D03 needs no configuration
  and catches the leak that matters.
- The messaging discipline: "adopted" versus "created", "already correct"
  versus "repaired", refusing to guess between two launchers, cancelling on
  an empty answer. These are the details that stop a tool from lying.
- 156 tests with no dependencies, run under the real bash 3.2 and under
  current bash, with stand-in `security`, `open`, `osacompile`, `sips` and
  `iconutil` so the macOS-only paths are exercised on every platform.
- The tool never reads a credential, and the source is tested for it. The
  one launch-line definition shared by `app` and D13 means the audit and the
  repair cannot disagree.
