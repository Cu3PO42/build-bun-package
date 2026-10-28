# shellcheck shell=bash

bunSetBuildRuntime() {
    # Run after stdenv has assembled PATH so the selected build runtime wins
    # over incidental Node.js inputs. The store path also works in shebangs.
    export PATH="@buildRuntimeNodeShim@/bin:$PATH"
}

postHooks+=(bunSetBuildRuntime)
