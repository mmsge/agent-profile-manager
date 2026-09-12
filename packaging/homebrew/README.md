# The Homebrew tap

`agpin.rb` in this directory is the formula. Homebrew cannot install from here
directly, because a tap is a repository of its own with a name Homebrew
recognises. This file says how to make that repository, and what to do to it on
every release.

The formula is kept here rather than only in the tap so that it is reviewed in
the same pull request as the code it installs, and so a release that changes
what gets installed cannot forget to change the formula.

## Why a tap at all

The one-liner install trusts `tools/install.sh` as it stands on `hovud` at the
moment you run it. The tap moves that trust: Homebrew reads a formula that
names one tarball and pins its `sha256`, and it refuses to unpack anything that
does not match. A release swapped after the formula was written fails the check
instead of installing quietly.

That is a real improvement and it is not the whole story. Whoever can push to
the tap repository can change the URL and the sum together, so the tap is only
as trustworthy as its write access. `cosign verify-blob` against the Sigstore
bundle is the check that survives that, and it is what `tools/install.sh` does
when `cosign` is installed.

## Creating the tap, once

Homebrew resolves `brew tap mmsge/agpin` to the repository
`github.com/mmsge/homebrew-agpin`. The `homebrew-` prefix is required and the
part after it is the tap name.

```sh
gh repo create mmsge/homebrew-agpin --public \
    --description "Homebrew tap for agpin, the agent profile manager"
git clone https://github.com/mmsge/homebrew-agpin
cd homebrew-agpin
mkdir -p Formula
cp ../agent-profile-manager/packaging/homebrew/agpin.rb Formula/agpin.rb
git add Formula/agpin.rb
git commit -m "Add the agpin formula"
git push
```

The formula must be at `Formula/agpin.rb`. Homebrew looks there and nowhere
else, and the file name is what `brew install agpin` matches on.

Then, from any Mac:

```sh
brew tap mmsge/agpin
brew install agpin
brew test agpin
```

## Updating the formula on each release

Half of this happens on its own now, and it is the mechanical half.

Publishing a release runs `.github/workflows/homebrew-formula.yml`. It reads
the row for `agent-profile-<version>.tar.gz` out of the release's own
`SHA256SUMS`, matching the file name exactly; downloads the tarball from that
same release and hashes it; checks the Sigstore signature on both; and then
opens a pull request setting `url`, `version` and `sha256` in this directory's
`agpin.rb` together. A missing row, a sum of the wrong length or a sum the
tarball does not have fails the job rather than writing a formula nobody can
install from.

A pull request, and never a push to `hovud`. The pin is worth having because
somebody looked at the release before the tap trusted it, and a workflow that
rewrote the default branch would take away exactly that. What is automated is
reading one number out of a file and typing it without making a mistake.

So these are still yours, in this order:

1. Read the pull request. Its body names the release, the tarball and the sum,
   so it can be checked against the release page without leaving the diff.
2. Rebuild the tarball from the tag, ideally on another machine, and confirm
   the sum reproduces. The workflow proves the release is intact and signed; a
   rebuild proves it is the tree the tag names. v0.8.0 and v0.9.0 were each
   checked this way before their sums were written.
3. Merge it.
4. Copy the merged formula to the tap, below. Nothing automatic goes near that
   repository.

The pull request does not start CI by itself. GitHub runs no workflow for a
push or a pull request that a `GITHUB_TOKEN` made, so the formula workflow
asks `ci.yml` to run on the branch through `workflow_dispatch`, which is the
documented exception to that rule. If the checks are missing anyway, close and
reopen the pull request.

The workflow also needs **Settings > Actions > General > Allow GitHub Actions
to create and approve pull requests** to be on. Without it the branch is still
pushed and the job says so; open the pull request from that branch by hand.

### By hand, when you need to

The workflow runs one script, and it is the same script from a checkout:

```sh
tools/update-homebrew-formula.sh 0.9.0
```

It makes the same checks and writes the same three fields. It does not commit,
does not push, and knows nothing about the tap. Use it when the release was
published somewhere the workflow did not see, or when the run failed and you
would rather not wait for another one.

Or just the number, to check one by eye:

```sh
tools/update-homebrew-formula.sh 0.9.0 --sum-only
```

Either way the formula cannot be updated before the release, because until it
exists there is no sum to pin.

### Copying it to the tap

The tap's copy is a deliberate act, so it is a hand-made commit:

```sh
cd ../homebrew-agpin
cp ../agent-profile-manager/packaging/homebrew/agpin.rb Formula/agpin.rb
git commit -am "agpin 0.9.0"
git push
```

Check it before anyone else does:

```sh
brew uninstall agpin
brew untap mmsge/agpin
brew tap mmsge/agpin
brew install agpin
brew test agpin
agpin version    # must print the version the formula names
```

## What the formula installs

`bin/`, `tools/`, `docs/` and `README.md` go into the keg's `libexec`, and two
symlinks, `agpin` and `agent-profile`, go on the `PATH`. Both point at the same
script.

Symlinks rather than two copies, because the tool names itself by whichever
name it was invoked as. Installed as copies it would still work, but a message
telling the reader to run `agent-profile doctor` when they typed `agpin` is
exactly the failure the self-naming exists to prevent, so the test block
asserts it.

## What is deliberately not here

No `bottle` block. A bottle is a prebuilt binary, and this is a shell script
with nothing to build, so Homebrew installs the tarball as it comes.

No autobump, no `livecheck` that installs. The formula is updated by a person
who has looked at the release, which is the same reason `agpin version --check`
reports and never updates.

A workflow that opens a pull request is not an autobump, and the difference is
the whole point. It reads the release and writes a diff; the formula changes
when somebody merges that diff, and the tap changes when somebody copies it.
Both decisions stay where they were.
