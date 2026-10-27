# shellcheck shell=bash

# The upstream nodejsInstallExecutables hook can use Bun via hostNode, but its
# string-bin handling uses the full scoped name, and splits bin paths on spaces.
bunInstallExecutables() {
    local packageJson=$1 packageOut=$2 binName binPath entry
    local -a wrapperFlags=()
    concatTo wrapperFlags makeWrapperArgs makeWrapperArgsArray

    while IFS= read -r entry; do
        binName=$(@jq@/bin/jq -r '.key' <<< "$entry")
        binPath=$(@jq@/bin/jq -r '.value' <<< "$entry")
        makeWrapper @bun@/bin/bun "$out/bin/$binName" \
            --add-flags "$(printf '%q' "$packageOut/$binPath")" "${wrapperFlags[@]}"
    done < <(@jq@/bin/jq -c 'if (.bin | type) == "string" then {key: (.name | split("/") | last), value: .bin} elif (.bin | type) == "object" then .bin | to_entries[] else empty end' "$packageJson")
}

# The pinned nodejsInstallManuals hook checks for jq type "list"; jq uses
# "array", so it does not install manuals from an array-valued man field.
bunInstallManuals() {
    local packageJson=$1 packageOut=$2 man

    while IFS= read -r man; do
        installManPage "$packageOut/$man"
    done < <(@jq@/bin/jq -r 'if (.man | type) == "string" then .man elif (.man | type) == "array" then .man[] else empty end' "$packageJson")
}

# Keep the project-relative layout: workspace links and isolated-linker links
# can point outside a package's own node_modules. Pack each linked local package
# and copy its node_modules, rather than copying links to the build directory.
# The visited set handles cycles/shared links. Registry/.bun store entries are
# already copied; only links to local source packages extend the traversal.
bunInstallPackageTree() {
    local projectRoot=$1 projectOut=$2 current currentOut link sourceLink target relative targetOut
    local -a pending=("$projectRoot" "${projectRoot}/${bunWorkspace:-.}")
    local -A installed=()
    local -a packFlags=()
    concatTo packFlags bunFlags bunFlagsArray bunPackFlags bunPackFlagsArray

    while (( ${#pending[@]} )); do
        current=$(realpath "${pending[0]}")
        pending=("${pending[@]:1}")
        if [[ -n ${installed[$current]-} ]]; then continue; fi
        installed[$current]=1
        relative=$(realpath --relative-to="$projectRoot" "$current")
        if [[ $relative == .. || $relative == ../* ]]; then
            echo "bunInstallHook: local package is outside bunRoot: $current" >&2
            exit 1
        fi
        currentOut="$projectOut/$relative"
        mkdir -p "$currentOut"
        pushd "$current" >/dev/null
        # Bun has no machine-readable file list like `npm pack --json`. The
        # archive preserves its publish-file selection, including files/ignores.
        if [[ $current == "$projectRoot" && -n ${bunWorkspace-} ]] && ! @jq@/bin/jq -e '.version' package.json >/dev/null; then
            # A private workspace container often has no version and cannot be
            # packed. Its metadata and node_modules still anchor the layout.
            cp package.json "$currentOut/package.json"
        else
            bun pm pack "${packFlags[@]}" --ignore-scripts --filename "$TMPDIR/package.tgz"
            # Bundled dependencies can appear in the archive. Copy the pruned
            # installed tree below so bundled and unbundled packages agree.
            tar -xzf "$TMPDIR/package.tgz" -C "$currentOut" --strip-components=1 --exclude='*/node_modules' --exclude='*/node_modules/*'
        fi
        popd >/dev/null

        if [[ ! -d $current/node_modules ]]; then continue; fi
        # A root pack may already have included a workspace's files.
        rm -rf "$currentOut/node_modules"
        cp -R "$current/node_modules" "$currentOut/node_modules"
        while IFS= read -r -d "" link; do
            sourceLink="$current/node_modules/${link#"$currentOut/node_modules/"}"
            target=$(realpath "$sourceLink")
            case "$target" in
                "$projectRoot"|"$projectRoot"/*)
                    relative=$(realpath --relative-to="$projectRoot" "$target")
                    targetOut="$projectOut/$relative"
                    ln -sfn "$(realpath -m --relative-to="$(dirname "$link")" "$targetOut")" "$link"
                    # Registry packages, including .bun store entries, were
                    # copied with node_modules. Only local packages need packing.
                    if [[ /$relative/ != */node_modules/* && -f $target/package.json ]]; then
                        pending+=("$target")
                    fi
                    ;;
                /nix/store/*) ;;
                *)
                    echo "bunInstallHook: dependency link escapes bunRoot: $sourceLink -> $target" >&2
                    exit 1
                    ;;
            esac
        done < <(find "$currentOut/node_modules" -type l -print0)
    done
}

bunInstallHook() {
    echo "Executing bunInstallHook"
    pushd "${bunRoot:-.}" >/dev/null

    runHook preInstall

    local projectRoot packageName packageOut selectedPackage
    projectRoot=$(pwd -P)
    packageName=$(@jq@/bin/jq -er '.name' package.json)
    packageOut="$out/lib/node_modules/$packageName"
    selectedPackage="${bunWorkspace:-.}"

    if [[ -z ${dontBunPrune-} ]]; then
        local -a pruneFlags=()
        concatTo pruneFlags bunFlags bunFlagsArray bunPruneFlags bunPruneFlagsArray
        bun prune "${pruneFlags[@]}" --production
    fi
    bunInstallPackageTree "$projectRoot" "$packageOut"

    bunInstallExecutables "$selectedPackage/package.json" "$packageOut/$selectedPackage"
    bunInstallManuals "$selectedPackage/package.json" "$packageOut/$selectedPackage"

    runHook postInstall
    popd >/dev/null
    echo "Finished bunInstallHook"
}

if [[ -z ${dontBunInstall-} && -z ${installPhase-} ]]; then
    installPhase=bunInstallHook
fi
