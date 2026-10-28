{
  lib,
  makeSetupHook,
  makeWrapper,
  installShellFiles,
  jq,
  bun,
  runCommand,
  bunNodeGyp,
  bunNodeHeaders,
  python3,
  stdenv,
  cctools,
  srcOnly,
  nodejs ? null,
  bunRuntime ? bun,
}:
let
  nodeGyp = bunNodeGyp.override { inherit bun nodejs; };
  nodeHeaders = if nodejs == null then bunNodeHeaders else srcOnly nodejs;
  nodeVersion = if nodejs == null then bunNodeHeaders.version else nodejs.version;
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
  bunNodeGypHook = makeSetupHook {
    name = "bun-node-gyp-hook";
    propagatedBuildInputs = [
      nodeGyp
      bunNodeFallbackHook
      python3
    ]
    ++ lib.optional (nodejs != null) nodejs
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ cctools ];
    substitutions = {
      nodeGyp = lib.getExe nodeGyp;
      inherit nodeHeaders nodeVersion;
      python = lib.getExe python3;
    };
    meta.license = lib.licenses.mit;
  } ./bun-node-gyp-hook.sh;
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
  bunCheckHook = makeSetupHook {
    name = "bun-check-hook";
    propagatedBuildInputs = [
      bun
      bunNodeFallbackHook
    ];
    meta.license = lib.licenses.mit;
  } ./bun-check-hook.sh;
  bunInstallHook = makeSetupHook {
    name = "bun-install-hook";
    meta.license = lib.licenses.mit;
    propagatedBuildInputs = [
      bun
      bunNodeFallbackHook
      makeWrapper
      installShellFiles
    ];
    substitutions = {
      inherit jq;
      runtime = lib.getExe bunRuntime;
    };
  } ./bun-install-hook.sh;
}
