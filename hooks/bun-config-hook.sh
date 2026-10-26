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
    # Keep Bun configuration and caches out of the builder's real home.
    # Disable the global store to avoid links outside the installed package.
    export HOME="$TMPDIR/home" BUN_CONFIG_NO_CLEAR_TERMINAL=1 BUN_INSTALL_GLOBAL_STORE=0
    mkdir -p "$HOME"
    export BUN_INSTALL_CACHE_DIR="$bunDeps"
    if [[ -n ${makeCacheWritable-} ]]; then
        BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
        cp -R "$bunDeps" "$BUN_INSTALL_CACHE_DIR"
        chmod -R u+w "$BUN_INSTALL_CACHE_DIR"
    fi

    # Bun runs permitted lifecycle scripts during install; no separate rebuild is needed.
    if ! bun install --offline --frozen-lockfile --backend copyfile ${bunInstallFlags-} "${bunInstallFlagsArray[@]}"; then
        echo 'bunConfigHook: offline install failed; check cache contents and lockfile, or try makeCacheWritable = true' >&2
        exit 1
    fi

    if [[ -d node_modules ]]; then
        chmod -R u+w node_modules
        patchShebangs node_modules
    fi
    popd >/dev/null
    echo "Finished bunConfigHook"
}
postPatchHooks+=(bunConfigHook)
