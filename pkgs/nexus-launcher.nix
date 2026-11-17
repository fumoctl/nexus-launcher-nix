{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  makeDesktopItem,
  writeShellScriptBin,
  runtimeShell,

  # Also ship 32-bit libraries inside the FHS environment (x86_64 only).
  # The Nexus Runtime is a Proton fork that runs directly on the host, so
  # Wine and some games may need 32-bit libraries.
  enable32Bit ? true,

  # Extra packages to put in the FHS environment, e.g. `pkgs: [ pkgs.gamescope ]`.
  extraPkgs ? pkgs: [ ],
}:
let
  pname = "nexus-launcher";

  versions = builtins.fromJSON (builtins.readFile ../artifacts/versions.json);
  info = versions."Nexus Launcher";
  system = stdenv.hostPlatform.system;

  platformInfo = info.${system} or (throw "Unsupported system for Nexus Launcher: ${system}");

  inherit (info) version;

  src = fetchurl {
    inherit (platformInfo) url;
    sha256 = platformInfo.hash;
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };

  # Nexus Launcher runs `/usr/bin/steam` to send shortcuts to a running Steam
  # client. Inside the FHS sandbox /usr/bin only holds packages from this env,
  # so forward the call to the Steam found on the host PATH.
  steamShim = writeShellScriptBin "steam" ''
    self="$(readlink -f "$0")"
    IFS=:
    for dir in $PATH; do
      case "$dir" in
        "" | /bin | /sbin | /usr/bin | /usr/sbin) continue ;;
      esac
      if [ -x "$dir/steam" ] && [ "$(readlink -f "$dir/steam")" != "$self" ]; then
        exec "$dir/steam" "$@"
      fi
    done
    echo "steam: no Steam installation found on PATH" >&2
    exit 127
  '';

  desktopItem = makeDesktopItem {
    # Matches the desktop ID the launcher reports via app.setDesktopName(),
    # so Wayland compositors associate windows with this entry.
    name = "org.xodusgaming.nexus";
    exec = "nexus-launcher %U";
    icon = "nexus-launcher";
    desktopName = "Nexus Launcher";
    genericName = "Game Launcher";
    comment = "Xbox-inspired launcher for Microsoft Store PC games";
    categories = [ "Game" ];
    keywords = [
      "xbox"
      "microsoft"
      "store"
      "gamepass"
      "games"
    ];
    startupWMClass = "Nexus Launcher";
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  multiArch = enable32Bit;

  extraPkgs =
    pkgs:
    (with pkgs; [
      # Nexus backend (Rust binary downloaded at first start)
      openssl
      dbus
      stdenv.cc.cc.lib

      # Archive handling for backend / runtime downloads
      gnutar
      xz
      zstd
      gzip
      procps

      # Keyring / secret service integration (`busctl`, `/usr/bin/systemd-run`)
      systemd
      libsecret
      kdePackages.kconfig

      # Optional in-game overlay: Python 3, PyGObject, GTK 3 and WebKitGTK 4.1
      (python3.withPackages (ps: [ ps.pygobject3 ]))
      gobject-introspection
      gtk3
      webkitgtk_4_1
      libsoup_3
      gtk-layer-shell
      libnotify

      # Graphics for games started through the Nexus Runtime (vulkan-loader,
      # libGL, PipeWire and PulseAudio are already in the default AppImage env;
      # GPU drivers come from the host via /run/opengl-driver).
      libva

      steamShim
    ])
    ++ extraPkgs pkgs;

  # Let GObject introspection (overlay) find typelibs inside the FHS env.
  profile = ''
    export GI_TYPELIB_PATH=/usr/lib/girepository-1.0''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}
  '';

  extraInstallCommands = ''
    # Upstream reads $APPIMAGE to get a persistent executable path for game
    # shortcuts, "Add to Steam" and the overlay desktop entry. Point it at the
    # path the launcher was started from (e.g. /run/current-system/sw/bin/nexus-launcher).
    # In-app self-updates stay disabled because this is not a writable .AppImage.
    mkdir -p $out/libexec/${pname}
    mv $out/bin/${pname} $out/libexec/${pname}/${pname}-fhs
    cat > $out/bin/${pname} <<EOF
    #!${runtimeShell}
    self="\$0"
    case "\$self" in
      */*) ;;
      *) self="\$(command -v -- "\$self" 2>/dev/null || true)" ;;
    esac
    case "\$self" in
      /*) ;;
      ?*) self="\$PWD/\$self" ;;
    esac
    if [ -n "\$self" ] && [ -x "\$self" ]; then
      export APPIMAGE="\$self" ARGV0="\$self"
    fi
    # Leaked from Electron-based editors' terminals; it would start a Node REPL.
    unset ELECTRON_RUN_AS_NODE
    exec "$out/libexec/${pname}/${pname}-fhs" "\$@"
    EOF
    chmod +x $out/bin/${pname}

    # Icons from the extracted AppImage
    for icon in ${appimageContents}/usr/share/icons/hicolor/*/apps/*.png; do
      size="$(basename "$(dirname "$(dirname "$icon")")")"
      install -Dm644 "$icon" "$out/share/icons/hicolor/$size/apps/${pname}.png"
    done

    # Fallback pixmap icon
    if [ -f ${appimageContents}/.DirIcon ]; then
      install -Dm644 ${appimageContents}/.DirIcon $out/share/pixmaps/${pname}.png
    fi

    # Desktop entry
    install -Dm644 -t $out/share/applications ${desktopItem}/share/applications/*.desktop
  '';

  passthru = {
    inherit appimageContents;
  };

  meta = {
    description = "Open-source Xbox-inspired desktop launcher for Microsoft Store games on Linux";
    homepage = "https://github.com/domsvoboda/nexus-launcher";
    changelog = "https://github.com/domsvoboda/nexus-launcher/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = pname;
  };
}
