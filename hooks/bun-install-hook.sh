# shellcheck shell=bash

# The upstream nodejsInstallExecutables hook can use Bun via hostNode, but its
# string-bin handling uses the full scoped name, and splits bin paths on spaces.
bunInstallExecutables() {
    local packageJson=$1 packageOut=$2 binName binPath entry

    while IFS= read -r entry; do
        binName=$(@jq@/bin/jq -r '.key' <<< "$entry")
        binPath=$(@jq@/bin/jq -r '.value' <<< "$entry")
        makeWrapper @bun@/bin/bun "$out/bin/$binName" \
            --add-flags "$(printf '%q' "$packageOut/$binPath")" ${makeWrapperArgs-} "${makeWrapperArgsArray[@]}"
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

bunInstallHook() {
    echo "Executing bunInstallHook"
    pushd "${bunRoot:-.}" >/dev/null

    runHook preInstall

    local packageName packageOut
    packageName=$(@jq@/bin/jq -er '.name' package.json)
    packageOut="$out/lib/node_modules/$packageName"
    mkdir -p "$packageOut"
    bun pm pack ${bunPackFlags-} "${bunPackFlagsArray[@]}" --ignore-scripts --filename "$TMPDIR/package.tgz"
    tar -xzf "$TMPDIR/package.tgz" -C "$packageOut" --strip-components=1 --exclude='package/node_modules' --exclude='package/node_modules/*'

    if [[ -z ${dontBunPrune-} ]]; then
        bun prune --production ${bunPruneFlags-} "${bunPruneFlagsArray[@]}"
    fi
    if [[ -d node_modules ]]; then cp -R node_modules "$packageOut/node_modules"; fi

    bunInstallExecutables package.json "$packageOut"
    bunInstallManuals package.json "$packageOut"

    runHook postInstall
    popd >/dev/null
    echo "Finished bunInstallHook"
}

if [[ -z ${dontBunInstall-} && -z ${installPhase-} ]]; then
    installPhase=bunInstallHook
fi
