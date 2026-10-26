{
  lib,
  makeSetupHook,
  makeWrapper,
  installShellFiles,
  jq,
  bun,
  runCommand,
}:
let
  bunNodeShim = runCommand "bun-node-shim-${bun.version}" { } ''
    mkdir -p "$out/bin"
    ln -s ${bun}/bin/bun "$out/bin/node"
  '';
  bunNodeFallbackHook = makeSetupHook {
    name = "bun-node-fallback-hook";
    propagatedBuildInputs = [ bun ];
    substitutions = { inherit bunNodeShim; };
  } ./bun-node-fallback-hook.sh;
in
{
  inherit bunNodeShim bunNodeFallbackHook;
  bunConfigHook = makeSetupHook {
    name = "bun-config-hook";
    propagatedBuildInputs = [
      bun
      bunNodeFallbackHook
    ];
    meta.license = lib.licenses.mit;
  } ./bun-config-hook.sh;
  bunBuildHook = makeSetupHook {
    name = "bun-build-hook";
    propagatedBuildInputs = [
      bun
      bunNodeFallbackHook
    ];
    meta.license = lib.licenses.mit;
  } ./bun-build-hook.sh;
  bunInstallHook = makeSetupHook {
    name = "bun-install-hook";
    meta.license = lib.licenses.mit;
    propagatedBuildInputs = [
      bun
      bunNodeFallbackHook
      makeWrapper
      installShellFiles
    ];
    substitutions = { inherit jq bun; };
  } ./bun-install-hook.sh;
}
