# shellcheck shell=bash

bunBuildHook() {
    echo "Executing bunBuildHook"
    pushd "${bunRoot:-.}" >/dev/null

    runHook preBuild

    if [[ -z ${bunBuildScript-} ]]; then
        echo 'bunBuildHook: set bunBuildScript, override buildPhase, or set dontBunBuild = true' >&2
        exit 1
    fi

    bun run ${bunRunFlags-} "${bunRunFlagsArray[@]}" "$bunBuildScript" ${bunBuildFlags-} "${bunBuildFlagsArray[@]}"

    runHook postBuild

    popd >/dev/null
    echo "Finished bunBuildHook"
}

if [[ -z ${dontBunBuild-} && -z ${buildPhase-} ]]; then
    buildPhase=bunBuildHook
fi
