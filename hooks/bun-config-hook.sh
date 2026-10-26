# shellcheck shell=bash

bunConfigHook() {
    echo "Executing bunConfigHook"
    pushd "${bunRoot:-.}" >/dev/null

    if [[ -z ${bunDeps-} ]]; then
        echo 'bunConfigHook: bunDeps is required' >&2
        exit 1
    fi
    if [[ ! -f "$bunDeps/.nix-bun/format-version" ]]; then
        echo 'bunConfigHook: missing cache metadata; regenerate bunDepsHash with lib.fakeHash' >&2
        exit 1
    fi
    if [[ $(cat "$bunDeps/.nix-bun/format-version") != 1 ]]; then
        echo 'bunConfigHook: incompatible or missing cache metadata; regenerate bunDepsHash with lib.fakeHash' >&2
        exit 1
    fi

    local lockfile
    if [[ -f bun.lock ]]; then lockfile=bun.lock
    elif [[ -f bun.lockb ]]; then lockfile=bun.lockb
    else echo 'bunConfigHook: missing bun.lock or bun.lockb' >&2; exit 1
    fi

    if ! cmp -s "$lockfile" "$bunDeps/.nix-bun/$lockfile"; then
        echo 'bunConfigHook: lockfile differs from cache; regenerate bunDepsHash with lib.fakeHash or update bunDeps' >&2
        exit 1
    fi

    # Keep user configuration and auto-installed tools out of the builder's home.
    export HOME="$TMPDIR/home"
    # Keep build logs readable when Bun runs scripts with terminal control codes.
    export BUN_CONFIG_NO_CLEAR_TERMINAL=1
    # The global store creates links outside node_modules that cannot be shipped.
    export BUN_INSTALL_GLOBAL_STORE=0
    # Bun's node-gyp shim otherwise runs `bun x node-gyp`, which downloads a tool.
    # Nixpkgs' bundled node-gyp also carries the Darwin build-tool patches.
    export npm_config_node_gyp="@nodeGyp@"
    # Use headers matching the supplied Node.js; node-gyp must not fetch them.
    export npm_config_nodedir="@nodeSrc@"
    mkdir -p "$HOME"
    export BUN_INSTALL_CACHE_DIR="$bunDeps"
    if [[ -n ${makeCacheWritable-} ]]; then
        BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
        cp -R "$bunDeps" "$BUN_INSTALL_CACHE_DIR"
        chmod -R u+w "$BUN_INSTALL_CACHE_DIR"
    fi

    runHook preBunInstall

    # Unlike npm, Bun has no rebuild command. A second install after
    # --ignore-scripts does not replay trusted dependency scripts either.
    # Keep Bun's trust and dependency ordering by running scripts in this install.
    # Packages that need shebang fixes before scripts run must be patched in
    # the source/cache before this command (see README.md).
    local -a installFlags=()
    concatTo installFlags bunFlags bunFlagsArray bunInstallFlags bunInstallFlagsArray
    if ! bun install "${installFlags[@]}" --offline --frozen-lockfile --backend copyfile; then
        echo 'bunConfigHook: offline install failed; check cache contents and lockfile, or try makeCacheWritable = true' >&2
        exit 1
    fi

    if [[ -d node_modules ]]; then
        chmod -R u+w node_modules
        patchShebangs node_modules
    fi

    runHook postBunInstall

    popd >/dev/null
    echo "Finished bunConfigHook"
}

postPatchHooks+=(bunConfigHook)
