# shellcheck shell=bash
# stdenv enables errexit, so failed directory changes abort the build.
# shellcheck disable=SC2164

bunBuildHook() {
    echo "Executing bunBuildHook"
    pushd "${bunRoot:-.}/${bunWorkspace:-.}" >/dev/null

    runHook preBuild

    if [[ -z ${bunBuildScript-} ]]; then
        echo 'bunBuildHook: set bunBuildScript, override buildPhase, or set dontBunBuild = true' >&2
        exit 1
    fi

    local -a runFlags=() buildFlags=()
    concatTo runFlags bunFlags bunFlagsArray
    concatTo buildFlags bunBuildFlags bunBuildFlagsArray
    bun run "${runFlags[@]}" "$bunBuildScript" "${buildFlags[@]}"

    runHook postBuild

    popd >/dev/null
    echo "Finished bunBuildHook"
}

if [[ -z ${dontBunBuild-} && -z ${buildPhase-} ]]; then
    buildPhase=bunBuildHook
fi
