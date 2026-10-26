# shellcheck shell=bash
bunBuildHook() {
    echo "Executing bunBuildHook"
    pushd "${bunRoot:-.}" >/dev/null

    runHook preBuild
    bun run "${bunBuildScript:-build}" ${bunBuildFlags-} "${bunBuildFlagsArray[@]}"
    runHook postBuild
    popd >/dev/null
    echo "Finished bunBuildHook"
}

if [[ -z ${dontBunBuild-} && -z ${buildPhase-} ]]; then
    buildPhase=bunBuildHook
fi
