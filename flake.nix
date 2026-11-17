{
  description = "Nexus Launcher - Xbox-inspired launcher for Microsoft Store PC games (Nix package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        nexus-launcher = pkgs.callPackage ./pkgs/nexus-launcher.nix { };
      in
      {
        packages = {
          default = nexus-launcher;
          inherit nexus-launcher;
        };

        apps.default = flake-utils.lib.mkApp { drv = nexus-launcher; };

        formatter = pkgs.nixfmt;

        # Development shell for working on this flake
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nix
            git
            curl
            jq
          ];

          shellHook = ''
            echo "Nexus Launcher Nix development environment"
            echo "Available commands:"
            echo "  ./scripts/check-version.sh  - Check current vs latest version"
            echo "  ./scripts/update-version.sh - Update to latest version"
          '';
        };
      }
    )
    // {
      # Overlay for easy integration into NixOS configurations
      overlays.default = final: prev: {
        nexus-launcher = final.callPackage ./pkgs/nexus-launcher.nix { };
      };
    };
}
