{ pkgs, example }:
let
  native-addon = pkgs.buildBunPackage (
    finalAttrs:
    let
      buildNode = finalAttrs.passthru.expectedBuildNode or finalAttrs.runtime;
      targetHeaders =
        if pkgs.lib.getName finalAttrs.nodeGypTarget == "bun" then
          finalAttrs.nodeGypTarget.nodeHeaders or pkgs.bunNodeHeaders
        else
          pkgs.srcOnly finalAttrs.nodeGypTarget;
    in
    {
      pname = "bun-native-example";
      version = "1";
      src = ./fixtures/native;
      nodeGyp = true;
      bunRunScripts = true;
      bunBuildFlags = pkgs.lib.optionals (pkgs.lib.getName finalAttrs.runtime != "bun") [
        "--target=node"
        "--format=cjs"
      ];
      bunDepsHash = "sha256-TU9oKkzKK4Pq10Xfs0qljTGljgErGbewPjbGQSyZx/s=";
      preBuild = ''
        test "$(node -p process.execPath)" = "$(realpath '${pkgs.lib.getExe buildNode}')"
        test "$("$npm_config_node_gyp" --version)" = 'v13.1.0'
        grep -F 'exec node ' "$npm_config_node_gyp"
        test "$npm_config_target" = '${targetHeaders.version}'
        test "$npm_config_nodedir" = '${targetHeaders}'
        grep -F "$npm_config_nodedir/" node_modules/native-answer/build/answer.target.mk
        test "$(node -p "require('native-answer').answer()")" = 42
      '';
      # With local headers, even an unusable download URL must work.
      env.npm_config_disturl = "http://127.0.0.1:9";
      doInstallCheck = true;
      installCheckPhase = ''
        test "$("$out/bin/bun-native-example")" = 42
        test "$(${pkgs.lib.getExe finalAttrs.runtime} -p "require('$out/lib/node_modules/bun-native-example/node_modules/native-answer').answer()")" = 42
      '';
    }
  );
in
{
  node-headers-version = pkgs.bun.tests.node-headers;

  inherit native-addon;

  standalone-node-gyp-hook =
    pkgs.runCommandCC "bun-standalone-node-gyp-hook"
      {
        nativeBuildInputs = [ pkgs.bunHooks.bunNodeGypHook ];
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

  native-node-gyp = native-addon.overrideAttrs (_: {
    runtime = pkgs.nodejs;
  });

  native-bun-runtime-node-build = native-addon.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.nodejs_22 ];
    passthru.expectedBuildNode = pkgs.nodejs_22;
  });

  native-node-runtime-alternate-node-build = native-addon.overrideAttrs (old: {
    runtime = pkgs.nodejs_22;
    nativeBuildInputs = [ pkgs.nodejs ] ++ old.nativeBuildInputs;
    passthru.expectedBuildNode = pkgs.nodejs;
  });

  native-build-target = native-addon.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.nodejs_22 ];
    passthru.expectedBuildNode = pkgs.nodejs_22;
    nodeGypTarget = pkgs.nodejs_22;
  });

  native-bun-target-node-runtime = native-addon.overrideAttrs (_: {
    runtime = pkgs.nodejs_22;
    nodeGypTarget = pkgs.bun;
  });

  # Different header releases can still produce a compatible Node-API addon.
  native-attached-headers = native-addon.overrideAttrs (_: {
    nodeGypTarget = pkgs.bun.overrideAttrs (old: {
      passthru = old.passthru // {
        nodeHeaders = pkgs.srcOnly pkgs.nodejs_22;
      };
    });
  });

  node-gyp-header-property =
    let
      hooks = pkgs.bunHooks.override {
        # The target's attached headers take precedence over the fallback.
        bunNodeHeaders = pkgs.bunNodeHeaders // {
          version = "0.0.0";
        };
      };
    in
    pkgs.runCommand "bun-node-gyp-header-property" { nativeBuildInputs = [ hooks.bunNodeGypHook ]; } ''
      test "$npm_config_nodedir" = '${pkgs.bun.nodeHeaders}'
      test "$npm_config_target" = '${pkgs.bun.nodeHeaders.version}'
      bunCheckNodeGypHeaders 2> warning
      test ! -s warning
      touch "$out"
    '';

  node-gyp-fallback-header-warning =
    let
      hooks = pkgs.bunHooks.override {
        nodeGypTarget = builtins.removeAttrs pkgs.bun [ "nodeHeaders" ];
        bunNodeHeaders = pkgs.bunNodeHeaders // {
          version = "0.0.0";
        };
      };
    in
    pkgs.runCommand "bun-node-gyp-fallback-header-warning"
      { nativeBuildInputs = [ hooks.bunNodeGypHook ]; }
      ''
        test "$npm_config_nodedir" = '${pkgs.bunNodeHeaders}'
        test "$npm_config_target" = '0.0.0'
        bunCheckNodeGypHeaders 2> warning
        actual=$(${pkgs.lib.getExe pkgs.bun} -p process.versions.node)
        grep -F "target Bun reports Node $actual" warning
        grep -F 'provides Node 0.0.0 headers' warning
        grep -F '${pkgs.bunNodeHeaders}' warning
        node-gyp --version
        touch "$out"
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
    bunDepsNativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.scripts.install = "node-gyp rebuild && touch built-by-script"' native/package.json > native/package.json.new
      mv native/package.json.new native/package.json
    '';
    postInstallCheck = ''
      test -f "$out/lib/node_modules/bun-native-example/node_modules/native-answer/built-by-script"
    '';
  });

  # Install without scripts, then compile only the explicitly chosen addon
  # after bunConfigHook has patched the installed dependency shebangs.
  native-manual-install = native-addon.overrideAttrs (_: {
    bunRunScripts = false;
    postBunInstall = ''
      test ! -e node_modules/native-answer/build/Release/answer.node
      (
        cd node_modules/native-answer
        node-gyp rebuild
      )
    '';
  });

  native-untrusted = native-addon.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    bunDepsNativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.trustedDependencies = []' package.json > package.json.new
      mv package.json.new package.json
    '';
    dontBunBuild = true;
    # This case deliberately leaves the addon unbuilt.
    preBuild = "";
    installPhase = ''
      test ! -e node_modules/native-answer/build/Release/answer.node
      mkdir -p "$out"
    '';
    doInstallCheck = false;
  });
}
