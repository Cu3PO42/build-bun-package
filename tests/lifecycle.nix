{ pkgs, example }:
let
  patched-shebang = pkgs.buildBunPackage {
    pname = "bun-patched-shebang";
    version = "1";
    src = ./fixtures/patched-shebang;
    bunDepsHash = "sha256-DwgcZvc9sTHz6pqx6/4iGAl6ARH7TYMJoHNFbZQrKtg=";
    bunRunScripts = true;
    dontBunBuild = true;
    doInstallCheck = true;
    installCheckPhase = ''
      packageOut="$out/lib/node_modules/patched-shebang"
      test "$(wc -l < "$packageOut/root-lifecycle-runs")" -eq 1
      test "$("$packageOut/node_modules/esbuild/bin/esbuild" --version)" = 0.25.0
      test "$(head -n1 "$bunDeps/esbuild@0.25.0@@@1/bin/esbuild")" = '#!/usr/bin/env node'
      # The final copy install must not leave links into the private cache.
      if find "$out" -type l -lname "$TMPDIR/*" -print | grep -q .; then exit 1; fi
    '';
  };

  lifecycle-writable = pkgs.buildBunPackage {
    pname = "bun-lifecycle-writable";
    version = "1";
    src = ./fixtures/basic;
    bunDeps = example.bunDeps;
    bunRunScripts = true;
    nativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq --arg script "node -e \"if (!process.versions.bun) process.exit(1); require('fs').appendFileSync('node_modules/is-odd/index.js', '\\n// lifecycle mutation\\n')\"" '.scripts.postinstall = $script' package.json > package.json.new
      mv package.json.new package.json
    '';
    doInstallCheck = true;
    installCheckPhase = ''grep -q 'lifecycle mutation' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"'';
  };

  lifecycle-shebangs = example.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    bunRunScripts = true;
    bunDepsNativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.scripts.postinstall = "node_modules/is-odd/index.js"' package.json > package.json.new
      mv package.json.new package.json
    '';
    preBunInstall = ''
      test "$BUN_INSTALL_CACHE_DIR" != "$bunDeps"
      script=$(find "$BUN_INSTALL_CACHE_DIR" -type f -path '*/is-odd@*/index.js')
      test -n "$script"
      sed -i '1i #!/missing/interpreter/node' "$script"
      chmod u+x "$script"
    '';
    postBunInstall = ''
      test -x node_modules/is-odd/index.js
      test "$(head -n1 node_modules/is-odd/index.js)" = "#!$(command -v node)"
      original=$(find "$bunDeps" -type f -path '*/is-odd@*/index.js')
      ! head -n1 "$original" | grep -q '^#!'
      touch lifecycle-installed
    '';
    postInstallCheck = ''
      test -f lifecycle-installed
    '';
  });

  prepared-lifecycle = example.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    bunDeps = example.bunDeps;
    bunRunScripts = true;
    postPatch = (old.postPatch or "") + ''
      cat > check-prepared.cjs <<'JS'
      const fs = require("fs");
      if (!fs.existsSync("preparation-hook-ran")) throw new Error("scripts ran before preparation hook");
      if (fs.existsSync("scripts-ran")) throw new Error("scripts ran twice");
      if (!fs.readFileSync("node_modules/is-odd/index.js", "utf8").includes("prepared-by-hook")) {
        throw new Error("cache edit did not survive reinstall");
      }
      fs.writeFileSync("scripts-ran", "yes");
      JS
      jq '.scripts.postinstall = "node ./check-prepared.cjs"' package.json > package.json.new
      mv package.json.new package.json
    '';
    preBunInstallScripts = ''
      test ! -e scripts-ran
      test ! -e preparation-hook-ran
      test -L node_modules/is-odd/package.json
      prepared=false
      shebangPrepared=false
      for package in "''${bunPreparedCachePackages[@]}"; do
        if [[ $(jq -r .name "$package/package.json") == is-odd ]]; then
          printf '\n// prepared-by-hook\n' >> "$package/index.js"
          prepared=true
        elif [[ $(jq -r .name "$package/package.json") == esbuild ]]; then
          test "$(head -n1 "$package/bin/esbuild")" = "#!$(command -v node)"
          shebangPrepared=true
        fi
      done
      test "$prepared" = true
      test "$shebangPrepared" = true
      touch preparation-hook-ran
    '';
    postBunInstall = ''
      test "$(cat scripts-ran)" = yes
    '';
    installCheckPhase = ''
      test "$("$out/bin/bun-example" 3)" = odd
      grep -q prepared-by-hook "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"
      test -z "$(find "$out" -type l -lname "$TMPDIR/*" -print)"
    '';
  });
in
{
  inherit patched-shebang;

  patched-shebang-isolated = patched-shebang.overrideAttrs (_: {
    bunInstallFlags = [ "--linker=isolated" ];
  });

  patched-shebang-ignore-scripts = patched-shebang.overrideAttrs (_: {
    bunInstallFlags = [ "--ignore-scripts" ];
    installCheckPhase = ''
      packageOut="$out/lib/node_modules/patched-shebang"
      test ! -e "$packageOut/root-lifecycle-runs"
      test "$("$packageOut/node_modules/esbuild/bin/esbuild" --version)" = 0.25.0
    '';
  });

  inherit lifecycle-writable;

  inherit lifecycle-shebangs;

  lifecycle-preparation-hook = prepared-lifecycle;
  lifecycle-preparation-hook-isolated = prepared-lifecycle.overrideAttrs (_: {
    bunInstallFlags = [ "--linker=isolated" ];
  });

  source-shebangs = example.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    bunDeps = example.bunDeps;
    bunRunScripts = true;
    postPatch = ''
      jq '.scripts.postinstall = "./root-helper" | .scripts.build = "./build-helper"' package.json > package.json.new
      mv package.json.new package.json
      # These represent project, workspace, and linked local-package helpers.
      # All must be usable before the final output fixup phase.
      mkdir -p packages/workspace local
      for helper in root-helper packages/workspace/helper local/helper; do
        cat > "$helper" <<'SH'
      #!/missing/interpreter/bash
      printf 'ran\n' >> source-helpers-ran
      SH
        chmod +x "$helper"
      done
      cat >> root-helper <<'SH'
      ./packages/workspace/helper
      ./local/helper
      SH
      cat > build-helper <<'SH'
      #!/missing/interpreter/bash
      test "$(wc -l < source-helpers-ran)" -eq 3
      bun build ./cli.js --target=bun --external=is-odd --outdir=dist
      SH
      chmod +x build-helper
    '';
    preBunInstall = ''
      cp local/helper hook-helper
      printf '\n./hook-helper\n' >> build-helper
    '';
    postBuild = ''test "$(wc -l < source-helpers-ran)" -eq 4'';
  });

  lifecycle-node-shebangs = lifecycle-shebangs.overrideAttrs (_: {
    runtime = pkgs.nodejs;
    makeCacheWritable = false; # Scripts still require a writable copy.
  });

  trusted-lifecycle = pkgs.buildBunPackage {
    pname = "bun-trusted-lifecycle";
    version = "1";
    src = ./fixtures/trusted;
    bunDepsHash = "sha256-c/tAgIcZjlyhDuUMXRHf1etYF9GmEEQiOPR/HdCEXOw=";
    bunRunScripts = true;
    doInstallCheck = true;
    installCheckPhase = ''test "$(grep -c 'trusted dependency script' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js")" -eq 1'';
  };

  lifecycle-disabled = pkgs.buildBunPackage {
    pname = "bun-lifecycle-disabled";
    version = "1";
    src = ./fixtures/trusted;
    bunDepsHash = "sha256-c/tAgIcZjlyhDuUMXRHf1etYF9GmEEQiOPR/HdCEXOw=";
    nativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.scripts.postinstall = "touch root-script-ran"' package.json > package.json.new
      mv package.json.new package.json
    '';
    bunDepsNativeBuildInputs = [ pkgs.jq ];
    makeCacheWritable = true; # Bun's patchedDependencies need cache writes.
    preBunInstallScripts = "exit 1"; # Must not run when bunRunScripts is disabled.
    preBunInstall = ''test "$BUN_INSTALL_CACHE_DIR" != "$bunDeps"'';
    doInstallCheck = true;
    installCheckPhase = ''
      test ! -e root-script-ran
      ! grep -q 'trusted dependency script' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"
    '';
  };
}
