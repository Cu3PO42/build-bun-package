{
  makeSetupHook,
  makeWrapper,
  installShellFiles,
  jq,
  bun,
}:
{
  bunConfigHook = makeSetupHook { name = "bun-config-hook"; } ./bun-config-hook.sh;
  bunBuildHook = makeSetupHook { name = "bun-build-hook"; } ./bun-build-hook.sh;
  bunInstallHook = makeSetupHook {
    name = "bun-install-hook";
    propagatedBuildInputs = [
      makeWrapper
      installShellFiles
    ];
    substitutions = { inherit jq bun; };
  } ./bun-install-hook.sh;
}
