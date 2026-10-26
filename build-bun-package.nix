{
  lib,
  stdenv,
  bun,
  fetchBunDeps,
  bunHooks,
}:

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
      ...
    }@args:
    let
      internalInputs = [
        bun
        (
          if (finalAttrs.bunConfigHook or bunConfigHook) != null then
            (finalAttrs.bunConfigHook or bunConfigHook)
          else
            bunHooks.bunConfigHook
        )
        (
          if (finalAttrs.bunBuildHook or bunBuildHook) != null then
            (finalAttrs.bunBuildHook or bunBuildHook)
          else
            bunHooks.bunBuildHook
        )
        (
          if (finalAttrs.bunInstallHook or bunInstallHook) != null then
            (finalAttrs.bunInstallHook or bunInstallHook)
          else
            bunHooks.bunInstallHook
        )
      ];
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
        "buildInputs"
        "env"
        "bunRoot"
        "bunFetchFlags"
      ] (_: null)) finalAttrs;
      deps =
        if bunDeps != null then
          bunDeps
        else
          fetchBunDeps (
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
    assert lib.assertMsg (lib.versionAtLeast bun.version "1.4.4")
      "buildBunPackage requires Bun >= 1.4.4";
    {
      bunDeps = deps;
      bunBuildScript = args.bunBuildScript or "build";
      nativeBuildInputs = nativeBuildInputs ++ internalInputs;
      strictDeps = args.strictDeps or true;
      dontStrip = args.dontStrip or true;
      meta = (args.meta or { }) // {
        platforms = args.meta.platforms or bun.meta.platforms;
      };
    };
}
