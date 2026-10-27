{
  description = "Build Bun projects with an offline, fixed-output dependency cache";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default =
        final: prev:
        let
          packages = import ./pkgs { inherit (final) callPackage lib; };
        in
        packages
        // {
          # Keep the attribute names independent of final while Nixpkgs boots.
          bun =
            if nixpkgs.lib.versionOlder prev.bun.version packages.bun.version then packages.bun else prev.bun;
        };
      legacyPackages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        nixpkgs.lib.makeScope pkgs.newScope (
          scope:
          import ./pkgs {
            inherit (scope) callPackage;
            inherit (pkgs) lib;
          }
        )
      );
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
      checks = forAllSystems (
        system:
        (import ./tests {
          pkgs = nixpkgs.legacyPackages.${system} // self.legacyPackages.${system};
        })
        // {
          flake-api = import ./tests/flake.nix {
            inherit self;
            pkgs = nixpkgs.legacyPackages.${system};
          };
        }
      );
      packages = forAllSystems (
        system:
        let
          pkgs = self.legacyPackages.${system};
          basePkgs = nixpkgs.legacyPackages.${system};
        in
        {
          inherit (pkgs) bun;
          opencode = pkgs.callPackage ./tests/opencode.nix { };
          swagger-typescript-api = pkgs.callPackage ./tests/swagger-typescript-api.nix { };
          kulala-core = pkgs.callPackage ./tests/kulala-core.nix { };
          gitlab-ci-local = pkgs.callPackage ./tests/gitlab-ci-local.nix { };
          filen-cli = pkgs.callPackage ./tests/filen-cli.nix { };
          balatro-mod-manager-web = pkgs.callPackage ./tests/balatro-mod-manager-web.nix { };
          handy-frontend = pkgs.callPackage ./tests/handy-frontend.nix { };
          models-dev = pkgs.callPackage ./tests/models-dev.nix { };
        }
        // nixpkgs.lib.optionalAttrs basePkgs.stdenv.hostPlatform.isLinux {
          convertx = pkgs.callPackage ./tests/convertx.nix { };
          equibop = pkgs.callPackage ./tests/equibop.nix { };
        }
      );
    }
    // nixpkgs.lib.genAttrs [
      "bun"
      "buildBunPackage"
      "fetchBunDeps"
      "bunHooks"
      "bunNodeGyp"
      "bunNodeHeaders"
      "bunNodeGypHook"
    ] (name: forAllSystems (system: self.legacyPackages.${system}.${name}))
    // nixpkgs.lib.genAttrs [
      "bunConfigHook"
      "bunBuildHook"
      "bunInstallHook"
      "bunNodeFallbackHook"
      "bunNodeShim"
    ] (name: forAllSystems (system: self.legacyPackages.${system}.bunHooks.${name}));
}
