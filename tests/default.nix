{ pkgs }:
let
  example = pkgs.callPackage ./example.nix { };
  workspace = pkgs.buildBunPackage {
    pname = "bun-workspace-example";
    version = "1.0.0";
    src = ./fixtures/workspace;
    bunDepsHash = "sha256-qMi8lw7OHZQg37M6xHPIr5asxw8Cr7jHXtqVy9zG/m8=";
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

  # Different output names force each platform to fetch its own cache rather
  # than reuse a fixed-output path already produced on another platform.
  dependency-cache = pkgs.fetchBunDeps {
    name = "bun-example-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/basic;
    hash = example.bunDeps.outputHash;
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
