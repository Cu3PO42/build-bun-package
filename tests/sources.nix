{ pkgs }:
let
  duplicateGit = pkgs.buildBunPackage {
    pname = "bun-duplicate-git";
    version = "1";
    src = ./fixtures/duplicate-git;
    bunDepsHash = "sha256-pmMIv9yvR/9ZHUg70KFsled0t/KH5RIrj9ICG/gT2ak=";
    bunDepsNativeBuildInputs = [ pkgs.git ];
    dontBunBuild = true;
    doInstallCheck = true;
    installCheckPhase = ''
      cd "$TMPDIR"
      rm -rf "$NIX_BUILD_TOP/duplicate-git"
      bun -e "for (const name of ['first', 'second']) { if (!require('$out/lib/node_modules/duplicate-git/node_modules/' + name)('3')) process.exit(1); }"
    '';
  };
  foreignOptional = pkgs.buildBunPackage {
    pname = "bun-foreign-optional";
    version = "1";
    src = ./fixtures/foreign-optional;
    bunDepsHash = "sha256-jGdGNvnXNZdtYR55CYEZKhdz4Ss67l4je8+iziQ4tCg=";
    dontBunBuild = true;
    doInstallCheck = true;
    installCheckPhase = ''
      # The all-platform cache must include this Windows-only binary even on
      # Linux/Darwin; the ordinary install must exclude the foreign package.
      test -n "$(find "$bunDeps" -name esbuild.exe -print -quit)"
      test ! -e "$out/lib/node_modules/foreign-optional/node_modules/@esbuild/win32-x64"
    '';
  };

  localDependencies = pkgs.buildBunPackage {
    pname = "bun-local-dependencies";
    version = "1";
    src = ./fixtures/local-dependencies;
    bunDepsHash = "sha256-G3ryLSIp40pH5iYxKIDRLnleyytn0BDsnRQKVos4wCU=";
    makeCacheWritable = true;
    dontBunBuild = true;
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      packageOut="$out/lib/node_modules/local-dependencies"
      # The root's publish list excludes these sources. Local packages must
      # survive through the installed dependency tree and linked-package packing.
      test ! -e "$packageOut/first"
      test ! -e "$packageOut/second"
      test -f "$packageOut/local/index.js"
      test ! -e "$packageOut/local/unpublished.txt"
      cd "$TMPDIR"
      rm -rf "$NIX_BUILD_TOP/local-dependencies"
      test "$("$out/bin/local-dependencies")" = 'local dependencies work'
      while IFS= read -r -d "" link; do test -e "$link"; done < <(find "$out" -type l -print0)
      runHook postInstallCheck
    '';
  };
in
{
  duplicate-git = duplicateGit;
  foreign-optional = foreignOptional;

  local-dependencies = localDependencies;
  local-dependencies-isolated = localDependencies.overrideAttrs (_: {
    bunInstallFlags = [ "--linker=isolated" ];
  });

  git-tarball-registry = pkgs.buildBunPackage {
    pname = "bun-source-fixture";
    version = "1";
    src = ./fixtures/sources;
    bunDepsHash = "sha256-B+0r5+hD3LZfcm6pg6hMO+BREOCIRkPzokUqdoae6CU=";
    bunDepsNativeBuildInputs = [ pkgs.git ];
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
    nativeBuildInputs = [ pkgs.jq ];
    bunDepsNativeBuildInputs = [
      pkgs.git
      pkgs.jq
    ];
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
    postBunInstall = ''
      cmp bun.lockb "$bunDeps/.nix-bun/bun.lockb"
      test -x bun.lockb
    '';
    doInstallCheck = true;
    installCheckPhase = ''test "$("$out/bin/bun-example" 3)" = odd'';
  };

  patched-dependency = pkgs.buildBunPackage {
    pname = "bun-patched-dependency";
    version = "1";
    src = ./fixtures/patched;
    bunDepsHash = "sha256-lT7chnHqWem8M+vLBqBTJLvbtpSoGs/D1KQMB1Zne3Y=";
    makeCacheWritable = true;
    doInstallCheck = true;
    installCheckPhase = ''grep -q 'patched by fixture' "$out/lib/node_modules/bun-example/node_modules/is-odd/index.js"'';
  };
}
