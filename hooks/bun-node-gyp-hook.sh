# shellcheck shell=bash

# Bun's node-gyp shim otherwise invokes `bun x node-gyp`, downloading a tool.
# This wrapper runs standalone node-gyp with Bun, without npm or Node.js.
export npm_config_node_gyp="@nodeGyp@"
# Use local headers and their explicit target version, independently of the
# Node.js compatibility version reported by the selected Bun runtime.
export npm_config_nodedir="@nodeHeaders@"
export npm_config_target="@nodeVersion@"
export npm_config_python="@python@"
