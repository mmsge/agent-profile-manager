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
  url "https://github.com/mmsge/agent-profile-manager/releases/download/v0.8.0/agent-profile-0.8.0.tar.gz"
  version "0.8.0"

  # From the v0.8.0 release's own SHA256SUMS, and checked three ways before it
  # was written here: against the tarball downloaded from the release, against
  # the digest GitHub reports for that asset, and against a tarball rebuilt
  # from the v0.8.0 tag on a different machine, which reproduced this sum
  # exactly. Replace it on every release, from that release's SHA256SUMS.
  sha256 "96e7121202621c586f9e92ec14d2928d5b6758c537789fb8eb4d23dca6258831"

  # Homebrew audits for this, and it must match the LICENSE file at the
  # repository root.
  license "GPL-3.0-or-later"

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
