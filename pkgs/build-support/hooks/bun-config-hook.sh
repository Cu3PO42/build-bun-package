# shellcheck shell=bash
# stdenv enables errexit, so failed directory changes abort the build.
# shellcheck disable=SC2164

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
    mkdir -p "$HOME"
    # Lifecycle preparation and other cache mutations need a private copy.
    export BUN_INSTALL_CACHE_DIR="$bunDeps"
    if [[ -n ${makeCacheWritable-} || -n ${bunRunScripts-} ]]; then
        BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
        cp -R "$bunDeps" "$BUN_INSTALL_CACHE_DIR"
        chmod -R u+w "$BUN_INSTALL_CACHE_DIR"
    fi

    runHook preBunInstall

    # Project helpers and linked local/workspace packages can execute during
    # installation, before stdenv's final output shebang fixup.
    patchShebangs .

    local -a installFlags=()
    concatTo installFlags bunFlags bunFlagsArray bunInstallFlags bunInstallFlagsArray
    if [[ -n ${bunRunScripts-} ]]; then
        # Fix dependency executables before Bun runs lifecycle scripts. Keep
        # interpreter paths out of the portable fixed-output cache itself.
        patchShebangs "$BUN_INSTALL_CACHE_DIR"
    else
        installFlags+=(--ignore-scripts)
    fi
    # copyfile keeps installed files separate from the store/cache inode.
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
