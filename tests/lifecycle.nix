{ pkgs, example }:
let
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
  inherit lifecycle-writable;

  inherit lifecycle-shebangs;

  lifecycle-node-shebangs = lifecycle-shebangs.overrideAttrs (_: {
    nodejs = pkgs.nodejs;
    __structuredAttrs = true;
    makeCacheWritable = false; # Scripts still require a writable copy.
  });

  trusted-lifecycle = pkgs.buildBunPackage {
    pname = "bun-trusted-lifecycle";
    version = "1";
    src = ./fixtures/trusted;
    bunDepsHash = "sha256-yp69Jks7nsEvClpdP31p6UfQbxofhf/ASkSkckPjeyw=";
    bunRunScripts = true;
    doInstallCheck = true;
    installCheckPhase = ''grep -q 'trusted dependency script' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"'';
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
    __structuredAttrs = true;
    makeCacheWritable = true; # Bun's patchedDependencies need cache writes.
    preBunInstall = ''test "$BUN_INSTALL_CACHE_DIR" != "$bunDeps"'';
    doInstallCheck = true;
    installCheckPhase = ''
      test ! -e root-script-ran
      ! grep -q 'trusted dependency script' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"
    '';
  };
}
