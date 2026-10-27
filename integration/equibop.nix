{
  lib,
  stdenv,
  buildBunPackage,
  fetchFromGitHub,
  electron_43,
  autoPatchelfHook,
  copyDesktopItems,
  jq,
  libpulseaudio,
  makeDesktopItem,
  makeWrapper,
  nodejs,
  pipewire,
  python3Packages,
}:
let
  electron = electron_43;
in

# Based on nixpkgs pkgs/by-name/eq/equibop/package.nix.
# Exercises an Electron build, arrpc bundle compilation, and app.asar packaging.
buildBunPackage (finalAttrs: {
  pname = "equibop";
  version = "3.2.2";
  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "Equicord";
    repo = "Equibop";
    tag = "v${finalAttrs.version}";
    hash = "sha256-foKgtyN1jr4+PHwJHTVXrYzWNVYtR1Sq8rLG4VEnujs=";
  };

  bunDepsHash = {
    "aarch64-linux" = "sha256-MCS7tdSYlSwmFsqFflSBr1AQtUFn9bp5Wk++IUaCkQI=";
    "x86_64-linux" = "sha256-bjTWv3MUgdgxkl6S2cnQ8Zz+aABmxI2eJ1RwCl7mRP0=";
  }.${stdenv.hostPlatform.system};
  bunFetchFlags = [
    "--os=linux"
    "--cpu=${stdenv.hostPlatform.node.arch}"
    "--libc=glibc"
  ];
  bunInstallFlags = [
    "--filter=equibop"
    "--force"
    "--linker=hoisted"
    "--no-progress"
  ];

  postPatch = ''
    substituteInPlace scripts/build/build.mts \
      --replace-fail 'gitHash = execSync("git rev-parse HEAD", { encoding: "utf-8" }).trim();' 'gitHash = "${finalAttrs.src.hash}"'

    substituteInPlace src/main/updater.ts \
      --replace-fail 'const isOutdated = autoUpdater.checkForUpdates().then(res => Boolean(res?.isUpdateAvailable));' 'const isOutdated = false;'

    substituteInPlace scripts/build/compileArrpc.mts \
      --replace-fail -baseline ""
  '';

  autoPatchelfIgnoreMissingDeps = [ "libc.musl-*.so.*" ];

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    jq
    makeWrapper
    nodejs
    python3Packages.icnsutil
  ];

  buildInputs = [
    libpulseaudio
    pipewire
    (lib.getLib stdenv.cc.cc)
  ];

  preBuild = ''
    if [ "$(jq -r '.devDependencies.electron' < package.json | cut -d. -f1 | tr -d '^')" != "${lib.versions.major electron.version}" ]; then
      echo "ERROR: Electron version mismatch between package.json and nixpkgs"
      exit 1
    fi

    cp -r ${electron.dist} electron-dist
    chmod -R u+w electron-dist
  '';

  buildPhase = ''
    runHook preBuild

    bun run build
    bun run compileArrpc
    node node_modules/electron-builder/out/cli/cli.js \
      --dir \
      -c.electronDist=electron-dist \
      -c.electronVersion=${electron.version} \
      -c.npmRebuild=false

    pushd build
    icnsutil e icon.icns
    popd

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/Equibop
    cp -r dist/*unpacked/resources $out/opt/Equibop/

    for file in build/icon.icns.export/*.png; do
      base=''${file##*/}
      size=''${base/x*/}
      install -Dm0644 $file $out/share/icons/hicolor/''${size}x''${size}/apps/equibop.png
    done
    install -Dm0644 build/icon.svg $out/share/icons/hicolor/scalable/apps/equibop.svg

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper ${lib.getExe electron} $out/bin/equibop \
      --add-flags $out/opt/Equibop/resources/app.asar \
      --run 'if [[ "''${NIXOS_SPEECH:-default}" != "False" ]]; then NIXOS_SPEECH=True; else unset NIXOS_SPEECH; fi' \
      --add-flags "''${NIXOS_SPEECH:+--enable-speech-dispatcher}" \
      --add-flags "''${NIXOS_OZONE_WL:+''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ (lib.getLib stdenv.cc.cc) ]}"
  '';

  desktopItems = makeDesktopItem {
    name = "equibop";
    desktopName = "Equibop";
    exec = "equibop %U";
    icon = "equibop";
    startupWMClass = "Equibop";
    genericName = "Internet Messenger";
    keywords = [
      "discord"
      "equibop"
      "electron"
      "chat"
    ];
    categories = [
      "Network"
      "InstantMessaging"
      "Chat"
    ];
  };

  meta = {
    description = "Custom Discord App aiming to give you better performance and improve Linux support";
    homepage = "https://equicord.org";
    license = lib.licenses.gpl3Plus;
    mainProgram = "equibop";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
})
