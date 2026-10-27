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
  bunNodeGypHook = makeSetupHook {
    name = "bun-node-gyp-hook";
    propagatedBuildInputs = [
      (bunNodeGyp.override { inherit bun; })
      bunNodeFallbackHook
      python3
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ cctools ];
    substitutions = {
      nodeGyp = lib.getExe (bunNodeGyp.override { inherit bun; });
      nodeHeaders = bunNodeHeaders;
      nodeVersion = bunNodeHeaders.version;
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
