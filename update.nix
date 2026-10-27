{
  writeShellApplication,
  writeShellScript,
  lib,
  common-updater-scripts,
  curl,
  jq,
  nix,
}:
let
  updater = writeShellApplication {
    name = "update-bun";
    runtimeInputs = [
      common-updater-scripts
      curl
      jq
      nix
    ];
    text = ''
      # Run from the repository root. An optional version allows updating to a
      # specific release; without one, use the latest stable GitHub release.
      version="''${1:-$(curl --fail --silent --show-error \
        https://api.github.com/repos/oven-sh/bun/releases/latest \
        | jq --exit-status --raw-output '.tag_name | ltrimstr("bun-v")')}"
      if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid Bun release version: $version" >&2
        exit 1
      fi

      current=$(nix-instantiate --eval --strict -A bun.version | jq --raw-output .)
      if [[ "$current" != "$version" ]]; then
        platforms=$(nix-instantiate --eval --strict --json -A bun.meta.platforms | jq --raw-output '.[]')
        for platform in $platforms; do
          update-source-version bun "$version" --ignore-same-version \
            --source-key="sources.$platform" --file=bun.nix
        done
      fi

      # Query the updated binary, not the Bun used to evaluate this updater.
      # Do this even when Bun is unchanged, so stale header pins can be repaired.
      bun_path=$(nix-build --no-out-link -A bun)
      node_version=$("$bun_path/bin/bun" -p process.versions.node)
      update-source-version bunNodeHeaders "$node_version" \
        --source-key=out --file=node-headers.nix
      nix-build --no-out-link -A bun.tests.node-headers
    '';
  };
in
writeShellScript "update-bun" ''
  exec ${lib.getExe updater} "$@"
''
