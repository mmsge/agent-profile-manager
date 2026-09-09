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

The release workflow publishes `SHA256SUMS` beside the tarball, so the sum is
read rather than computed by hand.

```sh
version=0.9.0
base=https://github.com/mmsge/agent-profile-manager/releases/download/v$version
sum=$(curl -fsSL "$base/SHA256SUMS" | awk '$2 == "agent-profile-'"$version"'.tar.gz" { print $1 }')
echo "$sum"
```

Then edit both copies, this one and the tap's, so they do not drift:

- `url` to the new tarball
- `version` to the new version
- `sha256` to `$sum`

Commit the change here in the same pull request as the version bump, and push
the copy to the tap once the release exists. The formula cannot be updated
before the release, because the sum does not exist yet.

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
