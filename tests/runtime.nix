{ pkgs, example }:
let
  runtimeExample = example.overrideAttrs (
    final: _old: {
      postPatch = ''
        bun -e '
          const fs = require("fs");
          const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
          pkg.scripts.build = "node ./check-build-runtime.cjs && " + pkg.scripts.build;
          fs.writeFileSync("package.json", JSON.stringify(pkg));
        '
        cat > check-build-runtime.cjs <<'JS'
        if (Boolean(process.versions.bun) !== ${builtins.toJSON (final.nodejs == null)}) {
          throw new Error("bun run used the wrong build runtime");
        }
        JS
      '';
      postBuild = ''
        cat > dist/cli.js <<'JS'
        const isOdd = require("is-odd");
        if (process.argv[2] === "--runtime") {
          if (process.env.RUNTIME_WRAPPER_TEST !== "enabled") throw new Error("missing wrapper argument");
          console.log(process.execPath);
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
        test "$("$out/bin/bun-example" --runtime)" = "$(realpath '${pkgs.lib.getExe final.bunRuntime}')"
        test "$("$out/bin/bun-example" 3)" = odd
      '';
    }
  );
in
{
  bun-runtime = runtimeExample;
  node-runtime = runtimeExample.overrideAttrs (_: {
    bunRuntime = pkgs.nodejs_22;
    # Selecting the installed runtime must leave the build runtime unchanged.
    preBuild = ''test "$(node -p process.versions.bun)" = '${pkgs.bun.version}' '';
  });
  node-runtime-structured = runtimeExample.overrideAttrs (_: {
    bunRuntime = pkgs.nodejs;
    nodejs = pkgs.nodejs;
    __structuredAttrs = true;
    preBuild = "node -e 'if (process.versions.bun) process.exit(1)'";
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
}
