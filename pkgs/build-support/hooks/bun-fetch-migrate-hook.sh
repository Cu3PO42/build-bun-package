# shellcheck shell=bash
# stdenv supplies out and enables errexit, so failed directory changes abort the build.
# shellcheck disable=SC2154,SC2164

bunFetchMigrateHook() {
    pushd "${bunRoot:-.}" >/dev/null
    if [[ -f bun.lock || -f bun.lockb ]]; then
        popd >/dev/null
        return
    fi
    echo "Executing bunFetchMigrateHook"
    if [[ ! -f npm-shrinkwrap.json && ! -f package-lock.json && ! -f yarn.lock && ! -f pnpm-lock.yaml ]]; then
        echo "fetchBunDeps: a committed Bun, npm, Yarn, or pnpm lockfile is required" >&2
        exit 1
    fi
    # Registry metadata is timestamped and must stay outside the fixed-output cache.
    bash @migrateLock@ snapshot "$TMPDIR/bun-migration"
    local -a migrateFlags=()
    concatTo migrateFlags bunFlags bunFlagsArray
    BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-migration-cache" BUN_INSTALL_GLOBAL_STORE=0 BUN_CONFIG_NO_CLEAR_TERMINAL=1 \
        bun pm migrate "${migrateFlags[@]}"
    if [[ ! -f bun.lock ]]; then
        echo "fetchBunDeps: Bun did not produce a migrated bun.lock" >&2
        exit 1
    fi
    mkdir -p "$out/.nix-bun"
    bash @migrateLock@ record "$TMPDIR/bun-migration" "$out/.nix-bun/migration"
    popd >/dev/null
}

# Project patches prepare the manifests before migration; installation only fetches.
postPatchHooks+=(bunFetchMigrateHook)
