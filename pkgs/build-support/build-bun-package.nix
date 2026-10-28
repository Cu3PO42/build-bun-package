{
  lib,
  stdenv,
  bun,
  fetchBunDeps,
  bunHooks,
  nix-update-script,
}:

let
  defaultBun = bun;
in
lib.extendMkDerivation {
  constructDrv = stdenv.mkDerivation;
  extendDrvArgs =
    finalAttrs:
    {
      name ? "${args.pname}-${args.version}",
      bunDepsHash ? "",
      bunDeps ? null,
      bunDepsNativeBuildInputs ? [ ],
      bunDepsImpureEnvVars ? [ ],
      bunConfigHook ? null,
      bunBuildHook ? null,
      bunCheckHook ? null,
      bunInstallHook ? null,
      nativeBuildInputs ? [ ],
      runtime ? finalAttrs.bun,
      buildRuntime ? finalAttrs.runtime,
      nodeGyp ? false,
      bunWorkspace ? null,
      bunRunScripts ? false,
      bunFlags ? [ ],
      bunFetchFlags ? [ ],
      bunInstallFlags ? [ ],
      bunBuildFlags ? [ ],
      bunCheckFlags ? [ ],
      bunCheckScript ? null,
      bunPackFlags ? [ ],
      bunPruneFlags ? [ ],
      ...
    }@args:
    let
      selectedBun =
        assert lib.assertMsg (lib.versionAtLeast finalAttrs.bun.version "1.4.4")
          "buildBunPackage requires Bun >= 1.4.4";
        finalAttrs.bun;
      selectedHooks = bunHooks.override {
        bun = selectedBun;
        runtime = finalAttrs.runtime;
        buildRuntime = finalAttrs.buildRuntime;
      };
      hook =
        name:
        if (finalAttrs.${name} or null) != null then
          finalAttrs.${name}
        else if name == "bunConfigHook" && (finalAttrs.bunDeps.isBunSourceBundle or false) then
          selectedHooks.bunImportConfigHook
        else
          selectedHooks.${name};
      # Forward only source preparation, never package phases, hooks or inputs.
      # Read finalAttrs so overrideAttrs also changes the dependency fetch.
      preparation = builtins.intersectAttrs (lib.genAttrs [
        "src"
        "srcs"
        "sourceRoot"
        "setSourceRoot"
        "unpackPhase"
        "preUnpack"
        "postUnpack"
        "preUnpackHooks"
        "postUnpackHooks"
        "patches"
        "patchFlags"
        "prePatch"
        "postPatch"
        "prePatchHooks"
        "postPatchHooks"
        "bunRoot"
        "bunFlags"
        "bunFetchFlags"
      ] (_: null)) finalAttrs;
      deps =
        if bunDeps != null then
          bunDeps
        else
          (fetchBunDeps.override { bun = selectedBun; }) (
            preparation
            // {
              name = "${finalAttrs.name or "${finalAttrs.pname}-${finalAttrs.version}"}-bun-deps";
              nativeBuildInputs = finalAttrs.bunDepsNativeBuildInputs or bunDepsNativeBuildInputs;
              impureEnvVars = finalAttrs.bunDepsImpureEnvVars or bunDepsImpureEnvVars;
              hash = finalAttrs.bunDepsHash or bunDepsHash;
            }
          );
    in
    {
      inherit
        bunDepsNativeBuildInputs
        bunDepsImpureEnvVars
        runtime
        buildRuntime
        nodeGyp
        bunWorkspace
        bunRunScripts
        bunFlags
        bunFetchFlags
        bunInstallFlags
        bunBuildFlags
        bunCheckFlags
        bunCheckScript
        bunPackFlags
        bunPruneFlags
        ;
      bun = args.bun or defaultBun;
      bunDeps = deps;
      bunBuildScript = args.bunBuildScript or "build";
      nativeBuildInputs =
        nativeBuildInputs
        ++ [
          selectedBun
          (hook "bunConfigHook")
          (hook "bunBuildHook")
          (hook "bunCheckHook")
          (hook "bunInstallHook")
        ]
        ++ lib.optional finalAttrs.nodeGyp selectedHooks.bunNodeGypHook;
      passthru = {
        updateScript = nix-update-script {
          extraArgs = [
            "--custom-dep"
            "bunDeps"
          ];
        };
      }
      // (args.passthru or { });
      __structuredAttrs = args.__structuredAttrs or true;
      strictDeps = args.strictDeps or true;
      dontStrip = args.dontStrip or true;
      meta = (args.meta or { }) // {
        platforms = args.meta.platforms or selectedBun.meta.platforms;
      };
    };
}
