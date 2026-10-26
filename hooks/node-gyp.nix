{
  lib,
  makeSetupHook,
  bun,
  bunHooks,
  bunNodeGyp,
  bunNodeHeaders,
  python3,
  stdenv,
  cctools,
}:
let
  nodeGyp = bunNodeGyp.override { inherit bun; };
in
makeSetupHook {
  name = "bun-node-gyp-hook";
  propagatedBuildInputs = [
    nodeGyp
    (bunHooks.override { inherit bun; }).bunNodeFallbackHook
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ cctools ];
  substitutions = {
    nodeGyp = lib.getExe nodeGyp;
    nodeHeaders = bunNodeHeaders;
    nodeVersion = bunNodeHeaders.version;
    python = lib.getExe python3;
  };
  meta.license = lib.licenses.mit;
} ./bun-node-gyp-hook.sh
