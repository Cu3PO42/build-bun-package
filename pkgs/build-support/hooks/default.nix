{
  lib,
  makeSetupHook,
  replaceVars,
  makeWrapper,
  installShellFiles,
  jq,
  coreutils,
  jd-diff-patch,
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
  nativeRuntime ? runtime,
}:
let
  nodeGyp = bunNodeGyp.override {
    inherit bun;
    runtime = buildRuntime;
  };
  nodeHeaders = if lib.getName nativeRuntime == "bun" then bunNodeHeaders else srcOnly nativeRuntime;
  nodeVersion = nodeHeaders.version;
  nodeShim =
    runtime:
    runCommand "bun-node-shim-${runtime.name}" { } ''
      mkdir -p "$out/bin"
      ln -s ${lib.getExe runtime} "$out/bin/node"
    '';
  buildRuntimeNodeShim = nodeShim buildRuntime;
  runtimeNodeShim = nodeShim runtime;
  envSplitFixup = replaceVars ./bun-env-s-fixup.sh {
    inherit buildRuntimeNodeShim runtimeNodeShim;
  };
in
rec {
  inherit buildRuntimeNodeShim;

  bunRuntimeHook = makeSetupHook {
    name = "bun-runtime-hook";
    propagatedBuildInputs = [ bun ];
    substitutions = {
      inherit
        buildRuntimeNodeShim
        runtimeNodeShim
        coreutils
        envSplitFixup
        ;
    };
  } ./bun-runtime-hook.sh;
  bunFetchMigrateHook = makeSetupHook {
    name = "bun-fetch-migrate-hook";
    propagatedBuildInputs = [
      bun
      jd-diff-patch
    ];
    substitutions.migrateLock = ../migrate-lock.sh;
    meta.license = lib.licenses.mit;
  } ./bun-fetch-migrate-hook.sh;
  bunMigrateHook = makeSetupHook {
    name = "bun-migrate-hook";
    propagatedBuildInputs = [ jd-diff-patch ];
    substitutions.migrateLock = ../migrate-lock.sh;
    meta.license = lib.licenses.mit;
  } ./bun-migrate-hook.sh;
  bunConfigHook = makeSetupHook {
    name = "bun-config-hook";
    propagatedBuildInputs = [
      bun
      bunRuntimeHook
      writableTmpDirAsHomeHook
    ];
    meta.license = lib.licenses.mit;
  } ./bun-config-hook.sh;
  bunNodeGypHook = makeSetupHook {
    name = "bun-node-gyp-hook";
    propagatedBuildInputs = [
      nodeGyp
      bunRuntimeHook
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
      bunRuntimeHook
    ];
    meta.license = lib.licenses.mit;
  } ./bun-build-hook.sh;
  bunCheckHook = makeSetupHook {
    name = "bun-check-hook";
    propagatedBuildInputs = [
      bun
      bunRuntimeHook
    ];
    meta.license = lib.licenses.mit;
  } ./bun-check-hook.sh;
  bunInstallHook = makeSetupHook {
    name = "bun-install-hook";
    meta.license = lib.licenses.mit;
    propagatedBuildInputs = [
      bun
      bunRuntimeHook
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
