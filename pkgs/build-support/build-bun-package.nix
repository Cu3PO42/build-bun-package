{
  lib,
  stdenv,
  bun,
  fetchBunDeps,
  bunHooks,
  nix-update-script,
}@topLevelArgs:

lib.extendMkDerivation {
  constructDrv = stdenv.mkDerivation;
  extendDrvArgs =
    finalAttrs:
    {
      # Recursive hash of the dependency cache; use lib.fakeHash to calculate it.
      bunDepsHash ? "",
      # Supply a dependency cache or importBunLock source bundle directly.
      bunDeps ? null,
      # Tools and impure environment variables needed only by the dependency fetcher.
      bunDepsNativeBuildInputs ? [ ],
      bunDepsImpureEnvVars ? [ ],
      # Replace individual setup hooks.
      bunConfigHook ? null,
      bunBuildHook ? null,
      bunCheckHook ? null,
      bunInstallHook ? null,
      nativeBuildInputs ? [ ],
      bun ? topLevelArgs.bun,
      # Runtime for installed executables and Node subprocesses.
      runtime ? finalAttrs.bun,
      # Runtime for Node commands during the build, including lifecycle scripts.
      buildRuntime ? finalAttrs.runtime,
      # Enable node-gyp and its native build tools.
      nodeGyp ? false,
      # Workspace directory relative to bunRoot to build and install.
      bunWorkspace ? null,
      # Run trusted dependency and root lifecycle scripts during installation.
      bunRunScripts ? false,
      # The package.json script to run when building the project.
      bunBuildScript ? "build",
      # Flags passed to every Bun command.
      bunFlags ? [ ],
      # Flags passed to bun pm fetch.
      bunFetchFlags ? [ ],
      # Flags passed to bun install.
      bunInstallFlags ? [ ],
      # Arguments passed to the build script.
      bunBuildFlags ? [ ],
      # Flags passed to bun test, or arguments passed to bunCheckScript.
      bunCheckFlags ? [ ],
      # Run this package.json script instead of bun test.
      bunCheckScript ? null,
      # Flags passed to bun pm pack.
      bunPackFlags ? [ ],
      # Flags passed to bun prune.
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
    in
    {
      inherit
        bun
        runtime
        buildRuntime
        bunBuildScript
        ;
      bunDeps =
        if bunDeps != null then
          bunDeps
        else
          (fetchBunDeps.override { bun = selectedBun; }) {
            name = "${finalAttrs.name or "${finalAttrs.pname}-${finalAttrs.version}"}-bun-deps";
            src = finalAttrs.src or null;
            srcs = finalAttrs.srcs or null;
            sourceRoot = finalAttrs.sourceRoot or null;
            prePatch = finalAttrs.prePatch or "";
            patches = finalAttrs.patches or [ ];
            postPatch = finalAttrs.postPatch or "";
            patchFlags = finalAttrs.patchFlags or [ "-p1" ];
            bunRoot = finalAttrs.bunRoot or ".";
            bunFlags = finalAttrs.bunFlags or bunFlags;
            bunFetchFlags = finalAttrs.bunFetchFlags or bunFetchFlags;
            nativeBuildInputs = finalAttrs.bunDepsNativeBuildInputs or bunDepsNativeBuildInputs;
            impureEnvVars = finalAttrs.bunDepsImpureEnvVars or bunDepsImpureEnvVars;
            hash = finalAttrs.bunDepsHash or bunDepsHash;
          };
      nativeBuildInputs =
        nativeBuildInputs
        ++ [
          selectedBun
          # Prefer caller-supplied hooks, selecting the importer for source bundles.
          (
            if (finalAttrs.bunConfigHook or null) != null then
              finalAttrs.bunConfigHook
            else if finalAttrs.bunDeps.isBunSourceBundle or false then
              selectedHooks.bunImportConfigHook
            else
              selectedHooks.bunConfigHook
          )
          (
            if (finalAttrs.bunBuildHook or null) != null then
              finalAttrs.bunBuildHook
            else
              selectedHooks.bunBuildHook
          )
          (
            if (finalAttrs.bunCheckHook or null) != null then
              finalAttrs.bunCheckHook
            else
              selectedHooks.bunCheckHook
          )
          (
            if (finalAttrs.bunInstallHook or null) != null then
              finalAttrs.bunInstallHook
            else
              selectedHooks.bunInstallHook
          )
        ]
        ++ lib.optional (finalAttrs.nodeGyp or nodeGyp) selectedHooks.bunNodeGypHook;
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
      # Stripping every file in the installed dependency tree is expensive.
      dontStrip = args.dontStrip or true;
      meta = (args.meta or { }) // {
        platforms = args.meta.platforms or selectedBun.meta.platforms;
      };
    };
}
