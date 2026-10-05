class NudoxPreview < Formula
  desc "Local-first versioned code intelligence checkpoint"
  homepage "https://nudox.org"
  url "https://github.com/nudoxorg/Backend/releases/download/checkpoint-20261005-9d29d53046/Nudox-preview-arm64.tar.gz?sha256=09ba4990d2b0bf45d95d341d2ddd546ffe63224bbfa609715ce7dfe9212ed34b"
  version "2026.10.05.9d29d53046"
  sha256 "09ba4990d2b0bf45d95d341d2ddd546ffe63224bbfa609715ce7dfe9212ed34b"
  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    if (buildpath/"Nudox.app").directory?
      libexec.install "Nudox.app"
    elsif (buildpath/"Contents/Info.plist").file?
      (libexec/"Nudox.app").mkpath
      (libexec/"Nudox.app").install "Contents"
    else
      odie "The checkpoint archive does not contain the expected app bundle"
    end
    %w[backend-cli backend-mcp backend-locald].zip(%w[nudox nudox-mcp nudox-locald]).each do |binary, command|
      bin.install_symlink libexec/"Nudox.app/Contents/MacOS/#{binary}" => command
    end
    (bin/"nudox-gui").write <<~EOS
      #!/bin/sh
      exec /usr/bin/open -a "#{libexec}/Nudox.app" "$@"
    EOS
    (bin/"nudox-gui").chmod 0755
  end

  def caveats
    <<~EOS
      This checkpoint is ad-hoc signed and is not notarized or a final investor release.
      Run nudox-gui to open the GUI; use nudox --help for CLI commands.
      Configure your MCP client with #{bin}/nudox-mcp.
      Language indexing requires the appropriate installed compiler/toolchain.
    EOS
  end

  test do
    assert_match "local-first", shell_output("#{bin}/nudox --help")
    assert_match "backend-mcp", shell_output("#{bin}/nudox-mcp --help")
    assert_match "backend-locald", shell_output("#{bin}/nudox-locald --help")
  end
end
