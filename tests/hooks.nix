{ pkgs, example }:
{
  output-isolation = example.overrideAttrs (old: {
    disallowedReferences = [ old.bunDeps ];
    postInstallCheck = ''
      if find "$out" -type l -lname "$TMPDIR/*" -print | grep -q .; then
        echo "output contains a temporary-directory symlink" >&2
        exit 1
      fi
    '';
  });

  custom-configure = example.overrideAttrs (_: {
    configurePhase = ''
      test -d node_modules/is-odd
      test "$BUN_INSTALL_GLOBAL_STORE" = 0
      test "$BUN_INSTALL_CACHE_DIR" = "$bunDeps"
    '';
  });

  independent-hooks = pkgs.stdenv.mkDerivation {
    pname = "bun-independent-hooks";
    version = "1";
    src = ./fixtures/basic;
    bunDeps = example.bunDeps;
    bunBuildScript = "build";
    nativeBuildInputs = [
      pkgs.bunHooks.bunConfigHook
      pkgs.bunHooks.bunBuildHook
      pkgs.bunHooks.bunInstallHook
    ];
    doInstallCheck = true;
    installCheckPhase = ''test "$("$out/bin/bun-example" 3)" = odd'';
  };

  functional-script =
    (pkgs.buildBunPackage (final: {
      pname = "functional-script";
      version = "1";
      src = ./fixtures/basic;
      bunDeps = example.bunDeps;
      bunBuildScript = if final.pname == "functional-script" then "build" else "alternate";
      nativeBuildInputs = [ pkgs.jq ];
      postPatch = ''
        jq '.scripts.alternate = .scripts.build' package.json > package.json.new
        mv package.json.new package.json
      '';
      preBuild = "touch pre-build-ran";
      postBuild = "test -f pre-build-ran && test -f dist/cli.js && touch post-build-ran";
      doInstallCheck = true;
      installCheckPhase = ''
        test -f post-build-ran
        test "$("$out/bin/bun-example" 3)" = odd
      '';
    })).overrideAttrs
      (_: {
        pname = "functional-script-overridden";
        bunBuildFlags = [ "--minify" ];
      });

  structured-flags = example.overrideAttrs (old: {
    __structuredAttrs = true;
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    bunFlags = [
      "--no-env-file"
      "--silent"
    ];
    bunBuildFlags = [
      "argument with spaces"
      "literal *"
    ];
    makeWrapperArgs = [
      "--set"
      "BUN_WRAPPER_TEST"
      "value with spaces"
    ];
    bunDepsNativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.scripts.build = "bun build ./cli.js --target=bun --external=is-odd --outdir=dist && bun ./check-args.js"' package.json > package.json.new
      mv package.json.new package.json
      cat > check-args.js <<'JS'
      const args = process.argv.slice(2);
      if (JSON.stringify(args) !== JSON.stringify(["argument with spaces", "literal *"])) {
        throw new Error(JSON.stringify(args));
      }
      JS
    '';
    postInstallCheck = ''
      grep -q 'value with spaces' "$out/bin/bun-example"
    '';
  });

  replacement-build-hook =
    let
      replacement = pkgs.makeSetupHook { name = "replacement-bun-build"; } (
        pkgs.writeText "replacement-bun-build.sh" ''
          replacementBunBuild() {
            test -d node_modules/is-odd
            bun run build
            touch replacement-ran
          }
          buildPhase=replacementBunBuild
        ''
      );
    in
    pkgs.buildBunPackage {
      pname = "replacement-hook-example";
      version = "1";
      src = ./fixtures/basic;
      bunDeps = example.bunDeps;
      bunBuildHook = replacement;
      doInstallCheck = true;
      installCheckPhase = "test -f replacement-ran";
    };

  scoped-bundled-manual = pkgs.buildBunPackage {
    pname = "scoped-bundled-manual";
    version = "1";
    src = ./fixtures/basic;
    bunDeps = example.bunDeps;
    makeWrapperArgs = [
      "--set"
      "BUN_TEST_WRAPPER"
      "enabled"
    ];
    nativeBuildInputs = [ pkgs.jq ];
    bunDepsNativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.name = "@example/bun-example" | .bin = "dist/cli.js" | .bundledDependencies = ["is-odd"] | .man = ["docs/example.1"] | .files += ["docs"]' package.json > package.json.new
      mv package.json.new package.json
      mkdir docs
      printf '.TH EXAMPLE 1\n' > docs/example.1
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/bun-example" 3)" = odd
      grep -q BUN_TEST_WRAPPER "$out/bin/bun-example"
      test -d "$out/lib/node_modules/@example/bun-example/node_modules/is-odd"
      test -d "$out/lib/node_modules/@example/bun-example/node_modules/is-number"
      test -f "$out/share/man/man1/example.1.gz"
    '';
  };

  keep-dev-dependencies = pkgs.callPackage ./example.nix {
    dontBunPrune = true;
  };

  # Exercise bunRoot and the standard hook/phase override interface without
  # fetching another copy of the same dependency set.
  nested =
    (pkgs.callPackage ./example.nix {
      fixtureSrc = ./fixtures;
      projectRoot = "basic";
      dependencyCache = example.bunDeps;
    }).overrideAttrs
      (old: {
        pname = "bun-nested-example";
        preBuild = ''
          test -f package.json
        '';
        postInstall = ''
          touch "$out/hook-ran"
        '';
        postInstallCheck = ''
          test -f "$out/hook-ran"
        '';
      });
}
