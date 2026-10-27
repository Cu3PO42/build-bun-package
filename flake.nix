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
        builtins.removeAttrs packages [ "bun" ]
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.versionOlder prev.bun.version packages.bun.version) {
          inherit (packages) bun;
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
      packages = forAllSystems (system: {
        inherit (self.legacyPackages.${system}) bun;
        opencode = self.legacyPackages.${system}.callPackage ./tests/opencode.nix { };
        swagger-typescript-api =
          self.legacyPackages.${system}.callPackage ./tests/swagger-typescript-api.nix
            { };
      });
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
