{
  self,
  pkgs,
  basePkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  helpers = self.legacyPackages.${system};
  bundledBun = pkgs.callPackage ../pkgs/bun { };
  overlay =
    version:
    self.overlays.default pkgs {
      bun = {
        inherit version;
        marker = true;
      };
    };
  equal = overlay bundledBun.version;
  newer = overlay "999.0.0";
  older = overlay "0.0.0";
  overlaid = import self.inputs.nixpkgs {
    inherit system;
    overlays = [ self.overlays.default ];
    config = {
      allowAliases = false;
      checkMeta = true;
    };
  };
  example = helpers.buildBunPackage {
    pname = "bun-flake-example";
    version = "1";
    src = ./fixtures/basic;
    nodeGyp = true;
  };
  expectedBun =
    if pkgs.lib.versionOlder basePkgs.bun.version bundledBun.version then bundledBun else basePkgs.bun;
  alternateBun = pkgs.bun.overrideAttrs (_: {
    env.NIX_BUN_TEST_VARIANT = "overlay";
  });
  extended = pkgs.extend (_final: _prev: { bun = alternateBun; });
  extendedPackage = extended.buildBunPackage {
    pname = "bun-extended-example";
    version = "1";
    src = ./fixtures/basic;
    nodeGyp = true;
  };
in
assert equal.bun.version == bundledBun.version;
assert equal.bun.marker;
assert newer.bun.version == "999.0.0";
assert newer.bun.marker;
assert older.bun.drvPath == bundledBun.drvPath;
assert helpers.buildBunPackage ? override;
assert helpers.fetchBunDeps ? override;
assert helpers.importBunLock ? override;
assert helpers.importBunLock.bunConfigHook == pkgs.bunHooks.bunImportConfigHook;
assert !(helpers ? nodejs);
assert !(helpers ? callPackage);
assert !(helpers ? bunNodeGypHook);
assert !(self ? buildBunPackage);
assert !(self ? hydraJobs);
assert pkgs.bun.drvPath == expectedBun.drvPath;
assert overlaid.bun.drvPath == expectedBun.drvPath;
assert helpers.bun.drvPath == pkgs.bun.drvPath;
assert self.packages.${system}.bun.drvPath == pkgs.bun.drvPath;
assert self.packages.${system}.bunNodeGyp.drvPath == helpers.bunNodeGyp.drvPath;
assert self.packages.${system}.bunNodeHeaders.drvPath == helpers.bunNodeHeaders.drvPath;
assert self.packages.${system}.example-filen-cli.bun.drvPath == pkgs.bun.drvPath;
assert (self.packages.${system} ? example-equibop) == pkgs.stdenv.hostPlatform.isLinux;
assert example.bun.drvPath == pkgs.bun.drvPath;
assert example.runtime.drvPath == pkgs.bun.drvPath;
assert example.buildRuntime.drvPath == pkgs.bun.drvPath;
assert builtins.elem pkgs.bunHooks.bunNodeGypHook.drvPath (
  map (input: input.drvPath) example.nativeBuildInputs
);
assert extendedPackage.bun.drvPath == alternateBun.drvPath;
assert extendedPackage.runtime.drvPath == alternateBun.drvPath;
assert builtins.elem alternateBun.drvPath (
  map (input: input.drvPath) extendedPackage.bunDeps.nativeBuildInputs
);
assert builtins.elem extended.bunHooks.bunNodeGypHook.drvPath (
  map (input: input.drvPath) extendedPackage.nativeBuildInputs
);
pkgs.runCommand "bun-flake-api" { } "touch $out"
