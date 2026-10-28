{
  pkgs,
  example,
  workspaces,
  sources,
}:
let
  imported =
    package:
    package.overrideAttrs (_: {
      bunDeps = pkgs.importBunLock { inherit (package) src; };
    });
  fixture = pkgs.buildBunPackage {
    pname = "bun-import-lock-sources";
    version = "1";
    src = ./fixtures/import-lock;
    bunDeps = pkgs.importBunLock {
      src = ./fixtures/import-lock;
      registry = "https://registry.yarnpkg.com";
      scopedRegistries."@types" = "https://registry.npmjs.org";
      fetcherOpts.react = {
        url = "https://registry.npmjs.org/react/-/react-19.0.0-rc.1.tgz";
      };
    };
    dontBunBuild = true;
    doInstallCheck = true;
    installCheckPhase = ''
      test -f "$out/lib/node_modules/import-lock-example/node_modules/@types/is-number/index.d.ts"
      cd "$TMPDIR"
      rm -rf "$NIX_BUILD_TOP/import-lock"
      test "$("$out/bin/import-lock-example")" = 'imported lock works'
    '';
  };
  basic = imported example;
  sourceLock = import ../pkgs/build-support/import-bun-lock/jsonc.nix (
    builtins.readFile ./fixtures/import-lock/bun.lock
  );
  legacyTarballLock = builtins.toFile "legacy-tarball.lock" (
    builtins.toJSON (
      sourceLock
      // {
        packages = sourceLock.packages // {
          is-number = pkgs.lib.take 2 sourceLock.packages.is-number;
        };
      }
    )
  );
  lifecycle = import ./lifecycle.nix { inherit pkgs example; };
  patchedScripts = (imported lifecycle.patched-shebang).overrideAttrs (_: {
    installCheckPhase = ''
      packageOut="$out/lib/node_modules/patched-shebang"
      test "$(wc -l < "$packageOut/root-lifecycle-runs")" -eq 1
      test "$("$packageOut/node_modules/esbuild/bin/esbuild" --version)" = 0.25.0
      test -z "$(find "$out" -type l -lname "$TMPDIR/*" -print)"
    '';
  });
  lock = import ../pkgs/build-support/import-bun-lock/jsonc.nix (
    builtins.readFile ./fixtures/workspace/bun.lock
  );
  lockFile = value: builtins.toFile "bun.lock" (builtins.toJSON value);
  # Force evaluation of the manifest, including every package's fetcher.
  succeeds = args: (builtins.tryEval (pkgs.importBunLock args).drvPath).success;
  invalid =
    value:
    !(succeeds {
      src = ./fixtures/workspace;
      lockFile = lockFile value;
    });
in
{
  import-lock-basic = basic;
  import-lock-sources = fixture;
  import-lock-legacy-tarball = fixture.overrideAttrs (_: {
    postPatch = "cp ${legacyTarballLock} bun.lock";
    bunDeps = pkgs.importBunLock {
      src = ./fixtures/import-lock;
      lockFile = legacyTarballLock;
      registry = "https://registry.yarnpkg.com";
      scopedRegistries."@types" = "https://registry.npmjs.org";
      fetcherOpts.is-number.hash = builtins.elemAt sourceLock.packages.is-number 2;
    };
  });
  import-lock-sources-isolated = fixture.overrideAttrs (_: {
    bunInstallFlags = [ "--linker=isolated" ];
  });
  import-lock-workspace = imported workspaces.workspace-installed;
  import-lock-workspace-isolated = imported workspaces.workspace-isolated;
  import-lock-workspace-bins = imported workspaces.workspace-unbuilt-bin;
  import-lock-catalogs = imported workspaces.catalogs;
  import-lock-local = imported sources.local-dependencies;
  import-lock-local-isolated = imported sources.local-dependencies-isolated;
  import-lock-local-tarballs = pkgs.buildBunPackage {
    pname = "bun-import-local-tarballs";
    version = "1";
    src = ./fixtures/local-tarballs;
    bunDeps = pkgs.importBunLock { src = ./fixtures/local-tarballs; };
    dontBunBuild = true;
    doInstallCheck = true;
    installCheckPhase = ''
      sourceTree=$PWD
      cd "$TMPDIR"
      rm -rf "$sourceTree" "$BUN_INSTALL_CACHE_DIR"
      test "$("$out/bin/local-tarballs")" = 'local tarballs work'
      while IFS= read -r -d "" link; do test -e "$link"; done < <(find "$out" -type l -print0)
    '';
  };
  import-lock-patched = imported sources.patched-dependency;
  import-lock-foreign-optional = (imported sources.foreign-optional).overrideAttrs (_: {
    installCheckPhase = ''
      tar -tf "$bunDeps/tarballs/0.tgz" > archive-files
      grep -q esbuild.exe archive-files
      test ! -e "$out/lib/node_modules/foreign-optional/node_modules/@esbuild/win32-x64"
    '';
  });
  import-lock-patched-scripts = patchedScripts;
  import-lock-patched-scripts-isolated = patchedScripts.overrideAttrs (_: {
    bunInstallFlags = [ "--linker=isolated" ];
  });
  import-lock-trusted-scripts = imported lifecycle.trusted-lifecycle;
  import-lock-disabled-scripts = imported lifecycle.lifecycle-disabled;
  import-lock-source-shebangs = imported lifecycle.source-shebangs;
  import-lock-preparation-hook = imported lifecycle.lifecycle-preparation-hook;
  import-lock-nested = pkgs.callPackage ./example.nix {
    fixtureSrc = ./fixtures;
    projectRoot = "basic";
    dependencyCache = pkgs.importBunLock {
      src = ./fixtures;
      bunRoot = "basic";
      lockFile = ./fixtures/basic/bun.lock;
    };
  };
  import-lock-cache-contract = pkgs.runCommand "bun-import-lock-cache-contract" { } ''
    test "$(cat ${basic.bunDeps}/.nix-bun/format-version)" = 2
    cmp ${basic.bunDeps}/.nix-bun/bun.lock ${./fixtures/basic/bun.lock}
    test ! -e ${basic.bunDeps}/node_modules
    test -z "$(find ${basic.bunDeps} -maxdepth 1 -name '*.npm' -print)"
    test -f ${basic.bunDeps}/sources.json
    test -L ${basic.bunDeps}/tarballs/0.tgz
    test -z "$(find ${basic.bunDeps} -name package.json -print)"
    touch "$out"
  '';
  import-lock-manifest-drift = pkgs.testers.testBuildFailure' {
    drv = basic.overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
      postPatch = ''
        jq 'del(.dependencies["is-odd"])' package.json > changed.json
        mv changed.json package.json
      '';
    });
    expectedBuilderLogEntries = [ "lockfile is frozen" ];
  };
  import-lock-standalone-hook = pkgs.stdenv.mkDerivation {
    name = "bun-import-standalone-hook";
    src = ./fixtures/basic;
    bunDeps = basic.bunDeps;
    nativeBuildInputs = [ pkgs.importBunLock.bunConfigHook ];
    postPatch = ''
      { printf '// Bun accepts comments in package.json\n'; cat package.json; } > package.json.new
      mv package.json.new package.json
    '';
    dontBuild = true;
    installPhase = ''
      bun -e 'if (!require("is-odd")(3)) process.exit(1)'
      test "$BUN_INSTALL_CACHE_DIR" != "$bunDeps"
      touch "$out"
    '';
  };
  import-lock-evaluation =
    assert succeeds { src = ./fixtures/basic; };
    assert succeeds { src = ./fixtures/local-tarballs; };
    assert !(succeeds { src = ./fixtures/binary-lock; });
    assert succeeds { src = ./fixtures/duplicate-git; };
    assert invalid (lock // { lockfileVersion = 99; });
    assert invalid (lock // { packages = [ ]; });
    assert invalid (lock // { packages.bad = [ ]; });
    assert invalid (lock // { packages.bad = [ "missing-resolution" ]; });
    assert invalid (
      lock
      // {
        packages.bad = [
          "bad@git+https://example.com/repo.git#main"
          { }
          "main"
        ];
      }
    );
    assert invalid (
      lock
      // {
        packages.bad = [
          "bad@github:owner/repository#1234567"
          { }
          "owner-repository-1234567"
        ];
      }
    );
    assert invalid (
      lock
      // {
        packages.bad = [
          "bad@file:local"
          "not metadata"
        ];
      }
    );
    assert invalid (
      lock
      // {
        packages.bad = [
          "bad@1.0.0"
          ""
          { }
          ""
        ];
      }
    );
    assert invalid (
      lock
      // {
        packages.bad = [
          "bad@1.0.0"
          ""
          { }
          "md5-abc"
        ];
      }
    );
    assert invalid (
      lock
      // {
        packages.bad = [
          "bad@https://example.com/archive.tgz"
          { }
        ];
      }
    );
    assert invalid (
      lock
      // {
        packages.bad = [
          "bad@file:archive.tgz"
          { }
          "sha512-abc"
        ];
      }
    );
    pkgs.runCommand "bun-import-lock-evaluation" { } "touch $out";
}
// import ./import-lock-git.nix { inherit pkgs sources; }
// pkgs.lib.mapAttrs' (name: drv: pkgs.lib.nameValuePair "import-lock-${name}" drv) (
  import ./elf.nix {
    inherit pkgs;
    importLock = true;
  }
)
