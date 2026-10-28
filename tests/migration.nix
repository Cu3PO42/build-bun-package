{ pkgs }:
let
  lib = pkgs.lib;
  fixtures = ./fixtures/migration;
  kinds = [
    "npm"
    "yarn-classic"
    "yarn-berry"
    "yarn-protocol"
    "pnpm"
  ];
  hashes = {
    npm = "sha256-Y505gcY4orTuxu4vbOPP+YbwQ1sT+5YsARwHk/pPx/w=";
    yarn-classic = "sha256-jBJFLvmkWo3pN78MpXLm5RR1MNP00h38C2e5qRam/CU=";
    yarn-berry = "sha256-DS7PoRZa4Q9+ynOc/3h9lZGT9BSwhCpVGdgBE5Mxrdc=";
    yarn-protocol = "sha256-5tr9FNU3X/U0vL3+WxpnwYh1P2N56Dk/voihJNvnFzA=";
    pnpm = "sha256-JpPLduDpM9Z/xzKmgF8nFVqx7NBWHwu7JDNWCje18IQ=";
  };
  source =
    kind:
    pkgs.runCommand "bun-migration-${kind}-source" { } ''
      mkdir -p "$out"
      cp ${fixtures}/{package.json,cli.js} "$out/"
      chmod u+w "$out/package.json"
      cp -R ${fixtures}/${kind}/. "$out/"
    '';
  packages = lib.genAttrs kinds (
    kind:
    pkgs.buildBunPackage {
      pname = "bun-migration-${kind}";
      version = "1.0.0";
      src = source kind;
      bunDepsHash = hashes.${kind};
      dontBunBuild = true;
      doCheck = true;
      checkPhase = ''
        test -x node_modules/.bin/is-docker
        test "$(bun cli.js)" = function
        test ! -d "$bunDeps/node_modules"
        test -f "$bunDeps/.nix-bun/migration.json"
        test -z "$(find "$bunDeps" -maxdepth 1 -name '*.npm' -print)"
        ${lib.optionalString (kind == "pnpm") ''
          bun -e 'const p = require("./package.json"); if (!p.workspaces.includes("packages/*") || !p.trustedDependencies.includes("is-docker")) process.exit(1)'
          bun -e 'if (Bun.JSONC.parse(await Bun.file("bun.lock").text()).workspaces["packages/message"].name !== "migration-message") process.exit(1)'
        ''}
        ${lib.optionalString (kind == "yarn-protocol") ''
          bun -e 'if (require("./package.json").dependencies["local-message"] !== "file:./local" || require("local-message") !== "message") process.exit(1)'
        ''}
      '';
      doInstallCheck = true;
      installCheckPhase = ''test "$("$out/bin/migration-example")" = function'';
    }
  );
  pnpm = packages.pnpm;
  # A separately supplied cache must preserve build-only manifest edits too.
  patched = pnpm.overrideAttrs (old: {
    bunDeps = pnpm.bunDeps;
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    postPatch = ''
      jq '.scripts.buildOnly = "echo patched" | .description = "patched manifest"' package.json > package.json.new
      mv package.json.new package.json
      jq '.description = "patched workspace"' packages/message/package.json > workspace.json
      mv workspace.json packages/message/package.json
    '';
    preBuild = ''
      test "$(bun run buildOnly)" = patched
      bun -e 'if (require("./package.json").description !== "patched manifest" || require("./packages/message/package.json").description !== "patched workspace") process.exit(1)'
    '';
  });
  expectedFailure =
    name: drv: message:
    pkgs.testers.testBuildFailure' {
      inherit drv;
      name = "bun-migration-${name}-failure";
      expectedBuilderLogEntries = [ message ];
    };
  fetchFailure =
    name: postPatch: message:
    expectedFailure name (
      (pkgs.fetchBunDeps {
        name = "bun-migration-${name}";
        src = source "npm";
        inherit postPatch;
        nativeBuildInputs = [ pkgs.jq ];
      }).overrideAttrs
        (_: {
          outputHash = null;
          outputHashAlgo = null;
          outputHashMode = null;
        })
    ) message;
in
lib.mapAttrs' (kind: value: lib.nameValuePair "migration-${kind}" value) packages
// lib.listToAttrs (
  map (
    kind:
    lib.nameValuePair "migration-${kind}-cache" (
      pkgs.testers.invalidateFetcherByDrvHash pkgs.fetchBunDeps {
        name = "bun-migration-${kind}-cache-${pkgs.stdenv.hostPlatform.system}";
        src = source kind;
        hash = hashes.${kind};
        postInstall = ''
          test -f "$out/.nix-bun/migration.json"
          test ! -d "$out/node_modules"
          test -z "$(find "$out" -maxdepth 1 -name '*.npm' -print)"
        '';
      }
    )
  ) kinds
)
// rec {
  migration-patched-manifests = patched;
  migration-patched-protocol = packages.yarn-protocol.overrideAttrs (old: {
    bunDeps = packages.yarn-protocol.bunDeps;
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    postPatch = ''
      jq '.description = "preserved alongside rewritten dependency"' package.json > package.json.new
      mv package.json.new package.json
    '';
    preBuild = ''bun -e 'if (require("./package.json").description !== "preserved alongside rewritten dependency") process.exit(1)' '';
  });
  migration-custom-patch-phase = pnpm.overrideAttrs (old: {
    src = pkgs.runCommand "bun-migration-unprepared-source" { } ''
      cp -R ${source "pnpm"} "$out"
      chmod -R u+w "$out"
      mv "$out/pnpm-lock.yaml" "$out/pnpm-lock.yaml.in"
    '';
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    bunDepsNativeBuildInputs = [ pkgs.jq ];
    patchPhase = ''
      runHook prePatch
      jq '.scripts.customPatch = "echo custom-patch"' package.json > package.json.new
      mv package.json.new package.json
      # Migration must see this prepared foreign lockfile in both derivations.
      mv pnpm-lock.yaml.in pnpm-lock.yaml
      test ! -f bun.lock
      runHook postPatch
    '';
    # Script edits do not change the migration metadata or dependency graph.
    bunDepsHash = hashes.pnpm;
    preBuild = ''test "$(bun run customPatch)" = custom-patch'';
  });
  migration-custom-patch-cache = pkgs.testers.invalidateFetcherByDrvHash (
    _: migration-custom-patch-phase.bunDeps
  ) { };
  migration-conflicting-patch = expectedFailure "conflicting-patch" (pnpm.overrideAttrs (old: {
    bunDeps = pnpm.bunDeps;
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    postPatch = ''
      jq '.trustedDependencies = []' package.json > package.json.new
      mv package.json.new package.json
    '';
  })) "conflicting migration and patch edits at package.json.trustedDependencies";
  migration-dependency-drift = expectedFailure "dependency-drift" (pnpm.overrideAttrs (old: {
    bunDeps = pnpm.bunDeps;
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
    postPatch = ''
      jq '.dependencies["is-docker"] = "3.0.0"' package.json > package.json.new
      mv package.json.new package.json
    '';
  })) "offline install failed";
  migration-lock-drift = expectedFailure "lock-drift" (pnpm.overrideAttrs (_: {
    bunDeps = pnpm.bunDeps;
    postPatch = ''printf '\n# changed\n' >> pnpm-lock.yaml'';
  })) "migration input pnpm-lock.yaml differs from cache";
  migration-missing-lock =
    fetchFailure "missing-lock" "rm package-lock.json"
      "a committed Bun, npm, Yarn, or pnpm lockfile is required";
  migration-unsupported-lock = fetchFailure "unsupported-lock" ''
    jq '.lockfileVersion = 1' package-lock.json > package-lock.json.new
    mv package-lock.json.new package-lock.json
  '' "unsupported lockfileVersion 1";
}
