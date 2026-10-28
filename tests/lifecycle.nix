{ pkgs, example }:
let
  patched-shebang = pkgs.buildBunPackage {
    pname = "bun-patched-shebang";
    version = "1";
    src = ./fixtures/patched-shebang;
    bunDepsHash = "sha256-FUFas7GOMdUkq9rF3JWS4NIdvDMTeLZNG1aBz/J1HhU=";
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
    nodejs = pkgs.nodejs;
    makeCacheWritable = false; # Scripts still require a writable copy.
  });

  trusted-lifecycle = pkgs.buildBunPackage {
    pname = "bun-trusted-lifecycle";
    version = "1";
    src = ./fixtures/trusted;
    bunDepsHash = "sha256-yp69Jks7nsEvClpdP31p6UfQbxofhf/ASkSkckPjeyw=";
    bunRunScripts = true;
    doInstallCheck = true;
    installCheckPhase = ''test "$(grep -c 'trusted dependency script' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js")" -eq 1'';
  };

  lifecycle-disabled = pkgs.buildBunPackage {
    pname = "bun-lifecycle-disabled";
    version = "1";
    src = ./fixtures/trusted;
    bunDepsHash = "sha256-yp69Jks7nsEvClpdP31p6UfQbxofhf/ASkSkckPjeyw=";
    nativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.scripts.postinstall = "touch root-script-ran"' package.json > package.json.new
      mv package.json.new package.json
    '';
    bunDepsNativeBuildInputs = [ pkgs.jq ];
    makeCacheWritable = true; # Bun's patchedDependencies need cache writes.
    preBunInstall = ''test "$BUN_INSTALL_CACHE_DIR" != "$bunDeps"'';
    doInstallCheck = true;
    installCheckPhase = ''
      test ! -e root-script-ran
      ! grep -q 'trusted dependency script' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"
    '';
  };
}
