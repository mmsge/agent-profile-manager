# Homebrew formula for agent-profile, installed as both agpin and
# agent-profile.
#
# This file is the source of truth. The tap repository holds a copy at
# Formula/agpin.rb, and packaging/homebrew/README.md says how to get it there
# and how to update it on each release.
#
# Homebrew verifies the sha256 below before it unpacks anything, so a tarball
# that was swapped after the formula was written fails rather than installs.
# That is the whole reason this file pins a sum instead of following the
# latest release.
class Agpin < Formula
  desc "Keep several AI agent accounts apart on one Mac, and audit that they stay apart"
  homepage "https://github.com/mmsge/agent-profile-manager"
  url "https://github.com/mmsge/agent-profile-manager/releases/download/v0.7.1/agent-profile-0.7.1.tar.gz"
  version "0.7.1"

  # PLACEHOLDER. Replace with the sum from the release's SHA256SUMS the first
  # time this formula points at a real release, and on every release after
  # that. Sixty-four zeros is not a sum anything can produce, so a formula that
  # still carries it fails loudly rather than installing something unchecked.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  # No license line yet: the repository ships no LICENSE file. Add one here
  # once it does, because Homebrew audits for it.

  # macOS only, deliberately. The tool pins the desktop app through open(1)
  # --env and reads the macOS Keychain, and neither exists elsewhere.
  depends_on :macos

  def install
    # The whole tree, so verify, doctor and the probe script can find the
    # documents they refer to. Only the two commands land on the PATH.
    libexec.install "bin", "tools", "docs", "README.md"

    # Symlinks rather than copies, because the tool names itself by the name it
    # was invoked as. Installed this way, "agpin doctor" says agpin in every
    # message and every suggested fix.
    bin.install_symlink libexec/"bin/agent-profile" => "agent-profile"
    bin.install_symlink libexec/"bin/agent-profile" => "agpin"
  end

  def caveats
    <<~EOS
      Two lines worth adding to your shell rc file:

        eval "$(agpin guard)"
        PROMPT='$(agpin which --label 2>/dev/null) %~ %# '

      The first refuses to run the agent unpinned. The second shows which
      profile the shell is pinned to.

      Then check the machine:

        agpin doctor
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/agpin version")
    # The self-naming property is the one thing a packaging mistake breaks
    # quietly, so assert it rather than trust it.
    assert_match "agpin <command>", shell_output("#{bin}/agpin help")
  end
end
