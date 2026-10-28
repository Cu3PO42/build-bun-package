# shellcheck shell=bash
# stdenv enables errexit, so failed directory changes abort the build.
# shellcheck disable=SC2164

bunMigrateHook() {
    if [[ ! -f ${bunDeps-}/.nix-bun/migration.json ]]; then return; fi
    echo "Executing bunMigrateHook"
    pushd "${bunRoot:-.}" >/dev/null
    bun @migrateLock@ apply "$bunDeps"
    popd >/dev/null
}

# Project postPatch runs first. Migration must then precede the config hook,
# regardless of the order in which their setup hooks were sourced.
postPatchHooks=(bunMigrateHook "${postPatchHooks[@]}")
