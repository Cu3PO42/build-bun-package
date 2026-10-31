{ pkgs }:
let
  inherit (pkgs) lib;
  fixtures = ./fixtures/migration-real;
  hashes = {
    markdown-toc = "sha256-DbMyV83lEx5QHAvBo3ICdJUJS32qt98B/kPoDPpQCwQ=";
    localtunnel = "sha256-cAxXsv+Mq29tD2zj4HqPxakUGqGfLWaRBAVB9usBHWk=";
    yarn-lock-converter = "sha256-cXOKb17irKcNcEOdE/q5tGor62y5HLa7Y6uUR+qshN8=";
    relative-time = "sha256-FsiKMD4cagNs/QbumRRMuRF2TpMnIOhTfIF8VVmLOH8=";
    opcua-schema = "sha256-PC/k0q1JC8lE/LiWGDs2I/l3f+nD20l1XdKdNL6eKSU=";
  };
  caches = lib.mapAttrs (
    name: hash:
    pkgs.testers.invalidateFetcherByDrvHash pkgs.fetchBunDeps {
      name = "bun-migration-real-${name}-deps-${pkgs.stdenv.hostPlatform.system}";
      src = fixtures + "/${name}";
      inherit hash;
      bunMigrateLockfile = true;
      postInstall = ''
        test ! -e "$out/node_modules"
        test ! -e "$out/.tmp"
        test -z "$(find "$out" -maxdepth 1 -name '*.npm' -print)"
        bytes=$(du -sb "$out" | cut -f1)
        echo "${name} cache: $bytes bytes"
        test "$bytes" -lt $((12 * 1024 * 1024))
      '';
    }
  ) hashes;
in
lib.mapAttrs' (
  name: bunDeps:
  lib.nameValuePair "migration-real-${name}" (
    pkgs.stdenvNoCC.mkDerivation {
      name = "bun-migration-real-${name}";
      src = fixtures + "/${name}";
      inherit bunDeps;
      nativeBuildInputs = [
        pkgs.bunHooks.bunMigrateHook
        pkgs.bunHooks.bunConfigHook
      ];
      dontConfigure = true;
      dontBuild = true;
      prePatch = "test ! -e bun.lock && test ! -e bun.lockb";
      installPhase = ''
        runHook preInstall
        bun ${./test-migration-real.ts} ${lib.escapeShellArg name}
        touch "$out"
        runHook postInstall
      '';
    }
  )
) caches
// {
  migration-real-cache-size = pkgs.runCommand "bun-migration-real-cache-size" { } ''
    total=0
    for cache in ${lib.concatStringsSep " " (map toString (builtins.attrValues caches))}; do
      bytes=$(du -sb "$cache" | cut -f1)
      total=$((total + bytes))
    done
    echo "Combined real-world migration caches: $total bytes"
    test "$total" -lt $((32 * 1024 * 1024))
    touch "$out"
  '';
}
