{ pkgs }:
let
  example = pkgs.callPackage ./example.nix { };
  workspace = pkgs.buildBunPackage {
    pname = "bun-workspace-example";
    version = "1.0.0";
    src = ./fixtures/workspace;
    bunDepsHash = "sha256-a/YgadTQr130SaPzXwbNMC2Eqwak0VRUboCi/OFcARY=";
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share"
      cp dist/index.js "$out/share/workspace.js"
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$(bun "$out/share/workspace.js")" = 'workspace works'
    '';
  };
in
{
  inherit example workspace;

  writable-cache = example.overrideAttrs (_: {
    makeCacheWritable = true;
  });

  custom-configure = example.overrideAttrs (_: {
    configurePhase = ''
      test -d node_modules/is-odd
      test "$BUN_INSTALL_GLOBAL_STORE" = 0
    '';
  });

  independent-hooks = pkgs.stdenv.mkDerivation {
    pname = "bun-independent-hooks";
    version = "1";
    src = ./fixtures/basic;
    bunDeps = example.bunDeps;
    bunInstallFlags = [ "--ignore-scripts" ];
    bunBuildScript = "build";
    nativeBuildInputs = [
      pkgs.bun
      pkgs.bunHooks.bunConfigHook
      pkgs.bunHooks.bunBuildHook
      pkgs.bunHooks.bunInstallHook
    ];
    doInstallCheck = true;
    installCheckPhase = ''test "$("$out/bin/bun-example" 3)" = odd'';
  };

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
      bunInstallFlags = [ "--ignore-scripts" ];
      bunBuildHook = replacement;
      doInstallCheck = true;
      installCheckPhase = "test -f replacement-ran";
    };

  scoped-bundled-manual = pkgs.buildBunPackage {
    pname = "scoped-bundled-manual";
    version = "1";
    src = ./fixtures/basic;
    bunDeps = example.bunDeps;
    bunInstallFlags = [ "--ignore-scripts" ];
    makeWrapperArgs = [
      "--set"
      "BUN_TEST_WRAPPER"
      "enabled"
    ];
    nativeBuildInputs = [ pkgs.jq ];
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

  cache-validation =
    pkgs.runCommand "bun-cache-validation"
      {
        nativeBuildInputs = [
          pkgs.bun
          pkgs.bunHooks.bunConfigHook
        ];
      }
      ''
        cp -R ${./fixtures/basic} project
        chmod -R u+w project
        cd project
        cp -R ${example.bunDeps} "$TMPDIR/cache"
        chmod -R u+w "$TMPDIR/cache"
        export bunDeps="$TMPDIR/cache" bunInstallFlags="--ignore-scripts"
        printf '2\n' > "$bunDeps/.nix-bun/format-version"
        (bunConfigHook) > "$TMPDIR/version.log" 2>&1 && exit 1
        grep -q 'incompatible or missing cache metadata' "$TMPDIR/version.log"
        printf '1\n' > "$bunDeps/.nix-bun/format-version"
        printf 'changed' >> bun.lock
        (bunConfigHook) > "$TMPDIR/lock.log" 2>&1 && exit 1
        grep -q 'lockfile differs from cache' "$TMPDIR/lock.log"
        touch "$out"
      '';

  cache-contract = pkgs.runCommand "bun-cache-contract" { } ''
    test "$(cat ${example.bunDeps}/.nix-bun/format-version)" = 1
    cmp ${example.bunDeps}/.nix-bun/bun.lock ${./fixtures/basic/bun.lock}
    touch "$out"
  '';

  override-evaluation =
    let
      changed = example.overrideAttrs (_: {
        bunDepsHash = pkgs.lib.fakeHash;
        bunFetchFlags = [ "--test-flag" ];
      });
      reused = example.overrideAttrs (_: {
        bunDeps = example.bunDeps;
      });
      functional = pkgs.buildBunPackage (final: {
        pname = "functional-bun";
        version = "1";
        src = ./fixtures/basic;
        bunDepsHash = example.bunDeps.outputHash;
        bunBuildScript = "build";
      });
    in
    assert changed.bunDeps.outputHash == pkgs.lib.fakeHash;
    assert changed.bunDeps.drvPath != example.bunDeps.drvPath;
    assert reused.bunDeps == example.bunDeps;
    assert functional.bunDeps.outputHash == example.bunDeps.outputHash;
    pkgs.runCommand "bun-override-evaluation" { } "touch $out";

  # Different output names force each platform to fetch its own cache rather
  # than reuse a fixed-output path already produced on another platform.
  dependency-cache = pkgs.fetchBunDeps {
    name = "bun-example-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/basic;
    hash = example.bunDeps.outputHash;
  };

  workspace-dependency-cache = pkgs.fetchBunDeps {
    name = "bun-workspace-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/workspace;
    hash = workspace.bunDeps.outputHash;
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

  offline-failures =
    pkgs.runCommand "bun-offline-failures"
      {
        nativeBuildInputs = [
          pkgs.bun
          pkgs.jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        export BUN_INSTALL_CACHE_DIR="$TMPDIR/cache"
        mkdir -p "$HOME" project
        cp ${./fixtures/basic}/{package.json,bun.lock} project/
        chmod -R u+w project
        cd project
        mkdir -p "$BUN_INSTALL_CACHE_DIR"
        cp -R ${example.bunDeps}/. "$BUN_INSTALL_CACHE_DIR/"
        chmod -R u+w "$BUN_INSTALL_CACHE_DIR"

        # An empty cache must fail immediately, instead of falling back to HTTP.
        BUN_INSTALL_CACHE_DIR="$TMPDIR/empty" \
          bun install --offline --frozen-lockfile --ignore-scripts >missing.log 2>&1 && exit 1
        cat missing.log
        test ! -d node_modules/is-odd

        jq 'del(.dependencies["is-odd"])' package.json > changed.json
        mv changed.json package.json
        bun install --offline --frozen-lockfile --ignore-scripts >frozen.log 2>&1 && exit 1
        cat frozen.log
        grep -qi 'lockfile.*frozen\|frozen.*lockfile' frozen.log
        touch "$out"
      '';
}
