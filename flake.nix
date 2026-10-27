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
      overlays.default = final: _prev: import ./package-set.nix { inherit (final) callPackage; };
      legacyPackages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        nixpkgs.lib.makeScope pkgs.newScope (
          scope: import ./package-set.nix { inherit (scope) callPackage; }
        )
      );
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
      checks = forAllSystems (
        system:
        import ./tests {
          pkgs = nixpkgs.legacyPackages.${system} // self.legacyPackages.${system};
        }
      );
      packages = forAllSystems (system: {
        inherit (self.legacyPackages.${system}) bun;
        opencode = self.legacyPackages.${system}.callPackage ./tests/opencode.nix { };
        swagger-typescript-api =
          self.legacyPackages.${system}.callPackage ./tests/swagger-typescript-api.nix
            { };
      });
    };
}
