{
  lib,
  stdenv,
  buildBunPackage,
  fetchFromGitHub,
}:

# Based on nixpkgs pkgs/by-name/ba/balatro-mod-manager/package.nix.
# Exercises a Svelte/Tauri frontend whose dependency install needs scripts enabled.
buildBunPackage (finalAttrs: {
  pname = "balatro-mod-manager-web";
  version = "0.4.1";
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "skyline69";
    repo = "balatro-mod-manager";
    tag = "v${finalAttrs.version}";
    hash = "sha256-cazd6Cns87cjwBORQIsAD5rBes7eTGCAz7bytZO+TsQ=";
  };

  bunDepsHash =
    {
      "aarch64-darwin" = "sha256-GyQMh30hViIz/HkYG2nawnvqi7X1Y6iUWfIt61qZFBA=";
      "aarch64-linux" = "sha256-lhehtsYyZB4MvskPHovGmoCXQHuDpjuHE8zgHVszqDo=";
      "x86_64-linux" = "sha256-Xnd3srXf9xxIUadY+26ZBEOnG5POdzyBy9O+xiMDiaI=";
    }
    .${stdenv.hostPlatform.system};
  bunFetchFlags = [
    "--os=${stdenv.hostPlatform.node.platform}"
    "--cpu=${stdenv.hostPlatform.node.arch}"
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ "--libc=glibc" ];
  bunRunScripts = true;
  bunInstallFlags = [
    "--allow-scripts"
    "--no-progress"
  ];

  bunBuildScript = "build";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/balatro-mod-manager
    cp -R build $out/share/balatro-mod-manager/

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s "$out/share/balatro-mod-manager/build/index.html"
    runHook postInstallCheck
  '';

  meta = {
    description = "Frontend build for the Balatro Mod Manager";
    homepage = "https://balatro-mod-manager.dasguney.com/";
    license = lib.licenses.gpl3Plus;
    mainProgram = "balatro-mod-manager-web";
    platforms = lib.platforms.unix;
  };
})
