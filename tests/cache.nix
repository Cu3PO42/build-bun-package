{
  pkgs,
  example,
  workspace,
  catalogs,
  duplicateGit,
  foreignOptional,
}:
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
in
{
  duplicate-git-cache = fetchForTest {
    name = "bun-duplicate-git-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/duplicate-git;
    nativeBuildInputs = [ pkgs.git ];
    hash = duplicateGit.bunDeps.outputHash;
  };
  foreign-optional-cache = fetchForTest {
    name = "bun-foreign-optional-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/foreign-optional;
    hash = foreignOptional.bunDeps.outputHash;
  };

  writable-cache = example.overrideAttrs (_: {
    makeCacheWritable = true;
  });

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
        rm "$bunDeps/.nix-bun/format"
        (bunConfigHook) > "$TMPDIR/metadata.log" 2>&1 && exit 1
        grep -q 'missing cache metadata' "$TMPDIR/metadata.log"
        printf 'source-bundle\n' > "$bunDeps/.nix-bun/format"
        (bunConfigHook) > "$TMPDIR/format.log" 2>&1 && exit 1
        grep -q 'incompatible or missing cache metadata' "$TMPDIR/format.log"
        printf 'extracted-cache\n' > "$bunDeps/.nix-bun/format"
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
    test "$(cat ${example.bunDeps}/.nix-bun/format)" = extracted-cache
    test "$(cat ${example.bunDeps}/.nix-bun/format-version)" = 1
    cmp ${example.bunDeps}/.nix-bun/bun.lock ${./fixtures/basic/bun.lock}
    touch "$out"
  '';

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
        __structuredAttrs = true;
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
    src = pkgs.bunNodeGyp.src;
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
    hash = "sha256-tJKoBbkhw00dCCd4VLl/Y2tiUq2+9JGOs5FORZjFKwc=";
  };

  binary-dependency-cache = fetchForTest {
    name = "bun-binary-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/binary-lock;
    hash = "sha256-QAf2z4p1EoJZmdajDQom1d+yIOQ4eZEWZT1/brQoU+I=";
  };

  source-dependency-cache = fetchForTest {
    name = "bun-source-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/sources;
    nativeBuildInputs = [ pkgs.git ];
    hash = "sha256-Am5rTbf5Utwntoin5iCkq6QcsXndS87uP3AivmKMl8o=";
  };

  workspace-dependency-cache = fetchForTest {
    name = "bun-workspace-deps-${pkgs.stdenv.hostPlatform.system}";
    src = ./fixtures/workspace;
    hash = workspace.bunDeps.outputHash;
  };

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
