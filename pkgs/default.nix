# Shared by the standalone package scope and the optional overlay.
{ callPackage, lib }:
let
  bunHooks = callPackage ./build-support/hooks { nodejs = null; };
in
{
  bun = callPackage ./bun { };
  fetchBunDeps = callPackage ./build-support/fetch-bun-deps.nix { };
  inherit bunHooks;
  bunNodeGyp = callPackage ./node-gyp { nodejs = null; };
  bunNodeHeaders = callPackage ./node-gyp/node-headers.nix { };
  # Delegate public hook overrides to the shared hook set.
  bunNodeGypHook = lib.makeOverridable (args: (bunHooks.override args).bunNodeGypHook) { };
  buildBunPackage = callPackage ./build-support/build-bun-package.nix { };
}
