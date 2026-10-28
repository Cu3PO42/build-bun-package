{
  callPackage,
  path,
  writeShellScript,
  bunNodeHeaders,
  version,
}:
let
  # Evaluate the upstream updater with our version for its early-exit check.
  upstreamBun = (callPackage (path + "/pkgs/by-name/bu/bun/package.nix") { }).overrideAttrs {
    inherit version;
    __intentionallyOverridingVersion = true;
  };
in
writeShellScript "update-bun" ''
  set -e
  ${upstreamBun.updateScript}
  ${bunNodeHeaders.updateScript}
''
