{
  lib,
  makeSetupHook,
  makeWrapper,
  installShellFiles,
  jq,
  coreutils,
  jd-diff-patch,
  bun,
  runCommand,
  writeShellScriptBin,
  bunNodeGyp,
  bunNodeHeaders,
  python3,
  stdenv,
  cctools,
  srcOnly,
  writableTmpDirAsHomeHook,
  runtime ? bun,
  nodeGypTarget ? runtime,
}:
let
  # The standalone package's wrapper pins its runtime. Build-time node-gyp
  # instead follows PATH, including the runtime hook's conditional Bun fallback.
  nodeGypPackage = bunNodeGyp.override { inherit bun; };
  nodeGyp = writeShellScriptBin "node-gyp" ''
    exec node ${nodeGypPackage.nodeGypScript} "$@"
  '';
  targetIsBun = lib.getName nodeGypTarget == "bun";
  nodeHeaders =
    if targetIsBun then nodeGypTarget.nodeHeaders or bunNodeHeaders else srcOnly nodeGypTarget;
  nodeVersion = nodeHeaders.version;
  nodeShim =
    runtime:
    runCommand "bun-node-shim-${runtime.name}" { } ''
      mkdir -p "$out/bin"
      ln -s ${lib.getExe runtime} "$out/bin/node"
    '';
  bunNodeShim = nodeShim bun;
  runtimeNodeShim = nodeShim runtime;
in
rec {
  bunRuntimeHook = makeSetupHook {
    name = "bun-runtime-hook";
    propagatedBuildInputs = [ bun ] ++ lib.optional (lib.getName runtime != "bun") runtime;
    substitutions = {
      inherit
        bunNodeShim
        runtimeNodeShim
        coreutils
        ;
      envSplitFixup = ./bun-env-s-fixup.sh;
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
  bunConfigHook =
    assert lib.assertMsg (lib.versionAtLeast bun.version "1.4.4") "bunConfigHook requires Bun >= 1.4.4";
    makeSetupHook {
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
      nodeGypTarget = lib.getExe nodeGypTarget;
      checkBunHeaders = lib.boolToString targetIsBun;
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
  bunInstallHook =
    assert lib.assertMsg (lib.versionAtLeast bun.version "1.4.4")
      "bunInstallHook requires Bun >= 1.4.4";
    makeSetupHook {
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
