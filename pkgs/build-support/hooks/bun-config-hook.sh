# shellcheck shell=bash
# stdenv enables errexit, so failed directory changes abort the build.
# shellcheck disable=SC2164

bunPatchElf() {
    # Reuse the caller's autoPatchelfHook and its library/search-path settings.
    if [[ -z ${dontAutoPatchelf-} ]] && declare -F autoPatchelf >/dev/null; then
        autoPatchelf "$@"
    fi
}

bunFixupElf() {
    # Early patching can reference libraries inside the build tree or private
    # cache. Resolve them against the installed outputs before RPATH auditing.
    # This Nixpkgs function normally runs in postFixup, but also works here:
    # it patches all existing non-debug outputs and honors dontAutoPatchelf.
    # Its normal postFixup call still runs after patchelf's RPATH shrinking.
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
    # Protect the project's binary lockfile from shebang rewriting.
    local executableLockfile=false
    if [[ -f bun.lockb && -x bun.lockb ]]; then
        chmod u-x bun.lockb
        executableLockfile=true
    fi
    patchShebangs .
    if "$executableLockfile"; then
        chmod u+x bun.lockb
    fi

    local -a installFlags=()
    concatTo installFlags bunFlags bunFlagsArray bunInstallFlags bunInstallFlagsArray
    if [[ -n ${bunRunScripts-} ]]; then
        # First materialize the dependency graph without executing any scripts.
        # Bun applies patchedDependencies against pristine cached package files;
        # patching their shebangs earlier could invalidate upstream patch hunks.
        # The symlink backend makes package files point into our writable cache.
        # Hoisting is needed only here: the isolated linker does not expose those
        # file symlinks. The final copy install honors the requested linker.
        if ! bun install "${installFlags[@]}" --offline --frozen-lockfile --linker hoisted --backend symlink --ignore-scripts; then
            echo 'bunConfigHook: offline dependency preparation failed' >&2
            exit 1
        fi
        local cacheRoot manifest target directory
        # Public to preBunInstallScripts: edits to these cache directories survive
        # the final reinstall. Replacing a file symlink in the staging tree would
        # only change that disposable tree, not the cached file Bun copies later.
        local -a bunPreparedCachePackages=()
        local -A prepared=()
        cacheRoot=$(realpath "$BUN_INSTALL_CACHE_DIR")
        # Follow each symlinked manifest to its real cache directory. This uses
        # Bun's own platform/dependency selection instead of parsing lockfiles or
        # guessing cache names. Workspace links outside the cache are excluded.
        while IFS= read -r -d "" manifest; do
            target=$(realpath "$manifest")
            if [[ $target == "$cacheRoot/"* ]]; then
                directory=$(dirname "$target")
                # A package can appear through several dependency paths. Prepare
                # its cache directory once, using an associative array as a set.
                if [[ -z ${prepared[$directory]-} ]]; then
                    prepared[$directory]=1
                    bunPreparedCachePackages+=("$directory")
                fi
            fi
        done < <(find . -path '*/node_modules/*' -type l -name package.json -print0)
        if ((${#bunPreparedCachePackages[@]})); then
            patchShebangs "${bunPreparedCachePackages[@]}"
        fi
        # Only selected packages are prepared, leaving foreign OS/CPU/libc
        # variants in the all-platform cache untouched.
        bunPatchElf . "${bunPreparedCachePackages[@]}"

        runHook preBunInstallScripts

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
        patchShebangs node_modules
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
