# shellcheck shell=bash
bunBuildHook() {
    pushd "${bunRoot:-.}" >/dev/null
    runHook preBuild
    bun run "${bunBuildScript:-build}" ${bunBuildFlags-} "${bunBuildFlagsArray[@]}"
    runHook postBuild
    popd >/dev/null
}
if [[ -z ${dontBunBuild-} && -z ${buildPhase-} ]]; then
    buildPhase=bunBuildHook
fi
