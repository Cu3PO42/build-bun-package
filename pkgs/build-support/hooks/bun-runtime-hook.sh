# shellcheck shell=bash

# shellcheck source=/dev/null
source @envSplitFixup@

bunSetupRuntime() {
    # Run after stdenv has assembled PATH so caller-supplied Node takes priority.
    if ! command -v node >/dev/null 2>&1; then
        addToSearchPath PATH @bunNodeShim@/bin
    fi
    export HOST_PATH="@runtimeNodeShim@/bin:@coreutils@/bin:$HOST_PATH"
}

# prefix, output and outputDev are supplied by stdenv's output fixup.
# shellcheck disable=SC2154
bunPatchOutputShebangs() {
    # Early patching selects build interpreters, including store paths. Resolve
    # them again for the output's consumer, even after a custom install phase.
    if [[ -n ${dontPatchShebangs-} || ! -e $prefix ]]; then
        return
    fi
    local searchPath=$HOST_PATH
    local -a flags=(--host --update)
    if [[ $output != out && $output == "$outputDev" ]]; then
        searchPath=$PATH
        flags=(--build --update)
    fi
    patchShebangs "${flags[@]}" "$prefix"
    bunFixupEnvSplitShebangs "$searchPath" "$prefix"
}

postHooks+=(bunSetupRuntime)
fixupOutputHooks+=(bunPatchOutputShebangs)
