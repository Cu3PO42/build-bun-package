{ pkgs }:
let
  # CI must execute the fetcher again when its implementation or inputs change,
  # even when the expected content hash is unchanged and already substituted.
  fetchForTest =
    args:
    pkgs.testers.invalidateFetcherByDrvHash pkgs.fetchBunDeps (
      args
      // {
        postInstall = (args.postInstall or "") + ''
          test ! -e "$out/node_modules"
          if find "$out" -maxdepth 1 -name '*.npm' -print | grep -q .; then
            echo 'fetchBunDeps retained timestamped registry manifests' >&2
            exit 1
          fi
          if find "$out" -type l -lname '/*' -print | grep -q .; then
            echo 'fetchBunDeps retained absolute cache symlinks' >&2
            exit 1
          fi
        '';
      }
    );
  example = pkgs.callPackage ./example.nix { };
  lifecycle-writable = pkgs.buildBunPackage {
    pname = "bun-lifecycle-writable";
    version = "1";
    src = ./fixtures/basic;
    bunDeps = example.bunDeps;
    makeCacheWritable = true;
    nativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq --arg script "node -e \"if (!process.versions.bun) process.exit(1); require('fs').appendFileSync('node_modules/is-odd/index.js', '\\n// lifecycle mutation\\n')\"" '.scripts.postinstall = $script' package.json > package.json.new
      mv package.json.new package.json
    '';
    doInstallCheck = true;
    installCheckPhase = ''grep -q 'lifecycle mutation' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"'';
  };
  native-addon = pkgs.buildBunPackage {
    pname = "bun-native-example";
    version = "1";
    src = ./fixtures/native;
    nativeBuildInputs = [ pkgs.bunNodeGypHook ];
    makeCacheWritable = true;
    bunDepsHash = "sha256-ztFqYwYa7DcpKqupOk7aapedtuBjK628uur9erJwLns=";
    # Both node-gyp and ordinary node commands must run with Bun.
    preBuild = ''
      test "$(node -p process.versions.bun)" = '${pkgs.bun.version}'
      test "$("$npm_config_node_gyp" --version)" = 'v13.1.0'
    '';
    # With local headers, even an unusable download URL must work.
    env.npm_config_disturl = "http://127.0.0.1:9";
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/bun-native-example")" = 42
      test "$(node -p "require('$out/lib/node_modules/bun-native-example/node_modules/native-answer').answer()")" = 42
    '';
  };

  catalogs = pkgs.buildBunPackage {
    pname = "bun-catalog-example";
    version = "1";
    src = ./fixtures/catalogs;
    bunDepsHash = "sha256-s318Wt8d+fBK6qijgUNG5sTN5LC0d9Cu6D5/ekVQFXg=";
    bunWorkspace = "apps/cli";
    makeCacheWritable = true;
    doInstallCheck = true;
    installCheckPhase = ''
      cd "$TMPDIR"
      rm -rf "$NIX_BUILD_TOP/catalogs"
      test "$("$out/bin/workspace-cli")" = 'catalogs work'
    '';
  };

  workspace = pkgs.buildBunPackage {
    pname = "bun-workspace-example";
    version = "1.0.0";
    src = ./fixtures/workspace;
    bunDepsHash = "sha256-a/YgadTQr130SaPzXwbNMC2Eqwak0VRUboCi/OFcARY=";
    makeCacheWritable = true;
    bunFlags = [ "--silent" ];
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
  inherit example workspace catalogs;

  swagger-typescript-api = pkgs.callPackage ./swagger-typescript-api.nix { };

  node-headers-version = pkgs.bun.tests.node-headers;

  workspace-installed = pkgs.buildBunPackage {
    pname = "bun-workspace-installed";
    version = "1";
    src = ./fixtures/workspace;
    bunDeps = workspace.bunDeps;
    bunWorkspace = "apps/cli";
    makeCacheWritable = true;
    # Root publish selection deliberately excludes workspace sources. Linked
    # packages must be installed independently of this list.
    nativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.files = ["package.json"]' package.json > package.json.new
      mv package.json.new package.json
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/workspace-cli")" = 'workspace works'
      test -f "$out/lib/node_modules/workspace-example/packages/message/index.js"
      test ! -e "$out/lib/node_modules/workspace-example/apps/cli/index.js"
      # Resolve every dependency link after removing the original source tree.
      cd "$TMPDIR"
      rm -rf "$NIX_BUILD_TOP/workspace"
      test "$("$out/bin/workspace-cli")" = 'workspace works'
      while IFS= read -r -d "" link; do test -e "$link"; done < <(find "$out" -type l -print0)
    '';
  };

  workspace-isolated = pkgs.buildBunPackage {
    pname = "bun-workspace-isolated";
    version = "1";
    src = ./fixtures/workspace;
    bunDeps = workspace.bunDeps;
    bunWorkspace = "apps/cli";
    makeCacheWritable = true;
    bunInstallFlags = [ "--linker=isolated" ];
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/workspace-cli")" = 'workspace works'
      while IFS= read -r -d "" link; do test -e "$link"; done < <(find "$out" -type l -print0)
    '';
  };

  inherit lifecycle-writable;

  inherit native-addon;

  standalone-node-gyp-hook =
    pkgs.runCommandCC "bun-standalone-node-gyp-hook"
      {
        nativeBuildInputs = [ pkgs.bunNodeGypHook ];
        npm_config_disturl = "http://127.0.0.1:9";
      }
      ''
        cp -R ${./fixtures/native/native} project
        chmod -R u+w project
        cd project
        cat > binding.gyp <<'JSON'
        {
          "targets": [{
            "target_name": "answer",
            "sources": ["answer.c"],
            "defines": ["NIX_BUN_NODE_FALLBACK=<!(node -p 'process.versions.bun ? 1 : 0')"]
          }]
        }
        JSON
        cat >> answer.c <<'C'
        #if NIX_BUN_NODE_FALLBACK != 1
        #error The gyp command must use Bun as node
        #endif
        C
        test "$(node -p process.versions.bun)" = '${pkgs.bun.version}'
        node-gyp rebuild
        test "$(bun -p 'require("./build/Release/answer.node").answer()')" = 42
        mkdir -p "$out"
        cp build/Release/answer.node "$out/"
      '';

  native-node-compatibility =
    pkgs.runCommand "bun-native-node-compatibility"
      {
        nativeBuildInputs = [ pkgs.nodejs ];
      }
      ''
        # Node is a consumer of the finished addon, not part of its build toolchain.
        node -e 'if (process.versions.bun) process.exit(1)'
        test "$(node -p "require('${native-addon}/lib/node_modules/bun-native-example/node_modules/native-answer').answer()")" = 42
        touch "$out"
      '';

  node-free-closures =
    let
      pure = pkgs.closureInfo {
        rootPaths = [ example ];
      };
      native = pkgs.closureInfo {
        rootPaths = [
          native-addon
          pkgs.bunNodeGyp
        ];
      };
    in
    pkgs.runCommand "bun-node-free-closures" { } ''
      if grep -E -- '-(nodejs(-slim)?|npm)-[0-9]' ${pure}/store-paths ${native}/store-paths; then
        echo 'Bun runtime closures unexpectedly depend on Node.js or npm' >&2
        exit 1
      fi
      if grep -E -- '-(bun-node-gyp|node-gyp)-[0-9]' ${pure}/store-paths; then
        echo 'Ordinary Bun projects unexpectedly depend on node-gyp' >&2
        exit 1
      fi
      touch "$out"
    '';

  native-explicit-install = native-addon.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    postPatch = ''
      jq '.scripts.install = "node-gyp rebuild && touch built-by-script"' native/package.json > native/package.json.new
      mv native/package.json.new native/package.json
    '';
    postInstallCheck = ''
      test -f "$out/lib/node_modules/bun-native-example/node_modules/native-answer/built-by-script"
    '';
  });

  native-untrusted = native-addon.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    postPatch = ''
      jq '.trustedDependencies = []' package.json > package.json.new
      mv package.json.new package.json
    '';
    dontBunBuild = true;
    installPhase = ''
      test ! -e node_modules/native-answer/build/Release/answer.node
      mkdir -p "$out"
    '';
    doInstallCheck = false;
  });

  lifecycle-shebangs = example.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    bunInstallFlags = [ ];
    makeCacheWritable = true;
    postPatch = ''
      jq '.scripts.postinstall = "node_modules/is-odd/index.js"' package.json > package.json.new
      mv package.json.new package.json
    '';
    preBunInstall = ''
      script=$(find "$BUN_INSTALL_CACHE_DIR" -type f -path '*/is-odd@*/index.js')
      test -n "$script"
      sed -i '1i #!/missing/interpreter/node' "$script"
      chmod u+x "$script"
      patchShebangs "$BUN_INSTALL_CACHE_DIR"
    '';
    postBunInstall = ''
      test -x node_modules/is-odd/index.js
      touch lifecycle-installed
    '';
    postInstallCheck = ''
      test -f lifecycle-installed
    '';
  });

  trusted-lifecycle = pkgs.buildBunPackage {
    pname = "bun-trusted-lifecycle";
    version = "1";
    src = ./fixtures/trusted;
    bunDepsHash = "sha256-yp69Jks7nsEvClpdP31p6UfQbxofhf/ASkSkckPjeyw=";
    makeCacheWritable = true;
    doInstallCheck = true;
    installCheckPhase = ''grep -q 'trusted dependency script' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"'';
  };

  git-tarball-registry = pkgs.buildBunPackage {
    pname = "bun-source-fixture";
    version = "1";
    src = ./fixtures/sources;
    bunDepsHash = "sha256-B+0r5+hD3LZfcm6pg6hMO+BREOCIRkPzokUqdoae6CU=";
    bunInstallFlags = [ "--ignore-scripts" ];
    nativeBuildInputs = [ pkgs.git ];
    dontBunBuild = true;
    installPhase = ''
      bun -e "if (!require('is-number')('3') || !require('is-odd')(3) || !require('is-even')(4)) process.exit(1)"
      mkdir -p "$out"
      cp -R node_modules "$out/"
    '';
  };

  bundled-and-unbundled = pkgs.buildBunPackage {
    pname = "bun-bundled-and-unbundled";
    version = "1";
    src = ./fixtures/sources;
    bunDepsHash = "sha256-B+0r5+hD3LZfcm6pg6hMO+BREOCIRkPzokUqdoae6CU=";
    nativeBuildInputs = [
      pkgs.git
      pkgs.jq
    ];
    bunInstallFlags = [ "--ignore-scripts" ];
    dontBunBuild = true;
    postPatch = ''
      jq '.bundledDependencies = ["is-odd"]' package.json > package.json.new
      mv package.json.new package.json
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test -d "$out/lib/node_modules/bun-source-fixture/node_modules/is-odd"
      test -d "$out/lib/node_modules/bun-source-fixture/node_modules/is-even"
      bun -e "if (!require('$out/lib/node_modules/bun-source-fixture/node_modules/is-odd')(3) || !require('$out/lib/node_modules/bun-source-fixture/node_modules/is-even')(4)) process.exit(1)"
    '';
  };

  binary-lock = pkgs.buildBunPackage {
    pname = "bun-binary-lock";
    version = "1";
    src = ./fixtures/binary-lock;
    bunDepsHash = "sha256-0IQeLWkQYpK0HHHblh/E1r4iEfC4ATzQUEUYLauR5U4=";
    bunInstallFlags = [ "--ignore-scripts" ];
    doInstallCheck = true;
    installCheckPhase = ''test "$("$out/bin/bun-example" 3)" = odd'';
  };

  patched-dependency = pkgs.buildBunPackage {
    pname = "bun-patched-dependency";
    version = "1";
    src = ./fixtures/patched;
    bunDepsHash = "sha256-lT7chnHqWem8M+vLBqBTJLvbtpSoGs/D1KQMB1Zne3Y=";
    makeCacheWritable = true;
    bunInstallFlags = [ "--ignore-scripts" ];
    doInstallCheck = true;
    installCheckPhase = ''grep -q 'patched by fixture' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"'';
  };

  output-isolation = example.overrideAttrs (old: {
    disallowedReferences = [ old.bunDeps ];
    postInstallCheck = ''
      if find "$out" -type l -lname "$TMPDIR/*" -print | grep -q .; then
        echo "output contains a temporary-directory symlink" >&2
        exit 1
      fi
    '';
  });

  writable-cache = example.overrideAttrs (_: {
    makeCacheWritable = true;
  });

  custom-configure = example.overrideAttrs (_: {
    configurePhase = ''
      test -d node_modules/is-odd
      test "$BUN_INSTALL_GLOBAL_STORE" = 0
    '';
  });

  node-fallback =
    pkgs.runCommand "bun-node-fallback"
      {
        nativeBuildInputs = [ pkgs.bunHooks.bunBuildHook ];
      }
      ''
        test "$(node -p process.versions.bun)" = '${pkgs.bun.version}'
        mkdir -p "$out/bin"
        cat > "$out/bin/node-script" <<'JS'
        #!/usr/bin/env node
        console.log(process.versions.bun);
        JS
        chmod +x "$out/bin/node-script"
        patchShebangs "$out/bin"
        grep -F '${pkgs.bunHooks.bunNodeShim}/bin/node' "$out/bin/node-script"
        test "$("$out/bin/node-script")" = '${pkgs.bun.version}'
      '';

  real-node-precedence =
    pkgs.runCommand "bun-real-node-precedence"
      {
        nativeBuildInputs = [
          pkgs.bunHooks.bunBuildHook
          pkgs.nodejs
        ];
      }
      ''
        test "$(command -v node)" = '${pkgs.nodejs}/bin/node'
        node -e 'if (process.versions.bun) process.exit(1)'
        touch "$out"
      '';

  independent-hooks = pkgs.stdenv.mkDerivation {
    pname = "bun-independent-hooks";
    version = "1";
    src = ./fixtures/basic;
    bunDeps = example.bunDeps;
    bunInstallFlags = [ "--ignore-scripts" ];
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
      bunInstallFlags = [ "--ignore-scripts" ];
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
        sed 's/sha512-/sha512-A/' bun.lock > bun.lock.changed
        mv bun.lock.changed bun.lock
        (bunConfigHook) > "$TMPDIR/lock.log" 2>&1 && exit 1
        grep -q 'lockfile differs from cache' "$TMPDIR/lock.log"
        cp ${./fixtures/basic/bun.lock} bun.lock
        find "$bunDeps" -mindepth 1 -maxdepth 1 ! -name .nix-bun -exec rm -r {} +
        (bunConfigHook) > "$TMPDIR/missing.log" 2>&1 && exit 1
        grep -q 'offline install failed' "$TMPDIR/missing.log"
        mv bun.lock bun.lock.text
        cp ${./fixtures/binary-lock/bun.lockb} bun.lockb
        chmod u+w bun.lockb
        cp ${./fixtures/binary-lock/bun.lockb} "$bunDeps/.nix-bun/bun.lockb"
        printf '\001' >> bun.lockb
        (bunConfigHook) > "$TMPDIR/binary.log" 2>&1 && exit 1
        grep -q 'lockfile differs from cache' "$TMPDIR/binary.log"
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
        bunFlags = [ "--no-env-file" ];
      });
      prepared = example.overrideAttrs (old: {
        src = ./fixtures;
        bunRoot = "basic";
        sourceRoot = "fixtures";
        preUnpack = "echo prepared";
        patchFlags = [ "-p1" ];
        bunFetchFlags = [ "--verbose" ];
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
        env.PREPARATION_TEST = "forwarded";
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
      alternateNodejs = pkgs.nodejs_22;
      alternateNode = example.overrideAttrs (_: {
        nodejs = alternateNodejs;
      });
      functional = pkgs.buildBunPackage (final: {
        pname = "functional-bun";
        version = "1";
        src = ./fixtures/basic;
        bunDepsHash = example.bunDeps.outputHash;
        bunBuildScript = "build";
      });
    in
    assert alternate.bunDeps.outPath != example.bunDeps.outPath;
    assert rebuilt.bunDeps.outPath != example.bunDeps.outPath;
    assert rebuiltBun.version == pkgs.bun.version;
    assert builtins.elem (toString alternateBun) (map toString alternate.nativeBuildInputs);
    assert builtins.elem (toString alternateBun) (map toString alternate.bunDeps.nativeBuildInputs);
    assert builtins.elem (toString alternateNodejs) (map toString alternateNode.nativeBuildInputs);
    assert example.nodejs == null;
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
    assert prepared.bunDeps.PREPARATION_TEST == "forwarded";
    assert builtins.elem (toString pkgs.jq.dev) (map toString prepared.bunDeps.nativeBuildInputs);
    assert
      !(builtins.elem (toString pkgs.bunHooks.bunConfigHook) (
        map toString prepared.bunDeps.nativeBuildInputs
      ));
    assert reused.bunDeps == example.bunDeps;
    assert functional.bunDeps.outputHash == example.bunDeps.outputHash;
    pkgs.runCommand "bun-override-evaluation" { } "touch $out";

  # Different output names force each platform to fetch its own cache rather
  # than reuse a fixed-output path already produced on another platform.
  dependency-cache = fetchForTest {
    name = "bun-example-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/basic;
    hash = example.bunDeps.outputHash;
  };

  fetcher-lock-drift = pkgs.testers.testBuildFailure' {
    drv =
      (pkgs.fetchBunDeps {
        name = "bun-fetch-lock-drift";
        src = ./fixtures/native;
        nativeBuildInputs = [ pkgs.jq ];
        postPatch = ''
          jq 'del(.dependencies["native-answer"])' package.json > package.json.new
          mv package.json.new package.json
        '';
      }).overrideAttrs
        (_: {
          # The expected-failure wrapper writes logs, not a dependency cache.
          outputHash = null;
          outputHashAlgo = null;
          outputHashMode = null;
        });
    expectedBuilderLogEntries = [ "lockfile is frozen" ];
  };

  fetcher-overrides =
    (fetchForTest {
      name = "bun-overridden-fetch-${pkgs.stdenv.hostPlatform.system}";
      src = ./fixtures;
      bunRoot = "missing";
      bunFlags = [ "--invalid-original-flag" ];
      bunFetchFlags = [ "--invalid-original-fetch-flag" ];
      hash = example.bunDeps.outputHash;
    }).overrideAttrs
      (_: {
        bunRoot = "basic";
        bunFlags = [ "--no-env-file" ];
        bunFetchFlags = [
          "--silent"
          "--config"
          "config with spaces.toml"
        ];
        postPatch = ''
          touch 'basic/config with spaces.toml'
        '';
        preInstall = ''
          # Standard hooks must run once, not both inline and through runHook.
          test ! -e "$TMPDIR/fetcher-pre-install-ran"
          touch "$TMPDIR/fetcher-pre-install-ran"
        '';
      });

  node-gyp-dependency-cache = fetchForTest {
    name = "bun-node-gyp-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ../node-gyp;
    hash = pkgs.bunNodeGyp.bunDeps.outputHash;
  };

  catalog-dependency-cache = fetchForTest {
    name = "bun-catalog-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/catalogs;
    hash = catalogs.bunDeps.outputHash;
  };

  patched-dependency-cache = fetchForTest {
    name = "bun-patched-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/patched;
    hash = "sha256-lT7chnHqWem8M+vLBqBTJLvbtpSoGs/D1KQMB1Zne3Y=";
  };

  binary-dependency-cache = fetchForTest {
    name = "bun-binary-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/binary-lock;
    hash = "sha256-0IQeLWkQYpK0HHHblh/E1r4iEfC4ATzQUEUYLauR5U4=";
  };

  source-dependency-cache = fetchForTest {
    name = "bun-source-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/sources;
    nativeBuildInputs = [ pkgs.git ];
    hash = "sha256-B+0r5+hD3LZfcm6pg6hMO+BREOCIRkPzokUqdoae6CU=";
  };

  workspace-dependency-cache = fetchForTest {
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
