{
  writeShellApplication,
  writeShellScript,
  lib,
  common-updater-scripts,
  jq,
  nix,
}:
let
  updater = writeShellApplication {
    name = "update-bun-node-headers";
    runtimeInputs = [
      common-updater-scripts
      jq
      nix
    ];
    text = ''
      # Run from the repository root. Query the selected Bun after any update,
      # rather than the Bun used to evaluate this script.
      bun_path=$(nix-build --no-out-link -A bun)
      node_version=$("$bun_path/bin/bun" -p process.versions.node)
      update-source-version bunNodeHeaders "$node_version" \
        --source-key=out --file=pkgs/node-gyp/node-headers.nix

      headers_path=$(nix-build --no-out-link -A bunNodeHeaders)
      actual=$(nix-instantiate --eval --strict --json -A bunNodeHeaders.version | jq --raw-output .)
      test "$actual" = "$node_version"
      test -f "$headers_path/include/node/node_api.h"
    '';
  };
in
writeShellScript "update-bun-node-headers" ''
  exec ${lib.getExe updater} "$@"
''
