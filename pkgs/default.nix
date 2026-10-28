# Shared by the standalone package scope and the optional overlay.
{ callPackage }:
let
  bunHooks = callPackage ./build-support/hooks { };
in
{
  bun = callPackage ./bun { };
  fetchBunDeps = callPackage ./build-support/fetch-bun-deps.nix { };
  importBunLock = callPackage ./build-support/import-bun-lock { };
  inherit bunHooks;
  bunNodeGyp = callPackage ./node-gyp { };
  bunNodeHeaders = callPackage ./node-gyp/node-headers.nix { };
  buildBunPackage = callPackage ./build-support/build-bun-package.nix { };
}
