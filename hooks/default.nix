{
  lib,
  makeSetupHook,
  makeWrapper,
  installShellFiles,
  jq,
  bun,
  nodejs,
  srcOnly,
  stdenv,
  cctools,
  runCommand,
}:
let
  bunNodeShim = runCommand "bun-node-shim-${bun.version}" { } ''
    mkdir -p "$out/bin"
    ln -s ${bun}/bin/bun "$out/bin/node"
  '';
  nodeFallbackHook = makeSetupHook {
    name = "bun-node-fallback-hook";
    substitutions = { inherit bunNodeShim; };
  } ./bun-node-fallback-hook.sh;
in
{
  inherit bunNodeShim;
  bunConfigHook = makeSetupHook {
    name = "bun-config-hook";
    propagatedBuildInputs = [
      bun
      nodeFallbackHook
      nodejs
      nodejs.python
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ cctools ];
    substitutions = {
      nodeSrc = srcOnly nodejs;
      nodeGyp = "${nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js";
    };
    meta.license = lib.licenses.mit;
  } ./bun-config-hook.sh;
  bunBuildHook = makeSetupHook {
    name = "bun-build-hook";
    propagatedBuildInputs = [
      bun
      nodeFallbackHook
    ];
    meta.license = lib.licenses.mit;
  } ./bun-build-hook.sh;
  bunInstallHook = makeSetupHook {
    name = "bun-install-hook";
    meta.license = lib.licenses.mit;
    propagatedBuildInputs = [
      bun
      nodeFallbackHook
      makeWrapper
      installShellFiles
    ];
    substitutions = { inherit jq bun; };
  } ./bun-install-hook.sh;
}
