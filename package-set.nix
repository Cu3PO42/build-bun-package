# Shared by the standalone package scope and the optional overlay.
{ callPackage }:
{
  bun = callPackage ./bun.nix { };
  fetchBunDeps = callPackage ./fetch-bun-deps.nix { };
  bunHooks = callPackage ./hooks { };
  bunNodeGyp = callPackage ./node-gyp.nix { };
  bunNodeHeaders = callPackage ./node-headers.nix { };
  # Preserve callPackage overrides on the public alias (e.g. custom headers).
  bunNodeGypHook = callPackage (
    {
      bun,
      bunNodeGyp,
      bunNodeHeaders,
      python3,
    }:
    (callPackage ./hooks {
      inherit
        bun
        bunNodeGyp
        bunNodeHeaders
        python3
        ;
    }).bunNodeGypHook
  ) { };
  buildBunPackage = callPackage ./build-bun-package.nix { };
}
