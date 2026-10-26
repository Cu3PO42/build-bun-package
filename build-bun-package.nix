{
  lib,
  stdenv,
  bun,
  nodejs,
  fetchBunDeps,
  bunHooks,
}:

let
  defaultBun = bun;
  defaultNodejs = nodejs;
in
lib.extendMkDerivation {
  constructDrv = stdenv.mkDerivation;
  extendDrvArgs =
    finalAttrs:
    {
      name ? "${args.pname}-${args.version}",
      bunDepsHash ? "",
      bunDeps ? null,
      bunConfigHook ? null,
      bunBuildHook ? null,
      bunInstallHook ? null,
      nativeBuildInputs ? [ ],
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
        nodejs = finalAttrs.nodejs;
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
      # Only source preparation belongs in the fixed-output fetcher. Forwarding
      # the whole derivation would also run package phases and introduce cycles.
      preparation = lib.filterAttrs (
        name: _:
        builtins.elem name [
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
          "buildInputs"
          "env"
          "bunRoot"
          "bunFlags"
          "bunFetchFlags"
        ]
      ) finalAttrs;
      deps =
        if bunDeps != null then
          bunDeps
        else
          (fetchBunDeps.override { bun = selectedBun; }) (
            preparation
            // {
              name = "${finalAttrs.name or "${finalAttrs.pname}-${finalAttrs.version}"}-bun-deps";
              nativeBuildInputs = lib.filter (
                input: !(builtins.elem (toString input) (map toString internalInputs))
              ) finalAttrs.nativeBuildInputs;
              hash = finalAttrs.bunDepsHash or bunDepsHash;
            }
          );
    in
    {
      inherit
        bunWorkspace
        bunFlags
        bunFetchFlags
        bunInstallFlags
        bunBuildFlags
        bunPackFlags
        bunPruneFlags
        ;
      bun = args.bun or defaultBun;
      nodejs = args.nodejs or defaultNodejs;
      bunDeps = deps;
      bunBuildScript = args.bunBuildScript or "build";
      nativeBuildInputs = nativeBuildInputs ++ internalInputs;
      strictDeps = args.strictDeps or true;
      dontStrip = args.dontStrip or true;
      meta = (args.meta or { }) // {
        platforms = args.meta.platforms or selectedBun.meta.platforms;
      };
    };
}
