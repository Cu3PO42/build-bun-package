# shellcheck shell=bash

# Bun's node-gyp shim otherwise invokes `bun x node-gyp`, downloading a tool.
# This launcher runs pinned standalone node-gyp with the build's node command.
export npm_config_node_gyp="@nodeGyp@"
# Target nodeGypTarget, independently of the interpreter executing node-gyp.
export npm_config_nodedir="@nodeHeaders@"
export npm_config_target="@nodeVersion@"
export npm_config_python="@python@"

bunCheckNodeGypHeaders() {
    if @checkBunHeaders@; then
        local actual
        actual=$(@nodeGypTarget@ -p process.versions.node)
        if [[ $actual != @nodeVersion@ ]]; then
            echo "warning: bunNodeGypHook: target Bun reports Node $actual, but @nodeHeaders@ provides Node @nodeVersion@ headers. Node-API addons may still be compatible; this mismatch may explain native addon build or loading errors." >&2
        fi
    fi
}

postHooks+=(bunCheckNodeGypHeaders)
