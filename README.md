# nexus-launcher-nix

A Nix flake packaging [Nexus Launcher](https://github.com/domsvoboda/nexus-launcher) — an open-source, Xbox-inspired launcher for Microsoft Store PC games on Linux — for NixOS and other Linux systems, built from the official upstream AppImages.

Supports `x86_64-linux` and `aarch64-linux` (upstream ARM64 builds are experimental), with automated daily updates via GitHub Actions.

> [!CAUTION]
> Nexus Launcher is an independent, unofficial project built on Xodus. This flake is an unofficial package of it. Report packaging problems here and launcher problems [upstream](https://github.com/domsvoboda/nexus-launcher/issues).

---

## Quick Start

Try it without installing it:

```bash
nix run github:fumoctl/nexus-launcher-nix
```

---

## Installation

### 1. NixOS Configuration

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nexus-launcher-nix = {
      url = "github:fumoctl/nexus-launcher-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nexus-launcher-nix, ... }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux"; # Or "aarch64-linux"
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            nexus-launcher-nix.packages.${pkgs.stdenv.hostPlatform.system}.nexus-launcher
          ];

          # Games run through the Nexus Runtime (a Proton fork) and need GPU drivers.
          hardware.graphics = {
            enable = true;
            enable32Bit = true;
          };
        })
      ];
    };
  };
}
```

### 2. Home Manager Configuration

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nexus-launcher-nix = {
      url = "github:fumoctl/nexus-launcher-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nexus-launcher-nix, ... }: {
    homeConfigurations.your-user = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        ({ pkgs, ... }: {
          home.packages = [
            nexus-launcher-nix.packages.${pkgs.stdenv.hostPlatform.system}.nexus-launcher
          ];
        })
      ];
    };
  };
}
```

### 3. Overlay Integration

```nix
{
  nixpkgs.overlays = [
    inputs.nexus-launcher-nix.overlays.default
  ];

  environment.systemPackages = with pkgs; [
    nexus-launcher
  ];
}
```

### Customization

The package accepts a few overridable arguments:

```nix
nexus-launcher.override {
  # Drop the 32-bit libraries from the FHS environment (x86_64 only; default: true)
  enable32Bit = false;
  # Add extra packages to the FHS environment the launcher and its games run in
  extraPkgs = pkgs: [ pkgs.gamescope pkgs.mangohud ];
}
```

---

## NixOS Notes

- **Sandbox**: The AppImage runs inside a `bubblewrap` FHS environment (`buildFHSEnv`, like `appimageTools.wrapType2`). Everything the launcher downloads at runtime — the Nexus backend and the Nexus Runtime families — runs inside that same environment, which provides glibc ≥ 2.38, OpenSSL 3, D-Bus, GCC runtime libraries, the usual AppImage libraries, and the 64- and 32-bit libraries Wine loads (gnutls, krb5, pcsclite, …) that Proton normally gets from the Steam Runtime.
- **Keyring**: Sign-in credentials are stored through the Secret Service D-Bus API. Make sure a provider is running, e.g. `services.gnome.gnome-keyring.enable = true;` or KDE Wallet on Plasma.
- **In-app updates** are disabled (the AppImage lives in the read-only Nix store). Update the flake input instead; the launcher still notifies you when a new version is out. The backend and runtimes are still updated from the launcher's Settings, because they live in your home directory.
- **Game shortcuts / Add to Steam**: The wrapper passes the path it was started from (for example `/run/current-system/sw/bin/nexus-launcher`) to the launcher, so generated shortcuts survive package updates. Shortcuts created while running from a `/nix/store` path (e.g. via `nix run`) break after garbage collection.
- **Passkey sign-in fallback** ("Continue in browser") needs Google Chrome (`google-chrome` from nixpkgs, or the Flatpak).
- **Overlay**: Python 3, PyGObject, GTK 3 and WebKitGTK 4.1 are included in the FHS environment.

---

## Maintenance & Development

A guide for updating locked versions, testing changes, or modifying the package derivation can be found in the **[Developer & Agent Guide (AGENTS.md)](AGENTS.md)**.
