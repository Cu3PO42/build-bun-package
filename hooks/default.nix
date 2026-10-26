{
  lib,
  makeSetupHook,
  makeWrapper,
  installShellFiles,
  jq,
  bun,
}:
{
  bunConfigHook = makeSetupHook {
    name = "bun-config-hook";
    meta.license = lib.licenses.mit;
  } ./bun-config-hook.sh;
  bunBuildHook = makeSetupHook {
    name = "bun-build-hook";
    meta.license = lib.licenses.mit;
  } ./bun-build-hook.sh;
  bunInstallHook = makeSetupHook {
    name = "bun-install-hook";
    meta.license = lib.licenses.mit;
    propagatedBuildInputs = [
      makeWrapper
      installShellFiles
    ];
    substitutions = { inherit jq bun; };
  } ./bun-install-hook.sh;
}
