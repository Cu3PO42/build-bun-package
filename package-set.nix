# Shared by the standalone package scope and the optional overlay.
{ callPackage }:
{
  bun = callPackage ./bun.nix { };
  fetchBunDeps = callPackage ./fetch-bun-deps.nix { };
  bunHooks = callPackage ./hooks { nodejs = null; };
  bunNodeGyp = callPackage ./node-gyp.nix { nodejs = null; };
  bunNodeHeaders = callPackage ./node-headers.nix { };
  # Preserve callPackage overrides on the public alias (e.g. custom headers).
  bunNodeGypHook = callPackage (
    {
      bun,
      bunNodeGyp,
      bunNodeHeaders,
      python3,
      nodejs ? null,
    }:
    (callPackage ./hooks {
      inherit
        bun
        bunNodeGyp
        bunNodeHeaders
        python3
        nodejs
        ;
    }).bunNodeGypHook
  ) { nodejs = null; };
  buildBunPackage = callPackage ./build-bun-package.nix { };
}
