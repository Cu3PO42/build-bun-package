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
      pkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system}.extend self.overlays.default);
    in
    {
      overlays.default =
        final: prev:
        let
          packages = import ./pkgs { inherit (final) callPackage; };
        in
        packages
        // {
          # Keep the attribute names independent of final while Nixpkgs boots.
          bun =
            if nixpkgs.lib.versionOlder prev.bun.version packages.bun.version then packages.bun else prev.bun;
        };
      legacyPackages = forAllSystems (system: {
        inherit (pkgsFor.${system})
          bun
          buildBunPackage
          fetchBunDeps
          importBunLock
          bunHooks
          bunNodeGyp
          bunNodeHeaders
          ;
      });
      formatter = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        pkgs.treefmt.withConfig {
          imports = [ ./treefmt.nix ];
          _module.args.bun = pkgs.bun;
        }
      );
      checks = forAllSystems (
        system:
        (import ./tests { pkgs = pkgsFor.${system}; })
        // {
          flake-api = import ./tests/flake.nix {
            inherit self;
            pkgs = pkgsFor.${system};
            basePkgs = nixpkgs.legacyPackages.${system};
          };
        }
      );
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          inherit (pkgs) bun bunNodeGyp bunNodeHeaders;
          example-opencode = pkgs.callPackage ./integration/opencode.nix { };
          example-swagger-typescript-api = pkgs.callPackage ./integration/swagger-typescript-api.nix { };
          example-kulala-core = pkgs.callPackage ./integration/kulala-core.nix { };
          example-gitlab-ci-local = pkgs.callPackage ./integration/gitlab-ci-local.nix { };
          example-filen-cli = pkgs.callPackage ./integration/filen-cli.nix { };
          example-balatro-mod-manager-web = pkgs.callPackage ./integration/balatro-mod-manager-web.nix { };
          example-handy-frontend = pkgs.callPackage ./integration/handy-frontend.nix { };
          example-models-dev = pkgs.callPackage ./integration/models-dev.nix { };
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          example-equibop = pkgs.callPackage ./integration/equibop.nix { };
        }
      );
    };
}
