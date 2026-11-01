{ pkgs, example }:
{
  hook-version-validation =
    let
      bunWithVersion =
        version:
        pkgs.bun.overrideAttrs (_: {
          inherit version;
          __intentionallyOverridingVersion = true;
        });
      oldBun = bunWithVersion "1.4.3";
      oldHooks = pkgs.bunHooks.override { bun = oldBun; };
      minimumHooks = pkgs.bunHooks.override { bun = bunWithVersion "1.4.4"; };
      evaluates = drv: (builtins.tryEval drv.drvPath).success;
      oldPackage =
        args:
        pkgs.buildBunPackage (
          {
            pname = "bun-version-validation";
            version = "1";
            bun = oldBun;
            bunDeps = pkgs.emptyDirectory;
          }
          // args
        );
    in
    assert !(evaluates oldHooks.bunConfigHook);
    assert !(evaluates oldHooks.bunInstallHook);
    assert !(evaluates oldHooks.bunImportConfigHook);
    assert evaluates minimumHooks.bunConfigHook;
    assert evaluates minimumHooks.bunInstallHook;
    assert evaluates minimumHooks.bunImportConfigHook;
    assert evaluates oldHooks.bunRuntimeHook;
    assert evaluates oldHooks.bunBuildHook;
    assert evaluates oldHooks.bunCheckHook;
    assert !(evaluates (oldPackage { }));
    assert
      !(evaluates (oldPackage {
        bunConfigHook = pkgs.emptyDirectory;
      }));
    assert
      !(evaluates (oldPackage {
        bunInstallHook = pkgs.emptyDirectory;
      }));
    assert evaluates (oldPackage {
      bunConfigHook = pkgs.emptyDirectory;
      bunInstallHook = pkgs.emptyDirectory;
    });
    pkgs.runCommand "bun-hook-version-validation" { } "touch $out";

  override-evaluation =
    let
      changed = example.overrideAttrs (_: {
        bunDepsHash = pkgs.lib.fakeHash;
        bunFetchFlags = [ "--test-flag" ];
        bunFlags = [ "--no-env-file" ];
      });
      prepared = example.overrideAttrs (old: {
        src = ./fixtures;
        bunRoot = "basic";
        sourceRoot = "fixtures";
        preUnpack = "echo prepared";
        patchFlags = [ "-p1" ];
        bunFetchFlags = [ "--verbose" ];
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.jq
          pkgs.cmake
        ];
        bunDepsNativeBuildInputs = [ pkgs.jq ];
        bunDepsImpureEnvVars = [ "NIX_BUN_TEST_TOKEN" ];
        env.BUILD_ONLY = "not forwarded";
        buildInputs = [ pkgs.zlib ];
      });
      reused = example.overrideAttrs (_: {
        bunDeps = example.bunDeps;
      });
      alternateBun = pkgs.bun.overrideAttrs (_: {
        version = "1.4.5";
        __intentionallyOverridingVersion = true;
      });
      alternate = example.overrideAttrs (_: {
        bun = alternateBun;
      });
      rebuiltBun = pkgs.bun.overrideAttrs (_: {
        env.NIX_BUN_TEST_VARIANT = "same-version";
      });
      rebuilt = example.overrideAttrs (_: {
        bun = rebuiltBun;
      });
      overriddenHash =
        (pkgs.fetchBunDeps {
          src = ./fixtures/basic;
          hash = example.bunDeps.outputHash;
        }).overrideAttrs
          (_: {
            hash = pkgs.lib.fakeHash;
          });
      scripted = example.overrideAttrs (_: {
        bunRunScripts = true;
      });
      migrating = example.overrideAttrs (_: {
        bunMigrateLockfile = true;
      });
      migrationDisabled = migrating.overrideAttrs (_: {
        bunMigrateLockfile = false;
      });
      migratingFetcher = functionalFetcher.overrideAttrs (_: {
        bunMigrateLockfile = true;
      });
      migrationDisabledFetcher = migratingFetcher.overrideAttrs (_: {
        bunMigrateLockfile = false;
      });
      alternateNodejs = pkgs.nodejs_22;
      alternateNode = example.overrideAttrs (_: {
        runtime = alternateNodejs;
      });
      alternateNodeGypTarget = example.overrideAttrs (_: {
        nodeGypTarget = alternateNodejs;
      });
      changedRuntime = alternateNodeGypTarget.overrideAttrs (_: {
        runtime = pkgs.nodejs;
      });
      customUpdater = example.overrideAttrs (_: {
        passthru = {
          updateScript = "custom-update";
          marker = true;
        };
      });
      replacementHooks = example.overrideAttrs (_: {
        bunConfigHook = pkgs.emptyDirectory;
        bunBuildHook = pkgs.emptyDirectory;
        bunCheckHook = pkgs.emptyDirectory;
        bunInstallHook = pkgs.emptyDirectory;
      });
      noUpdater = pkgs.buildBunPackage {
        pname = "no-updater";
        version = "1";
        passthru.updateScript = null;
      };
      functional = pkgs.buildBunPackage (final: {
        pname = "functional-bun";
        version = "1";
        src = ./fixtures/basic;
        bunDepsHash = example.bunDeps.outputHash;
        bunBuildScript = "build";
      });
      functionalFetcher = pkgs.fetchBunDeps (final: {
        name = "functional-bun-deps";
        src = ./fixtures/basic;
        hash = example.bunDeps.outputHash;
        passthru.selectedHash = final.hash;
      });
      overriddenFunctionalFetcher = functionalFetcher.overrideAttrs (_: {
        hash = pkgs.lib.fakeHash;
      });
    in
    assert example.__structuredAttrs;
    assert functional.__structuredAttrs;
    assert
      !(pkgs.buildBunPackage {
        pname = "unstructured-bun";
        version = "1";
        __structuredAttrs = false;
      }).__structuredAttrs;
    assert alternate.bunDeps.outPath == example.bunDeps.outPath;
    assert alternate.bunDeps.drvPath != example.bunDeps.drvPath;
    assert rebuilt.bunDeps.outPath == example.bunDeps.outPath;
    assert rebuilt.bunDeps.drvPath != example.bunDeps.drvPath;
    assert rebuiltBun.version == pkgs.bun.version;
    assert builtins.elem (toString alternateBun) (map toString alternate.nativeBuildInputs);
    assert builtins.elem (toString alternateBun) (map toString alternate.bunDeps.nativeBuildInputs);
    assert example.runtime == pkgs.bun;
    assert example.nodeGypTarget == pkgs.bun;
    assert alternate.runtime == alternateBun;
    assert alternate.nodeGypTarget == alternateBun;
    assert alternateNode.runtime == alternateNodejs;
    assert alternateNode.nodeGypTarget == alternateNodejs;
    assert alternateNodeGypTarget.runtime == pkgs.bun;
    assert alternateNodeGypTarget.nodeGypTarget == alternateNodejs;
    assert alternateNodeGypTarget.bunDeps.drvPath == example.bunDeps.drvPath;
    assert alternateNodeGypTarget.nativeBuildInputs == example.nativeBuildInputs;
    assert changedRuntime.nodeGypTarget == alternateNodejs;
    assert !(example.bunRunScripts or false);
    assert scripted.bunRunScripts;
    assert scripted.bunDeps.drvPath == example.bunDeps.drvPath;
    assert !example.bunMigrateLockfile;
    assert !example.bunDeps.bunMigrateLockfile;
    assert migrating.bunMigrateLockfile;
    assert migrating.bunDeps.bunMigrateLockfile;
    assert builtins.elem (toString pkgs.bunHooks.bunMigrateHook) (
      map toString migrating.nativeBuildInputs
    );
    assert builtins.elem (toString pkgs.bunHooks.bunFetchMigrateHook) (
      map toString migrating.bunDeps.nativeBuildInputs
    );
    assert
      !(builtins.elem (toString pkgs.bunHooks.bunMigrateHook) (map toString example.nativeBuildInputs));
    assert
      !(builtins.elem (toString pkgs.bunHooks.bunMigrateHook) (
        map toString pkgs.bunHooks.bunConfigHook.propagatedBuildInputs
      ));
    assert migrationDisabled.bunDeps.drvPath == example.bunDeps.drvPath;
    assert migrationDisabled.drvPath == example.drvPath;
    assert migratingFetcher.bunMigrateLockfile;
    assert builtins.elem (toString pkgs.bunHooks.bunFetchMigrateHook) (
      map toString migratingFetcher.nativeBuildInputs
    );
    assert migrationDisabledFetcher.drvPath == functionalFetcher.drvPath;
    assert
      example.updateScript == pkgs.nix-update-script {
        extraArgs = [
          "--custom-dep"
          "bunDeps"
        ];
      };
    assert customUpdater.updateScript == "custom-update";
    assert customUpdater.marker;
    assert noUpdater.updateScript == null;
    assert builtins.elem (toString (pkgs.bunHooks.override { bun = alternateBun; }).bunInstallHook) (
      map toString alternate.nativeBuildInputs
    );
    assert
      builtins.length (
        builtins.filter (
          input: toString input == toString pkgs.emptyDirectory
        ) replacementHooks.nativeBuildInputs
      ) == 4;
    assert overriddenHash.outputHash == pkgs.lib.fakeHash;
    assert changed.bunDeps.bunFlags == [ "--no-env-file" ];
    assert changed.bunDeps.outputHash == pkgs.lib.fakeHash;
    assert changed.bunDeps.drvPath != example.bunDeps.drvPath;
    assert prepared.bunDeps.src == ./fixtures;
    assert prepared.bunDeps.bunRoot == "basic";
    assert prepared.bunDeps.sourceRoot == "fixtures";
    assert !(prepared.bunDeps ? preUnpack);
    assert prepared.bunDeps.patchFlags == [ "-p1" ];
    assert prepared.bunDeps.bunFetchFlags == [ "--verbose" ];
    assert builtins.elem "NIX_BUN_TEST_TOKEN" prepared.bunDeps.impureEnvVars;
    assert !(prepared ? impureEnvVars);
    assert !(prepared.bunDeps ? BUILD_ONLY);
    assert prepared.bunDeps.buildInputs == [ ];
    assert !(builtins.elem (toString pkgs.cmake) (map toString prepared.bunDeps.nativeBuildInputs));
    assert builtins.elem (toString pkgs.jq.dev) (map toString prepared.bunDeps.nativeBuildInputs);
    assert
      !(builtins.elem (toString pkgs.bunHooks.bunConfigHook) (
        map toString prepared.bunDeps.nativeBuildInputs
      ));
    assert reused.bunDeps == example.bunDeps;
    assert functional.bunDeps.outputHash == example.bunDeps.outputHash;
    assert functionalFetcher.outputHash == example.bunDeps.outputHash;
    assert functionalFetcher.selectedHash == example.bunDeps.outputHash;
    assert overriddenFunctionalFetcher.outputHash == pkgs.lib.fakeHash;
    assert overriddenFunctionalFetcher.selectedHash == pkgs.lib.fakeHash;
    assert builtins.elem (toString pkgs.writableTmpDirAsHomeHook) (
      map toString functionalFetcher.nativeBuildInputs
    );
    assert
      !(builtins.elem (toString pkgs.bunHooks.bunFetchMigrateHook) (
        map toString functionalFetcher.nativeBuildInputs
      ));
    pkgs.runCommand "bun-override-evaluation" { } "touch $out";
}
