# shellcheck shell=bash
# stdenv enables errexit, so failed directory changes abort the build.
# shellcheck disable=SC2164

bunPatchShebangs() {
    # Binary lockfiles have an executable shebang but fixed binary offsets;
    # rewriting that line corrupts them. Batch paths to stay below ARG_MAX.
    local -a scripts=()
    while (($#)); do
        while mapfile -d '' -n 32 -t scripts && ((${#scripts[@]})); do
            patchShebangs "${scripts[@]}"
        done < <(find "${@:1:32}" -type f -perm -0100 ! -name bun.lockb -print0)
        if (($# <= 32)); then break; fi
        shift 32
    done
}

bunPatchElf() {
    # Reuse the caller's autoPatchelfHook and its library/search-path settings.
    if [[ -z ${dontAutoPatchelf-} ]] && declare -F autoPatchelf >/dev/null; then
        autoPatchelf "$@"
    fi
}

bunFixupElf() {
    # Early patching can reference libraries inside the build tree or private
    # cache. Resolve them against the installed outputs before RPATH auditing.
    if declare -F autoPatchelfPostFixup >/dev/null; then
        autoPatchelfPostFixup
    fi
}

bunSetupDependencyCache() {
    export BUN_INSTALL_CACHE_DIR="$bunDeps"
    if [[ -n ${makeCacheWritable-} || -n ${bunRunScripts-} ]]; then
        BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
        cp -R "$bunDeps" "$BUN_INSTALL_CACHE_DIR"
        chmod -R u+w "$BUN_INSTALL_CACHE_DIR"
    fi
}

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
    if [[ $(cat "$bunDeps/.nix-bun/format-version") != "${bunDepsFormatVersion:-1}" ]]; then
        echo 'bunConfigHook: incompatible or missing cache metadata; regenerate bunDepsHash with lib.fakeHash' >&2
        exit 1
    fi

    local lockfile
    if [[ -f bun.lock ]]; then
        lockfile=bun.lock
    elif [[ -f bun.lockb ]]; then
        lockfile=bun.lockb
    else
        echo 'bunConfigHook: missing bun.lock or bun.lockb' >&2
        exit 1
    fi

    if ! cmp -s "$lockfile" "$bunDeps/.nix-bun/$lockfile"; then
        echo 'bunConfigHook: lockfile differs from cache; regenerate bunDepsHash with lib.fakeHash or update bunDeps' >&2
        exit 1
    fi

    # Keep build logs readable when Bun runs scripts with terminal control codes.
    export BUN_CONFIG_NO_CLEAR_TERMINAL=1
    # The global store creates links outside node_modules that cannot be shipped.
    export BUN_INSTALL_GLOBAL_STORE=0
    # Lifecycle preparation and other cache mutations need a private copy.
    "${bunDependencySetupHook:-bunSetupDependencyCache}"

    runHook preBunInstall

    # Project helpers and linked local/workspace packages can execute during
    # installation, before stdenv's final output shebang fixup.
    bunPatchShebangs .

    local -a installFlags=()
    concatTo installFlags bunFlags bunFlagsArray bunInstallFlags bunInstallFlagsArray
    if [[ -n ${bunRunScripts-} ]]; then
        # Let Bun apply patchedDependencies to pristine cache entries first.
        # Symlinked files identify the cache packages selected for this platform
        # without decoding Bun's lockfile or its internal cache directory names.
        # Bun's isolated linker does not symlink package files for this backend.
        # Only staging uses hoisting; the final install honors the chosen linker.
        if ! bun install "${installFlags[@]}" --offline --frozen-lockfile --linker hoisted --backend symlink --ignore-scripts; then
            echo 'bunConfigHook: offline dependency preparation failed' >&2
            exit 1
        fi
        local cacheRoot manifest target directory
        local -a preparedCachePackages=()
        local -A prepared=()
        cacheRoot=$(realpath "$BUN_INSTALL_CACHE_DIR")
        while IFS= read -r -d "" manifest; do
            target=$(realpath "$manifest")
            if [[ $target == "$cacheRoot/"* ]]; then
                directory=$(dirname "$target")
                if [[ -z ${prepared[$directory]-} ]]; then
                    prepared[$directory]=1
                    preparedCachePackages+=("$directory")
                fi
            fi
        done < <(find . -path '*/node_modules/*' -type l -name package.json -print0)
        if ((${#preparedCachePackages[@]})); then
            bunPatchShebangs "${preparedCachePackages[@]}"
        fi
        # Only selected packages are prepared, leaving foreign OS/CPU/libc
        # variants in the all-platform cache untouched.
        bunPatchElf . "${preparedCachePackages[@]}"
        # A plain second install skips dependency scripts. Force a reinstall
        # from the prepared cache, retaining Bun's normal trust rules.
        installFlags+=(--force)
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
        bunPatchShebangs node_modules
    fi

    # Also prepare ordinary script-free installs and newly generated binaries
    # before build/check phases or a caller's postBunInstall commands use them.
    bunPatchElf .

    runHook postBunInstall

    popd >/dev/null
    echo "Finished bunConfigHook"
}

postPatchHooks+=(bunConfigHook)
preFixupHooks+=(bunFixupElf)
