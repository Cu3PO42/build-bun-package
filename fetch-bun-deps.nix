{
  lib,
  stdenvNoCC,
  bun,
  cacert,
}:

{
  name ? "bun-deps",
  hash ? "",
  bunRoot ? ".",
  bunFlags ? [ ],
  bunFetchFlags ? [ ],
  nativeBuildInputs ? [ ],
  ...
}@args:
assert lib.assertMsg (lib.versionAtLeast bun.version "1.4.4") "fetchBunDeps requires Bun >= 1.4.4";
stdenvNoCC.mkDerivation (
  finalAttrs:
  args
  // {
    inherit name;
    inherit
      bunRoot
      bunFlags
      bunFetchFlags
      ;
    nativeBuildInputs = nativeBuildInputs ++ [
      bun
      cacert
    ];
    strictDeps = args.strictDeps or true;
    dontConfigure = true;
    dontBuild = true;
    installPhase =
      args.installPhase or ''
        runHook preInstall
        export HOME="$TMPDIR/home" BUN_INSTALL_CACHE_DIR="$out" BUN_CONFIG_NO_CLEAR_TERMINAL=1 BUN_INSTALL_GLOBAL_STORE=0
        mkdir -p "$HOME" "$out"
        cd "$bunRoot"
        if [[ -f bun.lock ]]; then lockfile=bun.lock
        elif [[ -f bun.lockb ]]; then lockfile=bun.lockb
        else echo "fetchBunDeps: a committed bun.lock or bun.lockb is required" >&2; exit 1
        fi
        # Refuse manifest/lockfile drift even though fetching never saves a lock.
        # Fetch every optional platform variant for a platform-independent cache.
        bun pm fetch ${lib.escapeShellArgs finalAttrs.bunFlags} "''${bunFlagsArray[@]}" --frozen-lockfile --os '*' --cpu '*' --libc '*' ${lib.escapeShellArgs finalAttrs.bunFetchFlags} "''${bunFetchFlagsArray[@]}"
        rm -rf "$out/.tmp"
        while IFS= read -r -d "" link; do
          target=$(readlink "$link")
          ln -srfT "$target" "$link"
        done < <(find "$out" -type l -lname "$out/*" -print0)
        mkdir -p "$out/.nix-bun"
        printf '1\n' > "$out/.nix-bun/format-version"
        cp "$lockfile" "$out/.nix-bun/$lockfile"
        runHook postInstall
      '';
    outputHash = finalAttrs.hash or hash;
    outputHashAlgo = if (finalAttrs.hash or hash) == "" then "sha256" else null;
    outputHashMode = "recursive";
    dontFixup = true;
    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ (args.impureEnvVars or [ ]);
  }
)
