{
  lib,
  stdenvNoCC,
  bun,
  cacert,
}:

{
  name ? "bun-deps",
  src,
  hash ? "",
  sourceRoot ? null,
  patches ? [ ],
  prePatch ? "",
  postPatch ? "",
  bunRoot ? ".",
  bunFetchFlags ? [ ],
}:

assert lib.assertMsg (lib.versionAtLeast bun.version "1.4.4") "fetchBunDeps requires Bun >= 1.4.4";
stdenvNoCC.mkDerivation {
  inherit
    name
    src
    patches
    prePatch
    postPatch
    ;
  inherit sourceRoot;

  nativeBuildInputs = [
    bun
    cacert
  ];
  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    export HOME="$TMPDIR/home"
    export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
    export BUN_CONFIG_NO_CLEAR_TERMINAL=1
    mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR"
    cd ${lib.escapeShellArg bunRoot}
    if [[ ! -f bun.lock && ! -f bun.lockb ]]; then
      echo "fetchBunDeps: a committed bun.lock or bun.lockb is required" >&2
      exit 1
    fi
    # Fetch every platform so one hash can be shared by Darwin and Linux.
    # Fetch never runs lifecycle scripts or installs node_modules.
    bun pm fetch --os '*' --cpu '*' --libc '*' ${lib.escapeShellArgs bunFetchFlags}
    # Round-trip through a pack to retain only lockfile entries. The pack itself
    # follows filesystem traversal order, so its bytes differ across hosts.
    bun pm cache pack "$TMPDIR/bun-cache.pack"
    export BUN_INSTALL_CACHE_DIR="$out"
    bun pm cache unpack "$TMPDIR/bun-cache.pack"
    # Linux may create this scratch directory while opening a new cache.
    rm -rf "$out/.tmp"
    # Bun recreates absolute index symlinks on unpack. Keep package symlinks
    # intact, and make only links into this cache relative and relocatable.
    while IFS= read -r -d "" link; do
      target=$(readlink "$link")
      ln -srfT "$target" "$link"
    done < <(find "$out" -type l -lname "$out/*" -print0)
    runHook postInstall
  '';

  outputHash = hash;
  outputHashAlgo = "sha256";
  outputHashMode = "recursive";
  dontFixup = true;

  # Like other network fetchers, honor the builder's proxy configuration.
  impureEnvVars = lib.fetchers.proxyImpureEnvVars;
}
