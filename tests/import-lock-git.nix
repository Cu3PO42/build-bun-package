{ pkgs, sources }:
let
  rev = "cf105c473b705c7665ba654b28178a55de18cc06";
  hash = "sha256-Evhl5c1h7E35mN+BXi+to5VZ18tz2TQCyua+rgsb+Rc=";
  # A real local Git transport keeps this test independent of public Git hosts.
  # The same tracked checkout produces the same Git commit on every platform.
  repository = pkgs.runCommand "bun-test-git-repository" { nativeBuildInputs = [ pkgs.git ]; } ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" "$out"
    cp -R ${./fixtures/git-source/checkout}/. "$out/"
    chmod -R u+w "$out"
    git -C "$out" init -q --initial-branch=main
    git -C "$out" add .
    GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' \
      GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
      git -C "$out" -c commit.gpgsign=false commit -q -m fixture
    test "$(git -C "$out" rev-parse HEAD)" = ${rev}
  '';
  gitPackage =
    importer: opts:
    pkgs.buildBunPackage {
      pname = "bun-import-git";
      version = "1";
      src = ./fixtures/git-source;
      bunDeps = importer {
        src = ./fixtures/git-source;
        fetcherOpts = pkgs.lib.genAttrs [ "first" "second" ] (_: { url = "file://${repository}"; } // opts);
      };
      bunRunScripts = true;
      doInstallCheck = true;
      installCheckPhase = ''
            packageOut="$out/lib/node_modules/git-source-example"
            test "$(cat "$packageOut/build-ran")" = 42
            for name in first second; do
              test "$(cat "$packageOut/node_modules/$name/installed")" = 42
              test -x "$packageOut/node_modules/$name/bin/answer"
            test "$(cat "$packageOut/node_modules/$name/.bun-tag")" = ${rev}
              test ! -e "$packageOut/node_modules/$name/.git"
            done
          # Bun's copyfile backend omits package symlinks for native Git installs
          # too. The imported checkout must still retain them in the private cache.
          test -L "$BUN_INSTALL_CACHE_DIR/@G@${rev}/answer.js"
        test "$(head -n1 "$bunDeps/checkouts/0/bin/answer")" = '#!/usr/bin/env node'
            sourceTree=$PWD
            cd "$TMPDIR"
            rm -rf "$sourceTree" "$BUN_INSTALL_CACHE_DIR"
            test "$("$out/bin/git-source-example")" = 'git sources work'
            test -z "$(find "$out" -type l -lname "$TMPDIR/*" -print)"
      '';
    };
  git = gitPackage pkgs.importBunLock { inherit hash; };
  # Exercise the hash-free fetchGit path while keeping network and evaluation
  # fetching out of the test. The real checkout still runs through fetchgit.
  builtin = gitPackage (pkgs.importBunLock.override {
    fetchGit =
      args:
      assert args.rev == rev;
      assert args.allRefs;
      pkgs.fetchgit ((builtins.removeAttrs args [ "allRefs" ]) // { inherit hash; });
  }) { };
  imported =
    package:
    package.overrideAttrs (_: {
      bunDeps = pkgs.importBunLock { inherit (package) src; };
    });
  githubLock = import ../pkgs/build-support/import-bun-lock/jsonc.nix (
    builtins.readFile ./fixtures/duplicate-git/bun.lock
  );
  legacyGithubLock = builtins.toFile "legacy-github.lock" (
    builtins.toJSON (
      githubLock
      // {
        packages = pkgs.lib.mapAttrs (_: row: pkgs.lib.take 3 row) githubLock.packages;
      }
    )
  );
  legacyGithub = sources.duplicate-git.overrideAttrs (_: {
    bunDeps = pkgs.importBunLock {
      src = ./fixtures/duplicate-git;
      lockFile = legacyGithubLock;
      fetcherOpts = pkgs.lib.mapAttrs (_: row: { hash = builtins.elemAt row 3; }) githubLock.packages;
    };
    postPatch = "cp ${legacyGithubLock} bun.lock";
  });
  lock = import ../pkgs/build-support/import-bun-lock/jsonc.nix (
    builtins.readFile ./fixtures/git-source/bun.lock
  );
  legacyGitLock = builtins.toFile "legacy-git.lock" (
    builtins.toJSON (
      lock
      // {
        packages = pkgs.lib.mapAttrs (_: row: [
          "git-answer@git+https://example.invalid/repository.git#main"
          (builtins.elemAt row 1)
          "main"
        ]) lock.packages;
      }
    )
  );
  legacyGit = git.overrideAttrs (_: {
    postPatch = "cp ${legacyGitLock} bun.lock";
    bunDeps = pkgs.importBunLock {
      src = ./fixtures/git-source;
      lockFile = legacyGitLock;
      fetcherOpts = pkgs.lib.genAttrs [ "first" "second" ] (_: {
        url = "file://${repository}";
        inherit hash rev;
      });
    };
  });
  checkUrl =
    url: expected:
    let
      importer = pkgs.importBunLock.override {
        fetchGit =
          args:
          assert args.url == expected;
          assert args.rev == rev;
          ./fixtures/git-source/checkout;
      };
      changed = lock // {
        packages.first = [
          "git-answer@git+${url}#main"
          { }
          rev
        ];
      };
    in
    builtins.isString
      (importer {
        src = ./fixtures/git-source;
        lockFile = builtins.toFile "git-url.lock" (builtins.toJSON changed);
      }).drvPath;
in
{
  import-lock-git = git;
  import-lock-git-isolated = git.overrideAttrs (_: {
    bunInstallFlags = [ "--linker=isolated" ];
  });
  import-lock-git-builtin = builtin;
  import-lock-git-legacy = legacyGit;
  import-lock-github = imported sources.duplicate-git;
  import-lock-github-legacy = legacyGithub;
  import-lock-mixed-sources = imported sources.git-tarball-registry;
  import-lock-git-urls =
    assert checkUrl "https://example.com/repo.git" "https://example.com/repo.git";
    assert checkUrl "git://example.com/repo.git" "git://example.com/repo.git";
    assert checkUrl "ssh://git@example.com/repo.git" "ssh://git@example.com/repo.git";
    assert checkUrl "ssh://git@example.com:2222/repo.git" "ssh://git@example.com:2222/repo.git";
    assert checkUrl "ssh://git@example.com:owner/repo.git" "git@example.com:owner/repo.git";
    assert checkUrl "ssh://git@example.com:/repo.git" "git@example.com:/repo.git";
    assert checkUrl "ssh://git@[::1]/repo.git" "ssh://git@[::1]/repo.git";
    assert checkUrl "ssh://git@[::1]:2222/repo.git" "ssh://git@[::1]:2222/repo.git";
    assert checkUrl "ssh://git@[::1]:owner/repo.git" "git@[::1]:owner/repo.git";
    pkgs.runCommand "bun-import-git-urls" { } "touch $out";
}
