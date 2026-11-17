# Nexus Launcher Nix Flake Developer & Agent Guide

This repository contains a Nix flake that packages the [Nexus Launcher](https://github.com/domsvoboda/nexus-launcher) AppImage. This guide gives human developers and AI coding agents the context needed to maintain, test, update, or modify the package.

## Repository Layout

*   **[flake.nix](flake.nix)**: Entry point defining inputs, outputs (`packages`, `apps`, `devShells`, `formatter`) and the overlay.
*   **[pkgs/nexus-launcher.nix](pkgs/nexus-launcher.nix)**: Package definition for the AppImage.
*   **[artifacts/versions.json](artifacts/versions.json)**: Lock file storing the current version plus the URL and SHA-256 hash of the AppImage for each supported platform.
*   **[scripts/lib.sh](scripts/lib.sh)**: Shared helpers (release discovery, asset names, platform map).
*   **[scripts/check-version.sh](scripts/check-version.sh)**: Compares the locked version with the latest upstream release.
*   **[scripts/update-version.sh](scripts/update-version.sh)**: Updates `versions.json` to the latest release (pass `--force` to re-fetch the current one).

---

## Binary Fetching & Version Locking

The flake never fetches anything unpinned at build time:
1. **Metadata Store**: The version, URLs and hashes are locked in `artifacts/versions.json`:
   ```json
   { "Nexus Launcher": { "version": "0.5.0", "x86_64-linux": { "url": "...", "hash": "..." } } }
   ```
2. **Evaluation**: The derivation reads the lock file with `builtins.readFile`/`builtins.fromJSON` and selects the entry for `stdenv.hostPlatform.system`. A platform missing from the file throws an "Unsupported system" error.
3. **Fetch Phase**: The AppImage is downloaded with `fetchurl` using the pinned hash (nix32 SHA-256 from `nix-prefetch-url`).
4. **Upstream Source**: AppImages come from the GitHub releases of [domsvoboda/nexus-launcher](https://github.com/domsvoboda/nexus-launcher/releases).

### Upstream release quirks
*   The upstream repository publishes **two kinds of releases**: launcher releases tagged `vX.Y.Z`, and backend releases tagged `backend-vX.Y.Z`. `releases/latest` can therefore point at a backend release. `scripts/lib.sh` lists releases and keeps only non-draft, non-prerelease `vX.Y.Z` tags.
*   AppImage assets are being renamed from `Xodus-Nexus-<version>-<arch>.AppImage` to `Nexus-Launcher-<version>-<arch>.AppImage`. The update script accepts both and prefers the new name. The arch suffixes are `x86_64` and `arm64`.
*   Not every release ships an ARM64 AppImage. When one is missing, the update script omits `aarch64-linux` from `versions.json` (with a warning) instead of failing. A release without an x86_64 AppImage is rejected.
*   Each AppImage has a `.sha512sum` sidecar. The update script checks the downloaded file against it before writing the new hash.

---

## Critical Packaging Notes

### 1. FHS environment (`buildFHSEnv`, not `wrapType2`)
At runtime the launcher downloads and runs a **Nexus backend** binary and **Nexus Runtime** families (a Proton fork) into the user's home directory. All of these run inside the bubblewrap FHS environment, so their library needs must be met by the environment.

The package calls `buildFHSEnv` directly, with `appimageTools.defaultFhsEnvArgs` and `appimageTools.appimage-exec` (the same pieces `wrapType2` uses). **Do not switch back to `appimageTools.wrapType2`/`wrapAppImage`.** They merge their default `multiPkgs` *over* the caller's, which silently drops the Wine libraries.

*   **Wine/Proton libraries (`multiPkgs`, 64- and 32-bit)**: Proton normally gets these from the Steam Runtime. Wine `dlopen()`s `gnutls`, `libgcrypt`, `krb5`, `pcsclite`, `libv4l` and `unixodbc`. Without gnutls, `bcrypt` has no crypto support and Nexus package registration fails (`hr=80004005`, exit code 70). Libraries bundled with the runtime (GStreamer, libsoup, vosk) also need `libva`, `nghttp2`, `libpsl`, `sqlite`, `libopus`, `blas` and `lapack`.
*   Wrap `multiPkgs` entries in **`lib.getLib`**. For multi-output packages, `buildFHSEnv` only links `meta.outputsToInstall` (often `bin`/`man`), so the shared libraries would otherwise be missing from `/usr/lib*`.
*   The backend needs OpenSSL 3, `libdbus-1`, and the GCC runtime (`libstdc++`, `libgcc_s`).
*   Keyring handling calls `busctl`, `/usr/bin/systemd-run` and `kreadconfig`, so `systemd` and `kdePackages.kconfig` are included.
*   Runtime archives are unpacked with `tar`/`xz`, and partly with `python3`.
*   The optional overlay runs `/usr/bin/python3` with PyGObject, GTK 3, WebKitGTK 4.1 (+ libsoup 3) and gtk-layer-shell. `GI_TYPELIB_PATH` is set in the FHS `profile` so GObject introspection finds the typelibs under `/usr/lib/girepository-1.0`.
*   `multiArch` (argument `enable32Bit`, default `true`) adds 32-bit versions of `multiPkgs` on x86_64 for Wine/Proton.
*   GPU drivers come from the host (`/run/opengl-driver`). **Do not** add `mesa` to the environment.
*   To check a newly installed runtime for missing libraries, run commands inside the env with `APPIMAGE_DEBUG_EXEC=/path/to/script nexus-launcher`. Run `ldd` on `~/.local/share/xodus-nexus/runtimes/variants/*/releases/*/files/lib/wine/{x86_64,i386}-unix/*.so`. Also compare the `lib*.so*` strings in those files (which Wine `dlopen()`s) against `/usr/lib64` and `/usr/lib32`.

### 2. Launcher wrapper (`$APPIMAGE`)
Upstream reads `$APPIMAGE` for two things:
*   **Self-updates** (`LauncherUpdater`). These need a user-owned, writable `*.AppImage`. A Nix store path never qualifies, so in-app updates stay disabled.
*   **A persistent executable path** for game shortcuts, "Add to Steam" and the overlay desktop entry (`shortcutLauncherPath`). Without it these features are unavailable.

`extraInstallCommands` moves the FHS entry script to `libexec/nexus-launcher/nexus-launcher-fhs` and installs a small `bin/nexus-launcher` wrapper. The wrapper sets `APPIMAGE`/`ARGV0` to the absolute path it was started from (for example `/run/current-system/sw/bin/nexus-launcher`), which stays valid across upgrades.

### 3. `/usr/bin/steam` shim
The launcher runs `/usr/bin/steam steam://addnonsteamgame/...` to hand shortcuts to a running Steam client. Inside the FHS environment `/usr/bin` only contains env packages, so a `steam` shim is included. It forwards to the first other `steam` found on the host `PATH`.

### 4. Desktop integration
*   The desktop file is named `org.xodusgaming.nexus.desktop` to match the launcher's `app.setDesktopName()` (Wayland app ID). `StartupWMClass=Nexus Launcher` matches the X11 class Electron derives from `productName` (same as the desktop file shipped inside the AppImage).
*   Icons are copied from the `appimageTools.extract` output into `share/icons/hicolor/<size>/apps/nexus-launcher.png`.

---

## Update and Maintenance Workflows

### Automated CI/CD & Updates (GitHub Actions)
* **`.github/workflows/update.yml`**: Runs daily at 07:00 UTC and on manual dispatch. Runs `update-version.sh`, verifies the build (`nix flake check` & `nix build`) and opens a PR with auto-merge enabled.
* **`.github/workflows/ci.yml`**: Runs flake checks and builds on pushes and pull requests to `main`.
* **`.github/workflows/release.yml`**: Creates a `vX.Y.Z` tag and GitHub release when `versions.json` changes on `main`.
* **`.github/workflows/cleanup-branches.yml`**: Deletes merged `auto-update/*` branches.

```bash
gh workflow run update.yml
```

### Local commands
```bash
# Check for a newer upstream release
./scripts/check-version.sh

# Update artifacts/versions.json to the newest release
./scripts/update-version.sh

# Build & check
nix build .#nexus-launcher
nix flake check

# Inspect the extracted AppImage contents
nix build .#nexus-launcher.appimageContents
```
*(Note: Nix ignores untracked files in git repositories. Run `git add` on new or modified files before running Nix commands.)*
