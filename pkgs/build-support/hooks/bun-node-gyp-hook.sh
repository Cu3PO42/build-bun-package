# shellcheck shell=bash

# Bun's node-gyp shim otherwise invokes `bun x node-gyp`, downloading a tool.
# This wrapper runs pinned standalone node-gyp with the selected runtime.
export npm_config_node_gyp="@nodeGyp@"
# Target the installed runtime, independently of the runtime executing node-gyp.
export npm_config_nodedir="@nodeHeaders@"
export npm_config_target="@nodeVersion@"
export npm_config_python="@python@"
