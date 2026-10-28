{ pkgs }:
let
  inherit (pkgs) lib;
  fixtures = ./fixtures/migration-real;
  hashes = {
    markdown-toc = "sha256-4atBf00Lflk4+joGUbEbYJsnFiZHTu6kVijIgu24444=";
    localtunnel = "sha256-pBz2JCAMLt8oT2KEPpK/lPLFSjVTcfOdXXGEZRAx0bM=";
    yarn-lock-converter = "sha256-1ZSyhHar1XBgMisYeJFmK/ut+EV4vhpE8xmPgH3Ix00=";
    relative-time = "sha256-VuvDncsYDxKivfv5vXJW2FAhBkQkmzO8RUCw9XzmcoY=";
    opcua-schema = "sha256-t19hvaE+wkrVfZJz9xaSYLIJZ8rXeiReQYJQuonZ0M4=";
  };
  caches = lib.mapAttrs (
    name: hash:
    pkgs.testers.invalidateFetcherByDrvHash pkgs.fetchBunDeps {
      name = "bun-migration-real-${name}-deps-${pkgs.stdenv.hostPlatform.system}";
      src = fixtures + "/${name}";
      inherit hash;
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
      nativeBuildInputs = [ pkgs.bunHooks.bunConfigHook ];
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
