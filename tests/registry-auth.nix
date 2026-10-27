{ pkgs }:
# Exercise the real fetch/install commands against a local authenticated registry.
# Removing FOD attributes lets this test choose a free port without pinning it
# into a cache hash. The credential is deliberately public test data.
(pkgs.fetchBunDeps {
  name = "bun-registry-auth";
  src = ./fixtures/registry-auth;
  nativeBuildInputs = [ pkgs.python3 ];
  impureEnvVars = [ "NIX_BUN_TEST_TOKEN" ];
  preInstall = ''
    export NIX_BUN_TEST_TOKEN=public-test-token
    export REGISTRY_STATE="$TMPDIR/registry"
    python registry.py &
    registryPid=$!
    trap 'kill "$registryPid" 2>/dev/null || true' EXIT
    for attempt in {1..100}; do
      if [[ -f "$REGISTRY_STATE/port" ]]; then break; fi
      sleep 0.1
    done
    port=$(cat "$REGISTRY_STATE/port")
    cat > bunfig.toml <<EOF
    [install.scopes]
    private = { url = "http://127.0.0.1:$port/", token = "\$NIX_BUN_TEST_TOKEN" }
    EOF
  '';
  postInstall = ''
    test -f "$REGISTRY_STATE/authenticated"
    if grep -r -F "$NIX_BUN_TEST_TOKEN" "$out"; then
      echo 'fetchBunDeps leaked a registry credential' >&2
      exit 1
    fi
    kill "$registryPid"
    wait "$registryPid" || true
    trap - EXIT
    unset NIX_BUN_TEST_TOKEN
    bun install --offline --frozen-lockfile --ignore-scripts --backend copyfile
    test "$(bun -p "require('@private/example')")" = authenticated
  '';
}).overrideAttrs
  (_: {
    outputHash = null;
    outputHashAlgo = null;
    outputHashMode = null;
  })
