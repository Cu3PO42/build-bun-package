{
  description = "Build Bun projects with an offline, fixed-output dependency cache";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504";

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
      overlays.default = final: prev: {
        bun = final.callPackage ./bun.nix { };
        fetchBunDeps = final.callPackage ./fetch-bun-deps.nix { };
        bunHooks = final.callPackage ./hooks { };
        bunNodeGyp = final.callPackage ./node-gyp.nix { };
        bunNodeHeaders = final.callPackage ./node-headers.nix { };
        bunNodeGypHook = final.callPackage ./hooks/node-gyp.nix { };
        buildBunPackage = final.callPackage ./build-bun-package.nix { };
      };
      legacyPackages = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        }
      );
      formatter = forAllSystems (system: self.legacyPackages.${system}.nixfmt);
      checks = forAllSystems (system: import ./tests { pkgs = self.legacyPackages.${system}; });
      packages = forAllSystems (system: {
        inherit (self.legacyPackages.${system}) bun;
        example = self.legacyPackages.${system}.callPackage ./tests/example.nix { };
        default = self.packages.${system}.example;
      });
    };
}
