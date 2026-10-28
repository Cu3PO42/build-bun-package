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
        # Isolate Bun's user configuration and write its dependency cache
        # directly to the fixed-output path, without installing node_modules.
        export HOME="$TMPDIR/home" BUN_INSTALL_CACHE_DIR="$out" BUN_CONFIG_NO_CLEAR_TERMINAL=1 BUN_INSTALL_GLOBAL_STORE=0
        mkdir -p "$HOME" "$out"
        cd "$bunRoot"
        if [[ -f bun.lock ]]; then lockfile=bun.lock
        elif [[ -f bun.lockb ]]; then lockfile=bun.lockb
        else echo "fetchBunDeps: a committed bun.lock or bun.lockb is required" >&2; exit 1
        fi
        # Refuse manifest/lockfile drift even though fetching never saves a lock.
        # Fetch optional platform variants supported by Bun for a platform-independent cache.
        # Render the Nix flag lists once, preserving argument boundaries even
        # without structured attrs. The inherited shell variables are not
        # expanded here; *FlagsArray provide separate shell-hook additions.
        bun pm fetch ${lib.escapeShellArgs finalAttrs.bunFlags} "''${bunFlagsArray[@]}" --frozen-lockfile --os '*' --cpu '*' --libc '*' ${lib.escapeShellArgs finalAttrs.bunFetchFlags} "''${bunFetchFlagsArray[@]}"
        # Temporary download/extraction files are not part of the reusable cache.
        rm -rf "$out/.tmp"
        # Bun can create absolute aliases to other entries in this cache (for
        # example, Git dependencies sharing a checkout). Make those links
        # relative so the content hash does not depend on the output path and
        # a writable copy of the cache refers to its own entries.
        while IFS= read -r -d "" link; do
          target=$(readlink "$link")
          # -r computes the target relative to the link's parent; -f replaces
          # the link, and -T prevents following it as a destination directory.
          ln -srfT "$target" "$link"
        done < <(find "$out" -type l -lname "$out/*" -print0)
        # The offline install hook checks the format, version, and exact lockfile
        # snapshot before using the cache with a package's prepared source.
        mkdir -p "$out/.nix-bun"
        printf 'extracted-cache\n' > "$out/.nix-bun/format"
        printf '1\n' > "$out/.nix-bun/format-version"
        cp "$lockfile" "$out/.nix-bun/$lockfile"
        runHook postInstall
      '';
    outputHash = finalAttrs.hash or hash;
    outputHashAlgo = if (finalAttrs.hash or hash) == "" then "sha256" else null;
    outputHashMode = "recursive";
    # Patch shebangs and binaries only when installing from this pristine cache.
    dontFixup = true;
    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ (args.impureEnvVars or [ ]);
  }
)
