# shellcheck shell=bash

# shellcheck source=/dev/null
source @envSplitFixup@

bunSetBuildRuntime() {
    # Run after stdenv has assembled PATH so the selected build runtime wins
    # over incidental Node.js inputs. A temporary interpreter remains eligible
    # for stdenv's ordinary output shebang fixup after any install phase.
    bunBuildRuntimeBin=$(mktemp -d "$TMPDIR/bun-node.XXXXXXXXXX")
    ln -s @buildRuntimeNodeShim@/bin/node "$bunBuildRuntimeBin/node"
    export PATH="$bunBuildRuntimeBin:$PATH"
    export HOST_PATH="@runtimeNodeShim@/bin:@coreutils@/bin:$HOST_PATH"
}

bunSetFixupBuildRuntime() {
    # stdenv patches development outputs with --build. Those scripts must also
    # receive a permanent interpreter instead of the temporary build shim.
    export PATH="@buildRuntimeNodeShim@/bin:$PATH"
}

postHooks+=(bunSetBuildRuntime)
preFixupHooks+=(bunSetFixupBuildRuntime)
