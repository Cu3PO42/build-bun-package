# Shared by the standalone package scope and the optional overlay.
{ callPackage, lib }:
let
  bunHooks = callPackage ./hooks { nodejs = null; };
in
{
  bun = callPackage ./bun.nix { };
  fetchBunDeps = callPackage ./fetch-bun-deps.nix { };
  inherit bunHooks;
  bunNodeGyp = callPackage ./node-gyp.nix { nodejs = null; };
  bunNodeHeaders = callPackage ./node-headers.nix { };
  # Delegate public hook overrides to the shared hook set.
  bunNodeGypHook = lib.makeOverridable (args: (bunHooks.override args).bunNodeGypHook) { };
  buildBunPackage = callPackage ./build-bun-package.nix { };
}
