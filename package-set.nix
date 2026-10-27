# Shared by the standalone package scope and the optional overlay.
{ callPackage }:
{
  bun = callPackage ./bun.nix { };
  fetchBunDeps = callPackage ./fetch-bun-deps.nix { };
  bunHooks = callPackage ./hooks { };
  bunNodeGyp = callPackage ./node-gyp.nix { };
  bunNodeHeaders = callPackage ./node-headers.nix { };
  bunNodeGypHook = callPackage ./hooks/node-gyp.nix { };
  buildBunPackage = callPackage ./build-bun-package.nix { };
}
