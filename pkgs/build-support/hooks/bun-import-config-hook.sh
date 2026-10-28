# shellcheck shell=bash
# These variables form the interface with the propagated bunConfigHook.
# shellcheck disable=SC2034,SC2154

# The propagated bunConfigHook owns installation, patching, and lifecycle scripts.
# Replace only dependency preparation for the importer source-bundle interface.
bunDepsFormatVersion=2
bunDependencySetupHook=bunSetupImportedDependencies
bunSetupImportedDependencies() {
    export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
    mkdir -p "$BUN_INSTALL_CACHE_DIR"
    bun @rewriteLock@ "$bunDeps"
}
