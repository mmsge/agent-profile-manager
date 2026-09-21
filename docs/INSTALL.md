# Install

The one-liner, what it verifies and what it trusts, Homebrew, the options,
staying current, the development install and the Windows status. Every
output shown is generated from a real run of the installer against a release
laid out the way GitHub lays one out.

## The one-liner

<!-- BEGIN GENERATED: example install (tools/gen-doc-examples.sh) -->
```sh
curl -fsSL https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh | bash
```

```
Asking which release is newest...
Downloading agent-profile-0.11.0.tar.gz
Checksum matches SHA256SUMS for v0.11.0.
Signature verified: built by the release workflow, from tag v0.11.0.
Unpacked v0.11.0 into /Users/alex/.local/share/agent-profile/0.11.0

Installed /Users/alex/.local/bin/agpin -> /Users/alex/.local/share/agent-profile/0.11.0/bin/agent-profile
Installed /Users/alex/.local/bin/agent-profile -> /Users/alex/.local/share/agent-profile/0.11.0/bin/agent-profile

WARNING: /Users/alex/.local/bin is not on your PATH, so the command will not be found.
Add this to your shell rc file:
  export PATH="/Users/alex/.local/bin:$PATH"

Next:
  agpin help
  agpin doctor
  agpin version --check

Worth adding to ~/.zshrc (zsh, from $SHELL):

  eval "$(/Users/alex/.local/bin/agpin guard)"           # refuse to run the agent unpinned
  eval "$(/Users/alex/.local/bin/agpin completion zsh)"  # tab-complete commands and profile names
  PROMPT='$(/Users/alex/.local/bin/agpin which --label 2>/dev/null) %~ %# '

Another shell: agpin shellrc --shell bash|zsh|fish, or --explain for all three.
```
<!-- END GENERATED: example install -->

That downloads the newest tagged release, checks it against the `SHA256SUMS`
published beside it, checks the Sigstore signature if you have `cosign`,
unpacks it into `~/.local/share/agent-profile/<version>/` and links both
`agpin` and `agent-profile` at that copy. What runs in your shell then changes
only when you run the installer again.

Install `cosign` first if you want the signature checked, and you do:

```sh
brew install cosign
```

Without it the checksum is still checked, and the installer says loudly what
went unchecked:

<!-- BEGIN GENERATED: example install-no-cosign (tools/gen-doc-examples.sh) -->
```sh
curl -fsSL https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh | bash
```

```
Asking which release is newest...
Downloading agent-profile-0.11.0.tar.gz
Checksum matches SHA256SUMS for v0.11.0.

WARNING: cosign is not installed, so the signature was NOT checked.
         The checksum proves the download is intact. It does not prove
         who produced it: whoever served SHA256SUMS also served the
         tarball, so a swap of both would pass both checks.
         Run brew install cosign and this script again to check the
         Sigstore signature, which ties the file to the tag and to
         the workflow that built it.

Unpacked v0.11.0 into /Users/alex/.local/share/agent-profile/0.11.0

Installed /Users/alex/.local/bin/agpin -> /Users/alex/.local/share/agent-profile/0.11.0/bin/agent-profile
Installed /Users/alex/.local/bin/agent-profile -> /Users/alex/.local/share/agent-profile/0.11.0/bin/agent-profile

WARNING: /Users/alex/.local/bin is not on your PATH, so the command will not be found.
Add this to your shell rc file:
  export PATH="/Users/alex/.local/bin:$PATH"

Next:
  agpin help
  agpin doctor
  agpin version --check

Worth adding to ~/.zshrc (zsh, from $SHELL):

  eval "$(/Users/alex/.local/bin/agpin guard)"           # refuse to run the agent unpinned
  eval "$(/Users/alex/.local/bin/agpin completion zsh)"  # tab-complete commands and profile names
  PROMPT='$(/Users/alex/.local/bin/agpin which --label 2>/dev/null) %~ %# '

Another shell: agpin shellrc --shell bash|zsh|fish, or --explain for all three.
```
<!-- END GENERATED: example install-no-cosign -->

If `~/.local/bin` is already on your `PATH`, the warning about it is replaced
by a line saying so. The tool names itself by whichever name you invoke:
run it as `agpin` and every message, error and suggested fix says `agpin`.

Worth adding to your shell rc file, and `agpin shellrc` prints it for the
shell `$SHELL` names rather than leaving you to translate one:

<!-- BEGIN GENERATED: example shellrc (tools/gen-doc-examples.sh) -->
```sh
agpin shellrc
```

```
Worth adding to ~/.zshrc (zsh, from $SHELL):

  eval "$(agpin guard)"           # refuse to run the agent unpinned
  eval "$(agpin completion zsh)"  # tab-complete commands and profile names
  PROMPT='$(agpin which --label 2>/dev/null) %~ %# '

Another shell: agpin shellrc --shell bash|zsh|fish, or --explain for all three.
```
<!-- END GENERATED: example shellrc -->

`agpin shellrc --shell bash|zsh|fish` prints another shell's form, and
`agpin shellrc --explain` prints all three with a line on what each does. The
installer prints the same block at the end of an install, by calling this
command, so there is one copy of it.

See [Refusing to run unpinned](USE.md#refusing-to-run-unpinned) and
[Completions](USE.md#completions) for what each line does.

It is idempotent and says which of "installed" and "already installed"
happened, and it warns when the prefix is not on your `PATH` rather than
leaving you with a command nothing can find:

<!-- BEGIN GENERATED: example install-again (tools/gen-doc-examples.sh) -->
```sh
curl -fsSL https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh | bash
```

```
Asking which release is newest...
Downloading agent-profile-0.11.0.tar.gz
Checksum matches SHA256SUMS for v0.11.0.
Signature verified: built by the release workflow, from tag v0.11.0.
Unpacked v0.11.0 into /Users/alex/.local/share/agent-profile/0.11.0

Already installed: /Users/alex/.local/bin/agpin
Already installed: /Users/alex/.local/bin/agent-profile

Nothing changed. That is what an install looks like on a second run;
it is not the same as one that never worked.
WARNING: /Users/alex/.local/bin is not on your PATH, so the command will not be found.
Add this to your shell rc file:
  export PATH="/Users/alex/.local/bin:$PATH"

Next:
  agpin help
  agpin doctor
  agpin version --check

Worth adding to ~/.zshrc (zsh, from $SHELL):

  eval "$(/Users/alex/.local/bin/agpin guard)"           # refuse to run the agent unpinned
  eval "$(/Users/alex/.local/bin/agpin completion zsh)"  # tab-complete commands and profile names
  PROMPT='$(/Users/alex/.local/bin/agpin which --label 2>/dev/null) %~ %# '

Another shell: agpin shellrc --shell bash|zsh|fish, or --explain for all three.
```
<!-- END GENERATED: example install-again -->

## What it needs

No dependencies beyond a stock macOS for the tool itself. It is one bash
script, written to bash 3.2 because that is what `/bin/bash` is on macOS, and
it uses `python3` from the Command Line Tools only to read JSON. No Homebrew,
no `jq`.

`python3` is the one prerequisite the tool cannot avoid. A Mac that has never
had Xcode or the Command Line Tools has none, and `agpin new`, `agpin list`,
`agpin doctor`, `agpin remove` and `agpin verify` all refuse without it,
naming `xcode-select --install`. That download is several gigabytes, so it is
worth doing before the first profile rather than in the middle of one.

Installing adds nothing to that: `curl`, `shasum` and `tar` are on every Mac,
and neither `tools/install.sh` nor `agpin version --check` calls `python3`,
because on a fresh Mac that opens the Command Line Tools dialog and an
installer is the worst place to meet it. `cosign` is the one optional piece,
and the only thing that goes unchecked without it is the signature.

## What you are trusting, step by step

The one-liner runs whatever `tools/install.sh` holds on `hovud` at the moment
you run it, so that one file is trusted on GitHub's word alone. Read it first
if you would rather not:

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/mmsge/agent-profile-manager/hovud/tools/install.sh
less install.sh
bash install.sh
```

Everything after that first file is checked rather than trusted.

**The tarball comes from a tag, not a branch.** A release is built by
`.github/workflows/release.yml`, which runs under the tag itself, runs the same
tests a branch runs, refuses to publish when the tag and the version in
`bin/agent-profile` disagree, and attaches the tarball, its `SHA256SUMS` and a
Sigstore bundle for each. It also runs the command below against those bundles,
with this exact identity, before it creates the release, so a release that
would fail the check you are about to read is not published at all.

**The checksum is verified before anything is unpacked.** A mismatch stops the
install and leaves nothing behind, so a truncated download or an altered
tarball cannot become a half-installed command.

**The signature is verified when `cosign` is installed.** The Sigstore
certificate names the workflow, the repository and the tag that produced the
file, so a release swapped by somebody who can push to this repository fails
the check rather than installing quietly. Keyless: there is no public key to
fetch and no private key anyone can steal.

**Without `cosign` the installer says so, loudly, and names what went
unchecked.** A checksum on its own proves the download is intact and nothing
more: whoever served `SHA256SUMS` served the tarball too, so changing both
passes. That warning is the difference between a verified install and one that
looks like one.

### Verifying by hand

If you want to see it work:

```sh
shasum -a 256 -c SHA256SUMS
cosign verify-blob \
    --bundle agent-profile-0.10.0.tar.gz.sigstore \
    --certificate-identity-regexp '^https://github\.com/mmsge/agent-profile-manager/\.github/workflows/release\.yml@refs/tags/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    agent-profile-0.10.0.tar.gz
```

Every release published so far needs one thing more. v0.8.0, v0.9.0 and v0.10.0
were all cut from the Actions tab before the workflow signed under the tag, so
their certificates name `refs/heads/hovud` where every verifier here expects
`refs/tags/`. Both bundles in each release, the tarball's and the
`SHA256SUMS`, carry that same identity. The signatures are valid, and only this
repository's release workflow running on its default branch could have made
them; what they name is the branch rather than the tag. To check those three,
say so explicitly:

```sh
AGENT_PROFILE_COSIGN_IDENTITY='^https://github\.com/mmsge/agent-profile-manager/\.github/workflows/release\.yml@refs/heads/hovud$' \
    tools/install.sh --version v0.10.0
```

The same variable works for `tools/update-homebrew-formula.sh`, and the same
string goes after `--certificate-identity-regexp` in the `cosign verify-blob`
command above. Nothing after v0.10.0 needs it: releases are built and signed
under the tag now, and the workflow verifies its own bundles against the
unoverridden identity before it publishes them.

## Homebrew

```sh
brew tap mmsge/agpin
brew install agpin
```

The formula pins one tarball's `sha256`, so Homebrew refuses anything that does
not match it. That moves the trust from a branch to the tap repository, which
is an improvement and not the end of it: whoever can push to the tap can change
the URL and the sum together. The Sigstore check is the one that survives that.
See [`packaging/homebrew/README.md`](../packaging/homebrew/README.md).

## Options

```sh
tools/install.sh --version v0.10.0   # a named release rather than the newest
tools/install.sh --prefix ~/bin     # where the two links go
tools/install.sh --name apx         # a different short command name
tools/install.sh --uninstall        # remove the links, and nothing else
tools/install.sh --dev              # link a git checkout instead
```

`--version` never asks the API which release is newest, so it is what you want
in anything scripted: pin the version and the machine stays on it.

`--uninstall` removes links that point at a release copy or at a checkout, and
leaves anything else of the same name alone. It does not delete the unpacked
releases, and it says where they are so you can:

<!-- BEGIN GENERATED: example install-uninstall (tools/gen-doc-examples.sh) -->
```sh
tools/install.sh --uninstall
```

```
Removed /Users/alex/.local/bin/agpin
Removed /Users/alex/.local/bin/agent-profile

The unpacked releases are still in /Users/alex/.local/share/agent-profile.
Remove them when you are done with them:  rm -rf /Users/alex/.local/share/agent-profile
```
<!-- END GENERATED: example install-uninstall -->

## Am I current?

<!-- BEGIN GENERATED: example version-check (tools/gen-doc-examples.sh) -->
```sh
agpin version --check
```

```
installed  0.11.0
latest     0.11.0

agpin is up to date.
```
<!-- END GENERATED: example version-check -->

Prints the version you are running and the newest release, and exits non-zero
when you are behind, so it works from a cron entry or a shell hook. It compares
the numbers field by field, because `0.10.0` is newer than `0.9.9` and a string
comparison says the opposite. When it is behind it prints the one-liner above
and exits 1.

It downloads that one answer and nothing else, and it installs nothing at all.
A tool that updates itself is a tool that can be made to run new code without
anybody deciding to, which is the thing this whole release process exists to
prevent. Without `--check`, `version` prints the version and the licence and
touches no network:

<!-- BEGIN GENERATED: example version (tools/gen-doc-examples.sh) -->
```sh
agpin version
```

```
agpin 0.11.0
GPL-3.0-or-later
```
<!-- END GENERATED: example version -->

## The development install

<!-- BEGIN GENERATED: example install-dev (tools/gen-doc-examples.sh) -->
```sh
tools/install.sh --dev
```

```
Installed /Users/alex/.local/bin/agpin -> /Users/alex/src/agent-profile/bin/agent-profile
Installed /Users/alex/.local/bin/agent-profile -> /Users/alex/src/agent-profile/bin/agent-profile

This is a development install. The command is a link into
/Users/alex/src/agent-profile, so it runs whatever that checkout holds,
and a git pull changes it under you.
Drop --dev for an install that only changes when you say so.

WARNING: /Users/alex/.local/bin is not on your PATH, so the command will not be found.
Add this to your shell rc file:
  export PATH="/Users/alex/.local/bin:$PATH"

Next:
  agpin help
  agpin doctor
  agpin version --check

Worth adding to ~/.zshrc (zsh, from $SHELL):

  eval "$(/Users/alex/.local/bin/agpin guard)"           # refuse to run the agent unpinned
  eval "$(/Users/alex/.local/bin/agpin completion zsh)"  # tab-complete commands and profile names
  PROMPT='$(/Users/alex/.local/bin/agpin which --label 2>/dev/null) %~ %# '

Another shell: agpin shellrc --shell bash|zsh|fish, or --explain for all three.
```
<!-- END GENERATED: example install-dev -->

This is the old behaviour, and it is still the right one when you are working
on the tool: it symlinks `~/.local/bin/agpin` straight at `bin/agent-profile`
in your checkout, so an edit takes effect with no install step.

**The installed command then runs whatever is in that checkout.** A `git pull`
changes it, and so does anyone who can push to this repository, and
`eval "$(agpin guard)"` in an rc file means that code runs at every shell
start. On a machine that holds customer data that is not a trade-off worth
making. The installer says as much when you use it, and refuses to combine
`--dev` with `--version`, because a development install has no version to pin.

## Windows

Nothing in this tool has been run on Windows. The tool is a bash script
written for macOS paths and macOS mechanisms (Keychain, `open`, AppleScript
applets); none of it runs on Windows, so a machine used from both platforms
gets no isolation from this tool at all on the Windows side.

What a port would rest on is written down all the same, as W01 to W06 in
[`docs/FACTS.md`](FACTS.md#windows), with the same statuses the macOS facts
carry and an honest one for each. Every entry there was read out of the
documentation or argued from it. None was observed on a Windows machine, so
none is `VERIFIED`.

```powershell
powershell -ExecutionPolicy Bypass -File tools\probe-claude-windows.ps1
```

The probe works in a throwaway config root and app data directory under
`$env:TEMP`, never touches a real root, never reads the content of a credential
file, and removes what it made. Run it in Windows PowerShell 5.1 or PowerShell
7 and paste the output into the Windows section of `docs/FACTS.md`. That
settles five of the six. W05 needs a person as well: pin the launcher the probe
leaves behind, launch from the pin, and say which root the session landed in.

The port itself, one cross-platform binary in Go, is
[issue #15](https://github.com/mmsge/agent-profile-manager/issues/15), and it depends on these facts being settled first.
W04 is the one that decides the shape of a port. It asks whether the desktop
app's embedded Claude Code reads the config root from the app's process
environment, which is F01 asked again for Windows. Until somebody answers it,
no Windows launcher should ship, because a launcher that pins nothing looks
exactly like one that works.
