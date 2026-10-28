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
  import-lock-sources-isolated = fixture.overrideAttrs (_: {
    bunInstallFlags = [ "--linker=isolated" ];
  });
  import-lock-workspace = imported workspaces.workspace-installed;
  import-lock-workspace-isolated = imported workspaces.workspace-isolated;
  import-lock-workspace-bins = imported workspaces.workspace-unbuilt-bin;
  import-lock-catalogs = imported workspaces.catalogs;
  import-lock-local = imported sources.local-dependencies;
  import-lock-local-isolated = imported sources.local-dependencies-isolated;
  import-lock-patched = imported sources.patched-dependency;
  import-lock-foreign-optional = imported sources.foreign-optional;
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
    test "$(cat ${basic.bunDeps}/.nix-bun/format-version)" = 1
    cmp ${basic.bunDeps}/.nix-bun/bun.lock ${./fixtures/basic/bun.lock}
    test ! -e ${basic.bunDeps}/node_modules
    test -z "$(find ${basic.bunDeps} -maxdepth 1 -name '*.npm' -print)"
    test -z "$(find ${basic.bunDeps} -type l -lname '/*' -print)"
    test -z "$(find ${basic.bunDeps} -type f -name '*.json' -exec grep -l '127.0.0.1' {} +)"
    touch "$out"
  '';
  import-lock-manifest-drift = pkgs.testers.testBuildFailure' {
    drv = pkgs.importBunLock {
      src = ./fixtures/native;
      lockFile = ./fixtures/basic/bun.lock;
    };
    expectedBuilderLogEntries = [ "lockfile is frozen" ];
  };
  import-lock-evaluation =
    assert succeeds { src = ./fixtures/basic; };
    assert !(succeeds { src = ./fixtures/binary-lock; });
    assert !(succeeds { src = ./fixtures/duplicate-git; });
    assert invalid (lock // { lockfileVersion = 99; });
    assert invalid (lock // { packages = [ ]; });
    assert invalid (lock // { packages.bad = [ ]; });
    assert invalid (lock // { packages.bad = [ "missing-resolution" ]; });
    assert invalid (
      lock
      // {
        packages.bad = [
          "bad@file:archive.tgz"
          { }
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
