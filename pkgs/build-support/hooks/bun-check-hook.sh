# shellcheck shell=bash

bunCheckHook() {
    echo "Executing bunCheckHook"
    pushd "${bunRoot:-.}/${bunWorkspace:-.}" >/dev/null || return

    runHook preCheck

    local -a runFlags=() checkFlags=()
    concatTo runFlags bunFlags bunFlagsArray
    concatTo checkFlags bunCheckFlags bunCheckFlagsArray
    if [[ -n ${bunCheckScript-} ]]; then
        bun run "${runFlags[@]}" "$bunCheckScript" "${checkFlags[@]}"
    else
        bun test "${runFlags[@]}" "${checkFlags[@]}"
    fi

    runHook postCheck

    popd >/dev/null || return
    echo "Finished bunCheckHook"
}

if [[ -z ${dontBunCheck-} && -z ${checkPhase-} ]]; then
    checkPhase=bunCheckHook
fi
