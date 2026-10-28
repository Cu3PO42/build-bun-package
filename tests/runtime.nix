{ pkgs, example }:
let
  runtimeExample = example.overrideAttrs (
    final: _old: {
      postPatch = ''
        bun -e '
          const fs = require("fs");
          const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
          pkg.scripts.build = "node ./check-build-runtime.cjs && " + pkg.scripts.build;
          pkg.scripts.postinstall = "node ./check-build-runtime.cjs";
          pkg.scripts["check-runtime"] = "node ./check-build-runtime.cjs";
          fs.writeFileSync("package.json", JSON.stringify(pkg));
        '
        cat > check-build-runtime.cjs <<'JS'
        const expected = require("fs").realpathSync("${pkgs.lib.getExe final.buildRuntime}");
        if (process.execPath !== expected) {
          throw new Error("bun run used the wrong build runtime: " + process.execPath);
        }
        JS
      '';
      bunRunScripts = true;
      checkPhase = null;
      bunCheckScript = "check-runtime";
      postBunInstall = ''
        cat > node_modules/is-odd/runtime-helper <<'JS'
        #!/usr/bin/env node
        console.log(process.execPath);
        JS
        chmod +x node_modules/is-odd/runtime-helper
        patchShebangs node_modules/is-odd/runtime-helper
        test "$(node_modules/is-odd/runtime-helper)" = "$(realpath '${pkgs.lib.getExe final.buildRuntime}')"
        sed '1c\#!/usr/bin/env -S node --no-deprecation' node_modules/is-odd/runtime-helper > node_modules/is-odd/runtime-helper-split
        chmod +x node_modules/is-odd/runtime-helper-split
        patchShebangs node_modules/is-odd/runtime-helper-split
        test "$(node_modules/is-odd/runtime-helper-split)" = "$(realpath '${pkgs.lib.getExe final.buildRuntime}')"
      '';
      postBuild = ''
        cat > dist/cli.js <<'JS'
        const isOdd = require("is-odd");
        if (process.argv[2] === "--runtime") {
          if (process.env.RUNTIME_WRAPPER_TEST !== "enabled") throw new Error("missing wrapper argument");
          console.log(process.execPath);
        } else if (process.argv[2] === "--child-runtime") {
          const child = require("child_process").spawnSync("node", ["-p", "process.execPath"], { encoding: "utf8" });
          if (child.status !== 0) throw new Error(child.stderr || "node child failed");
          process.stdout.write(child.stdout);
        } else {
          console.log(isOdd(Number(process.argv[2])) ? "odd" : "even");
        }
        JS
      '';
      makeWrapperArgs = [
        "--set"
        "RUNTIME_WRAPPER_TEST"
        "enabled"
      ];
      postInstallCheck = ''
        cd "$TMPDIR"
        rm -rf "$NIX_BUILD_TOP/basic"
        test "$("$out/bin/bun-example" --runtime)" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
        test "$(PATH=${pkgs.coreutils}/bin "$out/bin/bun-example" --child-runtime)" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
        test "$("$out/bin/bun-example" 3)" = odd
        test "$("$out/lib/node_modules/bun-example/node_modules/is-odd/runtime-helper")" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
        test "$("$out/lib/node_modules/bun-example/node_modules/is-odd/runtime-helper-split")" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
      '';
    }
  );
in
{
  bun-runtime = runtimeExample;
  node-runtime = runtimeExample.overrideAttrs (_: {
    runtime = pkgs.nodejs_22;
  });
  bun-runtime-node-build = runtimeExample.overrideAttrs (_: {
    buildRuntime = pkgs.nodejs_22;
    disallowedReferences = [ pkgs.nodejs_22 ];
  });
  node-runtime-bun-build = runtimeExample.overrideAttrs (_: {
    runtime = pkgs.nodejs_22;
    buildRuntime = pkgs.bun;
  });
  node-runtime-structured = runtimeExample.overrideAttrs (_: {
    runtime = pkgs.nodejs;
    __structuredAttrs = true;
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
        grep -F '${pkgs.bunHooks.buildRuntimeNodeShim}/bin/node' "$out/bin/node-script"
        test "$("$out/bin/node-script")" = '${pkgs.bun.version}'
      '';

  build-runtime-precedence =
    pkgs.runCommand "bun-build-runtime-precedence"
      {
        nativeBuildInputs = [
          pkgs.bunHooks.bunBuildHook
          pkgs.nodejs
        ];
      }
      ''
        test "$(node -p process.versions.bun)" = '${pkgs.bun.version}'
        touch "$out"
      '';
}
