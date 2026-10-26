# shellcheck shell=bash
bunInstallHook() {
    pushd "${bunRoot:-.}" >/dev/null
    runHook preInstall
    local packageName packageOut binName binPath entry
    packageName=$(@jq@/bin/jq -er '.name' package.json)
    packageOut="$out/lib/node_modules/$packageName"
    mkdir -p "$packageOut"
    bun pm pack ${bunPackFlags-} "${bunPackFlagsArray[@]}" --ignore-scripts --filename "$TMPDIR/package.tgz"
    tar -xzf "$TMPDIR/package.tgz" -C "$packageOut" --strip-components=1 --exclude='package/node_modules' --exclude='package/node_modules/*'
    if [[ -z ${dontBunPrune-} ]]; then bun prune --production; fi
    if [[ -d node_modules ]]; then cp -R node_modules "$packageOut/node_modules"; fi
    while IFS= read -r entry; do
        binName=$(@jq@/bin/jq -r '.key' <<< "$entry")
        binPath=$(@jq@/bin/jq -r '.value' <<< "$entry")
        makeWrapper @bun@/bin/bun "$out/bin/$binName" \
            --add-flags "$(printf '%q' "$packageOut/$binPath")" ${makeWrapperArgs-} "${makeWrapperArgsArray[@]}"
    done < <(@jq@/bin/jq -c 'if (.bin | type) == "string" then {key: (.name | split("/") | last), value: .bin} elif (.bin | type) == "object" then .bin | to_entries[] else empty end' package.json)
    while IFS= read -r man; do
        installManPage "$packageOut/$man"
    done < <(@jq@/bin/jq -r 'if (.man | type) == "string" then .man elif (.man | type) == "array" then .man[] else empty end' package.json)
    runHook postInstall
    popd >/dev/null
}
if [[ -z ${dontBunInstall-} && -z ${installPhase-} ]]; then
    installPhase=bunInstallHook
fi
