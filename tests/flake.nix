{ self, pkgs }:
let
  scope = self.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  overlay = version: self.overlays.default scope { bun = { inherit version; }; };
  equal = overlay scope.bun.version;
  newer = overlay "999.0.0";
  older = overlay "0.0.0";
  extended = scope.overrideScope (_final: _prev: { bun = pkgs.bun; });
in
assert !(equal ? bun);
assert !(newer ? bun);
assert older.bun.version == scope.bun.version;
assert self.buildBunPackage.${pkgs.stdenv.hostPlatform.system} ? override;
assert self.fetchBunDeps.${pkgs.stdenv.hostPlatform.system} ? override;
assert self.bunConfigHook.${pkgs.stdenv.hostPlatform.system} == scope.bunHooks.bunConfigHook;
assert self.bunBuildHook.${pkgs.stdenv.hostPlatform.system} == scope.bunHooks.bunBuildHook;
assert self.bunInstallHook.${pkgs.stdenv.hostPlatform.system} == scope.bunHooks.bunInstallHook;
assert self.bunNodeGypHook.${pkgs.stdenv.hostPlatform.system} == scope.bunNodeGypHook;
assert self.bunNodeGyp.${pkgs.stdenv.hostPlatform.system} == scope.bunNodeGyp;
assert self.bunNodeHeaders.${pkgs.stdenv.hostPlatform.system} == scope.bunNodeHeaders;
assert scope.buildBunPackage ? override;
assert scope.fetchBunDeps ? override;
assert extended.bun == pkgs.bun;
assert
  (scope.bunNodeGypHook.override { nodejs = pkgs.nodejs; }).drvPath
  == (scope.bunHooks.override { nodejs = pkgs.nodejs; }).bunNodeGypHook.drvPath;
assert
  (scope.bunNodeGypHook.override { python3 = pkgs.python312; }).drvPath
  == (scope.bunHooks.override { python3 = pkgs.python312; }).bunNodeGypHook.drvPath;
pkgs.runCommand "bun-flake-api" { } "touch $out"
