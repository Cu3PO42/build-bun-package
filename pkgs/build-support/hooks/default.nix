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
  writableTmpDirAsHomeHook,
  runtime ? bun,
  buildRuntime ? runtime,
}:
let
  nodeGyp = bunNodeGyp.override {
    inherit bun;
    runtime = buildRuntime;
  };
  nodeHeaders = if lib.getName runtime == "bun" then bunNodeHeaders else srcOnly runtime;
  nodeVersion = nodeHeaders.version;
  nodeShim =
    runtime:
    runCommand "bun-node-shim-${runtime.name}" { } ''
      mkdir -p "$out/bin"
      ln -s ${lib.getExe runtime} "$out/bin/node"
    '';
  bunNodeShim = nodeShim buildRuntime;
  runtimeNodeShim = nodeShim runtime;
  bunNodeFallbackHook = makeSetupHook {
    name = "bun-node-fallback-hook";
    propagatedBuildInputs = lib.unique [
      bun
      buildRuntime
    ];
    substitutions = { inherit bunNodeShim; };
  } ./bun-node-fallback-hook.sh;
  bunConfigHook = makeSetupHook {
    name = "bun-config-hook";
    propagatedBuildInputs = [
      bun
      bunNodeFallbackHook
      writableTmpDirAsHomeHook
    ];
    meta.license = lib.licenses.mit;
  } ./bun-config-hook.sh;
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
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ cctools ];
    substitutions = {
      nodeGyp = lib.getExe nodeGyp;
      inherit nodeHeaders nodeVersion;
      python = lib.getExe python3;
    };
    meta.license = lib.licenses.mit;
  } ./bun-node-gyp-hook.sh;
  inherit bunConfigHook;
  bunImportConfigHook = makeSetupHook {
    name = "bun-import-config-hook";
    propagatedBuildInputs = [ bunConfigHook ];
    substitutions.rewriteLock = ../import-bun-lock/rewrite-lock.ts;
    meta.license = lib.licenses.mit;
  } ./bun-import-config-hook.sh;
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
      runtime = lib.getExe runtime;
      inherit runtimeNodeShim;
    };
  } ./bun-install-hook.sh;
}
