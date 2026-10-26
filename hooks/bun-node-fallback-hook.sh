# shellcheck shell=bash

bunAddNodeFallback() {
    # Run after stdenv has assembled PATH so an explicitly supplied Node wins.
    # Unlike Bun's temporary child-process shim, this store path also works in
    # shell phases and remains valid in shebangs patched into installed files.
    if ! command -v node >/dev/null 2>&1; then
        addToSearchPath PATH @bunNodeShim@/bin
    fi
}

postHooks+=(bunAddNodeFallback)
