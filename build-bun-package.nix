{
  lib,
  stdenv,
  bun,
  fetchBunDeps,
  bunHooks,
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
      bunInstallHook ? null,
      nativeBuildInputs ? [ ],
      nodejs ? null,
      bunWorkspace ? null,
      bunFlags ? [ ],
      bunFetchFlags ? [ ],
      bunInstallFlags ? [ ],
      bunBuildFlags ? [ ],
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
      };
      internalInputs = [
        selectedBun
        (
          if (finalAttrs.bunConfigHook or bunConfigHook) != null then
            (finalAttrs.bunConfigHook or bunConfigHook)
          else
            selectedHooks.bunConfigHook
        )
        (
          if (finalAttrs.bunBuildHook or bunBuildHook) != null then
            (finalAttrs.bunBuildHook or bunBuildHook)
          else
            selectedHooks.bunBuildHook
        )
        (
          if (finalAttrs.bunInstallHook or bunInstallHook) != null then
            (finalAttrs.bunInstallHook or bunInstallHook)
          else
            selectedHooks.bunInstallHook
        )
      ];
      # Share source preparation explicitly. Package tools, setup hooks and
      # environment belong only to the ordinary build unless opted in below.
      preparation = {
        src = finalAttrs.src or null;
        srcs = finalAttrs.srcs or null;
        sourceRoot = finalAttrs.sourceRoot or null;
        setSourceRoot = finalAttrs.setSourceRoot or "";
        preUnpack = finalAttrs.preUnpack or "";
        postUnpack = finalAttrs.postUnpack or "";
        preUnpackHooks = finalAttrs.preUnpackHooks or [ ];
        postUnpackHooks = finalAttrs.postUnpackHooks or [ ];
        patches = finalAttrs.patches or [ ];
        patchFlags = finalAttrs.patchFlags or [ "-p1" ];
        prePatch = finalAttrs.prePatch or "";
        postPatch = finalAttrs.postPatch or "";
        prePatchHooks = finalAttrs.prePatchHooks or [ ];
        postPatchHooks = finalAttrs.postPatchHooks or [ ];
        bunRoot = finalAttrs.bunRoot or ".";
        bunFlags = finalAttrs.bunFlags or [ ];
        bunFetchFlags = finalAttrs.bunFetchFlags or [ ];
      }
      // lib.optionalAttrs (finalAttrs ? unpackPhase) {
        inherit (finalAttrs) unpackPhase;
      };
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
        nodejs
        bunWorkspace
        bunFlags
        bunFetchFlags
        bunInstallFlags
        bunBuildFlags
        bunPackFlags
        bunPruneFlags
        ;
      bun = args.bun or defaultBun;
      bunDeps = deps;
      bunBuildScript = args.bunBuildScript or "build";
      nativeBuildInputs =
        nativeBuildInputs ++ internalInputs ++ lib.optional (finalAttrs.nodejs != null) finalAttrs.nodejs;
      strictDeps = args.strictDeps or true;
      dontStrip = args.dontStrip or true;
      meta = (args.meta or { }) // {
        platforms = args.meta.platforms or selectedBun.meta.platforms;
      };
    };
}
