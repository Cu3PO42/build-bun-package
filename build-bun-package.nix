{
  lib,
  stdenv,
  bun,
  fetchBunDeps,
  makeWrapper,
  jq,
}:

{
  pname,
  version,
  src,
  bunDepsHash ? "",
  bunDeps ? null,
  sourceRoot ? null,
  patches ? [ ],
  prePatch ? "",
  postPatch ? "",
  bunRoot ? ".",
  bunFetchFlags ? [ ],
  bunInstallFlags ? [ ],
  bunBuildScript ? "build",
  bunBuildFlags ? [ ],
  bunPackFlags ? [ ],
  dontBunBuild ? false,
  dontBunPrune ? false,
  nativeBuildInputs ? [ ],
  ...
}@args:

let
  deps =
    if bunDeps != null then
      bunDeps
    else
      fetchBunDeps {
        name = "${pname}-${version}-bun-deps";
        inherit
          src
          sourceRoot
          patches
          prePatch
          postPatch
          bunRoot
          bunFetchFlags
          ;
        hash = bunDepsHash;
      };
in
assert lib.assertMsg (lib.versionAtLeast bun.version "1.4.4")
  "buildBunPackage requires Bun >= 1.4.4";
stdenv.mkDerivation (
  (builtins.removeAttrs args [
    "bunDepsHash"
    "bunDeps"
    "bunFetchFlags"
    "bunInstallFlags"
    "bunBuildFlags"
    "bunPackFlags"
  ])
  // {
    inherit
      pname
      version
      src
      sourceRoot
      patches
      prePatch
      postPatch
      ;
    bunDeps = deps;
    nativeBuildInputs = nativeBuildInputs ++ [
      bun
      makeWrapper
      jq
    ];
    strictDeps = args.strictDeps or true;
    dontStrip = args.dontStrip or true;

    configurePhase =
      args.configurePhase or ''
        runHook preConfigure
        export HOME="$TMPDIR/home"
        export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
        export BUN_CONFIG_NO_CLEAR_TERMINAL=1
        mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR"
        cd ${lib.escapeShellArg bunRoot}
        cp -R "$bunDeps"/. "$BUN_INSTALL_CACHE_DIR/"
        chmod -R u+w "$BUN_INSTALL_CACHE_DIR"
        bun install ${lib.escapeShellArgs bunInstallFlags} --offline --frozen-lockfile
        runHook postConfigure
      '';

    buildPhase =
      args.buildPhase or ''
        runHook preBuild
        ${lib.optionalString (!dontBunBuild) ''
          bun run ${lib.escapeShellArg bunBuildScript} ${lib.escapeShellArgs bunBuildFlags}
        ''}
        runHook postBuild
      '';

    installPhase =
      args.installPhase or ''
        runHook preInstall
        packageName=$(jq -er '.name' package.json)
        packageOut="$out/lib/node_modules/$packageName"
        mkdir -p "$packageOut"
        # Use Bun's package file selection (files/.npmignore), without re-running
        # prepare scripts after the build phase.
        bun pm pack ${lib.escapeShellArgs bunPackFlags} --ignore-scripts --filename "$TMPDIR/package.tgz"
        tar -xzf "$TMPDIR/package.tgz" -C "$packageOut" --strip-components=1
        ${lib.optionalString (!dontBunPrune) ''
          bun prune --production
        ''}
        if [[ -d node_modules ]]; then
          cp -R node_modules "$packageOut/node_modules"
        fi
        # Run package bins with Bun, regardless of an upstream node shebang.
        while IFS= read -r entry; do
          binName=$(jq -r '.key' <<< "$entry")
          binPath=$(jq -r '.value' <<< "$entry")
          makeWrapper ${lib.getExe bun} "$out/bin/$binName" \
            --add-flags "$(printf '%q' "$packageOut/$binPath")"
        done < <(jq -c '
          if (.bin | type) == "string" then
            {key: (.name | split("/") | last), value: .bin}
          elif (.bin | type) == "object" then
            .bin | to_entries[]
          else empty end
        ' package.json)
        runHook postInstall
      '';

    passthru = (args.passthru or { }) // {
      bunDeps = deps;
    };
    meta = {
      platforms = bun.meta.platforms;
    }
    // (args.meta or { });
  }
)
