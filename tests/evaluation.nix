{ pkgs, example }:
{
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
      alternateNodejs = pkgs.nodejs_22;
      alternateNode = example.overrideAttrs (_: {
        runtime = alternateNodejs;
      });
      alternateBuildRuntime = example.overrideAttrs (_: {
        buildRuntime = alternateNodejs;
      });
      customUpdater = example.overrideAttrs (_: {
        passthru = {
          updateScript = "custom-update";
          marker = true;
        };
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
    assert example.buildRuntime == pkgs.bun;
    assert alternate.runtime == alternateBun;
    assert alternate.buildRuntime == alternateBun;
    assert alternateNode.runtime == alternateNodejs;
    assert alternateNode.buildRuntime == alternateNodejs;
    assert alternateBuildRuntime.runtime == pkgs.bun;
    assert alternateBuildRuntime.buildRuntime == alternateNodejs;
    assert alternateBuildRuntime.bunDeps.drvPath == example.bunDeps.drvPath;
    assert !example.bunRunScripts;
    assert scripted.bunRunScripts;
    assert scripted.bunDeps.drvPath == example.bunDeps.drvPath;
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
    assert overriddenHash.outputHash == pkgs.lib.fakeHash;
    assert changed.bunDeps.bunFlags == [ "--no-env-file" ];
    assert changed.bunDeps.outputHash == pkgs.lib.fakeHash;
    assert changed.bunDeps.drvPath != example.bunDeps.drvPath;
    assert prepared.bunDeps.src == ./fixtures;
    assert prepared.bunDeps.bunRoot == "basic";
    assert prepared.bunDeps.sourceRoot == "fixtures";
    assert prepared.bunDeps.preUnpack == "echo prepared";
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
    pkgs.runCommand "bun-override-evaluation" { } "touch $out";
}
