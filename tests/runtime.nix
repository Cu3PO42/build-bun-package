{ pkgs, example }:
let
  runtimeExample = example.overrideAttrs (
    final: _old:
    let
      buildNode = final.passthru.expectedBuildNode or final.runtime;
    in
    {
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
        const expected = require("fs").realpathSync("${pkgs.lib.getExe buildNode}");
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
        test "$(node_modules/is-odd/runtime-helper)" = "$(realpath '${pkgs.lib.getExe buildNode}')"
        sed '1c\#!/usr/bin/env -S node --no-deprecation' node_modules/is-odd/runtime-helper > node_modules/is-odd/runtime-helper-split
        chmod +x node_modules/is-odd/runtime-helper-split
        patchShebangs node_modules/is-odd/runtime-helper-split
        test "$(node_modules/is-odd/runtime-helper-split)" = "$(realpath '${pkgs.lib.getExe buildNode}')"
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
        helper=node_modules/is-odd/runtime-helper
        sed '1c\#!/usr/bin/env node' "$helper" > "$helper-generated"
        sed '1c\#!/usr/bin/env -S node --no-deprecation' "$helper" > "$helper-generated-split"
        sed '1c\#!${pkgs.lib.getExe pkgs.nodejs}' "$helper" > "$helper-pinned"
        sed '1c\#!${pkgs.lib.getExe pkgs.bun}' "$helper" > "$helper-bun"
        chmod +x "$helper-"*
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
        helper="$out/lib/node_modules/bun-example/node_modules/is-odd/runtime-helper"
        test "$("$helper-generated")" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
        test "$("$helper-generated-split")" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
        grep -q -- ' --no-deprecation$' "$helper-split"
        grep -q -- ' --no-deprecation$' "$helper-generated-split"
        test "$("$helper-pinned")" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
        test "$("$helper-bun")" = "$(realpath '${pkgs.lib.getExe pkgs.bun}')"
      '';
    }
  );
in
{
  bun-runtime = runtimeExample;
  node-runtime = runtimeExample.overrideAttrs (_: {
    runtime = pkgs.nodejs_22;
  });
  bun-runtime-node-build = runtimeExample.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.nodejs_22 ];
    passthru.expectedBuildNode = pkgs.nodejs_22;
    disallowedReferences = [ pkgs.nodejs_22 ];
  });
  node-runtime-alternate-node-build = runtimeExample.overrideAttrs (old: {
    runtime = pkgs.nodejs_22;
    nativeBuildInputs = [ pkgs.nodejs ] ++ old.nativeBuildInputs;
    passthru.expectedBuildNode = pkgs.nodejs;
  });
  node-runtime-structured = runtimeExample.overrideAttrs (_: {
    runtime = pkgs.nodejs;
    __structuredAttrs = true;
  });

  custom-install-runtimes = runtimeExample.overrideAttrs (
    final: old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.nodejs_22 ];
      passthru.expectedBuildNode = pkgs.nodejs_22;
      outputs = [
        "out"
        "dev"
      ];
      outputChecks.out.disallowedReferences = [ pkgs.nodejs_22 ];
      installPhase = ''
        mkdir -p "$out/custom scripts" "$dev/bin"
        cp node_modules/is-odd/runtime-helper* "$out/custom scripts/"
        cp node_modules/is-odd/runtime-helper* "$dev/bin/"
      '';
      installCheckPhase = ''
        sourceTree=$PWD
        cd "$TMPDIR"
        rm -rf "$sourceTree"
        for helper in runtime-helper runtime-helper-split runtime-helper-generated runtime-helper-generated-split; do
          test "$("$out/custom scripts/$helper")" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
          test "$("$dev/bin/$helper")" = "$(realpath '${pkgs.lib.getExe pkgs.nodejs_22}')"
        done
        test "$("$out/custom scripts/runtime-helper-pinned")" = "$(realpath '${pkgs.lib.getExe final.runtime}')"
        test "$("$out/custom scripts/runtime-helper-bun")" = "$(realpath '${pkgs.lib.getExe pkgs.bun}')"
      '';
      postInstallCheck = "";
    }
  );

  static-output-no-runtime = example.overrideAttrs (_: {
    dontBunBuild = true;
    doCheck = false;
    installPhase = ''
      mkdir -p "$out"
      cp package.json "$out/manifest.json"
    '';
    installCheckPhase = ''test -f "$out/manifest.json"'';
    disallowedReferences = [ pkgs.bun ];
  });

  runtime-hook = pkgs.stdenvNoCC.mkDerivation {
    name = "bun-runtime-hook-test";
    nativeBuildInputs = [ pkgs.bunHooks.bunRuntimeHook ];
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      test "$(node -p process.versions.bun)" = '${pkgs.bun.version}'
      mkdir -p "$out/bin"
      cat > "$out/bin/node-script" <<'JS'
      #!/usr/bin/env node
      console.log(process.versions.bun);
      JS
      chmod +x "$out/bin/node-script"
      patchShebangs "$out/bin"
      test "$("$out/bin/node-script")" = '${pkgs.bun.version}'
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/node-script")" = '${pkgs.bun.version}'
    '';
  };

  runtime-fixup-disabled = pkgs.stdenvNoCC.mkDerivation {
    name = "bun-runtime-fixup-disabled";
    nativeBuildInputs = [
      pkgs.bunHooks.bunRuntimeHook
      pkgs.nodejs_22
    ];
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontPatchShebangs = true;
    installPhase = ''
      mkdir -p "$out/bin"
      cat > "$out/bin/node-script" <<'JS'
      #!/usr/bin/env node
      console.log(process.execPath);
      JS
      sed '1c\#!/usr/bin/env -S node --no-deprecation' "$out/bin/node-script" > "$out/bin/node-script-split"
      chmod +x "$out/bin/"*
      # Explicit build-time patching is allowed; automatic output fixup is not.
      patchShebangs --build "$out/bin"
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      for script in "$out/bin/"*; do
        test "$("$script")" = "$(realpath '${pkgs.lib.getExe pkgs.nodejs_22}')"
      done
    '';
  };

  explicit-node-precedence =
    pkgs.runCommand "bun-explicit-node-precedence"
      {
        nativeBuildInputs = [
          pkgs.bunHooks.bunBuildHook
          pkgs.nodejs
        ];
      }
      ''
        node -e 'if (process.versions.bun) process.exit(1)'
        touch "$out"
      '';
}
