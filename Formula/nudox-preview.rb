require "tmpdir"

class NudoxPreview < Formula
  desc "Local-first versioned code intelligence checkpoint"
  homepage "https://nudox.org"
  url "https://github.com/nudoxorg/Backend/releases/download/checkpoint-20261005-9d29d53046/Nudox-preview-arm64.tar.gz?sha256=09ba4990d2b0bf45d95d341d2ddd546ffe63224bbfa609715ce7dfe9212ed34b"
  version "2026.10.05.9d29d53046"
  sha256 "09ba4990d2b0bf45d95d341d2ddd546ffe63224bbfa609715ce7dfe9212ed34b"
  revision 1
  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    libexec.mkpath
    archive = libexec/"Nudox.app.zip"
    source_bundle = buildpath/"Nudox.app"
    source_contents = buildpath/"Contents"
    source_root = nil

    odie "refusing to overwrite an unexpected archive path at #{archive}" if archive.exist? || archive.symlink?

    source_root = Pathname.new(Dir.mktmpdir("nudox-preview-source.", libexec.to_s))
    source_app = source_root/"Nudox.app"

    begin
      if source_bundle.symlink?
        odie "the checkpoint archive contains a symlink where Nudox.app should be"
      elsif source_bundle.directory?
        system "/usr/bin/ditto", source_bundle.to_s, source_app.to_s
      elsif source_contents.symlink?
        odie "the checkpoint archive contains a symlink where Contents should be"
      elsif source_contents.directory? && (source_contents/"Info.plist").file? && !(source_contents/"Info.plist").symlink?
        source_app.mkpath
        system "/usr/bin/ditto", source_contents.to_s, (source_app/"Contents").to_s
      else
        odie "the checkpoint archive does not contain Nudox.app or a Homebrew-stripped Contents directory"
      end

      odie "the reconstructed app bundle is incomplete" unless
        source_app.directory? && !source_app.symlink? &&
        (source_app/"Contents/Info.plist").file? && !(source_app/"Contents/Info.plist").symlink?

      system "/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", source_app.to_s, archive.to_s
    ensure
      rm_rf source_root if source_root && source_root.directory? && !source_root.symlink?
    end

    bin.mkpath
    helper = libexec/"nudox-preview-postinstall"
    helper.write <<~'NUDOX_POSTINSTALL'
    #!/bin/sh
    set -eu

    SELF_DIR=$(CDPATH= cd -P "$(/usr/bin/dirname "$0")" && /bin/pwd -P) || {
      printf '%s\n' 'nudox-preview-postinstall: cannot determine its libexec directory' >&2
      exit 1
    }
    APP="$SELF_DIR/Nudox.app"
    ARCHIVE="$SELF_DIR/Nudox.app.zip"
    STAGE=
    STAGED_APP=
    STAGE_OWNED=0
    PREVIOUS_MOVED=0
    PUBLISH_STARTED=0
    STAGED_ID=
    PUBLISHED=0
    PRESERVE_STAGE=0

    path_exists() {
      [ -e "$1" ] || [ -L "$1" ]
    }

    fail() {
      printf 'nudox-preview-postinstall: %s\n' "$*" >&2
      exit 1
    }

    cleanup() {
      status=$?
      trap - 0 HUP INT TERM
      set +e
      recovery_failed=0

      if [ "$status" -ne 0 ] && [ "$PUBLISHED" -ne 1 ]; then
        new_app_moved=0
        if [ "$PUBLISH_STARTED" -eq 1 ] && [ -n "$STAGED_ID" ] &&
          [ -d "$APP" ] && [ ! -L "$APP" ]; then
          current_app_id=$(/usr/bin/stat -f '%d:%i' "$APP" 2>/dev/null) || current_app_id=
          if [ "$current_app_id" = "$STAGED_ID" ]; then
            new_app_moved=1
          fi
        fi
        if [ "$new_app_moved" -eq 1 ]; then
          if [ -L "$APP" ]; then
            printf 'nudox-preview-postinstall: cannot safely remove replacement symlink at %s\n' "$APP" >&2
            recovery_failed=1
          elif [ -d "$APP" ]; then
            if ! /bin/rm -rf "$APP"; then
              printf 'nudox-preview-postinstall: cannot remove failed replacement at %s\n' "$APP" >&2
              recovery_failed=1
            fi
          elif path_exists "$APP"; then
            printf 'nudox-preview-postinstall: cannot safely remove non-directory replacement at %s\n' "$APP" >&2
            recovery_failed=1
          fi
        fi

        previous_moved=$PREVIOUS_MOVED
        if [ "$previous_moved" -ne 1 ] && [ -n "$STAGE" ] &&
          [ -d "$STAGE/previous-app" ] && [ ! -L "$STAGE/previous-app" ]; then
          previous_moved=1
        fi
        if [ "$previous_moved" -eq 1 ]; then
          if [ "$recovery_failed" -eq 0 ] &&
            [ -d "$STAGE/previous-app" ] && [ ! -L "$STAGE/previous-app" ] &&
            [ ! -e "$APP" ] && [ ! -L "$APP" ]; then
            if /bin/mv "$STAGE/previous-app" "$APP"; then
              PREVIOUS_MOVED=0
            else
              printf 'nudox-preview-postinstall: failed to restore previous app; keeping recovery data in %s\n' "$STAGE" >&2
              recovery_failed=1
            fi
          else
            printf 'nudox-preview-postinstall: previous app could not be restored safely; keeping recovery data in %s\n' "$STAGE" >&2
            recovery_failed=1
          fi
        fi
      fi

      if [ "$recovery_failed" -eq 1 ]; then
        PRESERVE_STAGE=1
      fi

      if [ "$STAGE_OWNED" -eq 1 ] && [ "$PRESERVE_STAGE" -eq 0 ]; then
        case "$STAGE" in
          "$SELF_DIR"/nudox-preview-stage.*)
            if [ -d "$STAGE" ] && [ ! -L "$STAGE" ]; then
              if ! /bin/rm -rf "$STAGE"; then
                printf 'nudox-preview-postinstall: could not remove owned staging directory %s\n' "$STAGE" >&2
              fi
            else
              printf 'nudox-preview-postinstall: staging path changed; leaving it untouched at %s\n' "$STAGE" >&2
            fi
            ;;
          *)
            printf 'nudox-preview-postinstall: staging path is outside the owned pattern; leaving it untouched at %s\n' "$STAGE" >&2
            ;;
        esac
      fi

      exit "$status"
    }

    trap cleanup 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if [ -L "$APP" ]; then
      fail "refusing symlink app path: $APP"
    fi
    if path_exists "$APP" && [ ! -d "$APP" ]; then
      fail "app path exists but is not a real directory: $APP"
    fi
    if [ -L "$ARCHIVE" ]; then
      fail "refusing symlink archive path: $ARCHIVE"
    fi
    if path_exists "$ARCHIVE" && [ ! -f "$ARCHIVE" ]; then
      fail "archive path exists but is not a regular file: $ARCHIVE"
    fi

    if ! path_exists "$ARCHIVE"; then
      [ -d "$APP" ] || fail "no app bundle or staged archive exists in $SELF_DIR"
      /usr/bin/codesign --verify --deep --strict "$APP" || fail "existing app bundle failed strict code-signature verification: $APP"
      printf '%s\n' 'nudox-preview-postinstall: existing app passed strict code-signature verification'
      exit 0
    fi

    STAGE=$(/usr/bin/mktemp -d "$SELF_DIR/nudox-preview-stage.XXXXXX") || fail "could not create a unique staging directory under $SELF_DIR"
    case "$STAGE" in
      "$SELF_DIR"/nudox-preview-stage.*) STAGE_OWNED=1 ;;
      *) fail "mktemp returned a staging path outside libexec: $STAGE" ;;
    esac
    [ -d "$STAGE" ] && [ ! -L "$STAGE" ] || fail "mktemp did not create a real staging directory: $STAGE"

    /usr/bin/ditto -x -k "$ARCHIVE" "$STAGE" || fail "could not extract the staged app archive"
    STAGED_APP="$STAGE/Nudox.app"
    [ ! -L "$STAGED_APP" ] || fail "archive produced a symlink app bundle"
    [ -d "$STAGED_APP" ] || fail "archive did not contain a real Nudox.app directory"
    /usr/bin/codesign --verify --deep --strict "$STAGED_APP" || fail "staged app failed strict code-signature verification"
    STAGED_ID=$(/usr/bin/stat -f '%d:%i' "$STAGED_APP") || fail "could not identify the verified staged app"
    [ -n "$STAGED_ID" ] || fail "could not identify the verified staged app"

    if path_exists "$APP"; then
      [ -d "$APP" ] && [ ! -L "$APP" ] || fail "refusing to replace a non-directory app path: $APP"
      [ ! -e "$STAGE/previous-app" ] && [ ! -L "$STAGE/previous-app" ] || fail "staging backup path unexpectedly exists"
      /bin/mv "$APP" "$STAGE/previous-app" || fail "could not move existing app into its owned staging backup"
      PREVIOUS_MOVED=1
    fi

    PUBLISH_STARTED=1
    /bin/mv "$STAGED_APP" "$APP" || fail "could not atomically publish the verified app bundle"
    PUBLISHED_APP_ID=$(/usr/bin/stat -f '%d:%i' "$APP") || fail "could not identify the published app"
    [ "$PUBLISHED_APP_ID" = "$STAGED_ID" ] || fail "published app path no longer identifies the verified staged bundle"
    /usr/bin/codesign --verify --deep --strict "$APP" || fail "published app failed strict code-signature verification"
    PUBLISHED=1

    [ ! -L "$ARCHIVE" ] || fail "archive path changed to a symlink after publication; leaving it untouched"
    [ -f "$ARCHIVE" ] || fail "archive path changed after publication; leaving it untouched"
    /bin/rm -f "$ARCHIVE" || fail "app was published and verified, but its staged archive could not be removed"
    printf '%s\n' 'nudox-preview-postinstall: verified app published successfully'
    NUDOX_POSTINSTALL
    helper.chmod 0555

    {
      "nudox" => "backend-cli",
      "nudox-mcp" => "backend-mcp",
      "nudox-locald" => "backend-locald",
    }.each do |command, binary|
      shim = bin/command
      shim.write <<~EOS
        #!/bin/sh
        exec "#{libexec}/Nudox.app/Contents/MacOS/#{binary}" "$@"
      EOS
      shim.chmod 0755
    end

    gui = bin/"nudox-gui"
    gui.write <<~EOS
      #!/bin/sh
      exec /usr/bin/open -a "#{libexec}/Nudox.app" "$@"
    EOS
    gui.chmod 0755
  end

  post_install_steps do
    run "nudox-preview-postinstall", base: :libexec
  end

  def caveats
    <<~EOS
      This is an ad-hoc signed, non-notarized preview checkpoint, not a final release.
      It requires an Apple Silicon Mac running macOS 14 or later.
      Run nudox-gui to open the GUI; use nudox --help for CLI commands.
      Configure your MCP client with #{bin}/nudox-mcp.
      Language indexing still requires the appropriate native compiler/toolchain.
    EOS
  end

  test do
    assert_match "local-first", shell_output("#{bin}/nudox --help")
    assert_match "backend-mcp", shell_output("#{bin}/nudox-mcp --help")
    assert_match "backend-locald", shell_output("#{bin}/nudox-locald --help")
  end
end
