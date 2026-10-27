{
  lib,
  stdenv,
  buildBunPackage,
  fetchFromGitHub,
  makeWrapper,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:

# Based on nixpkgs pkgs/by-name/fi/filen-cli/package.nix.
# Exercises Bun's standalone compile target and a binary that must avoid stripping.
buildBunPackage (finalAttrs: {
  pname = "filen-cli";
  version = "0.0.36";
  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "FilenCloudDienste";
    repo = "filen-cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-2FN9KygSGir/vtHdKXX0zUeug2O6tgAc1PBhzD9HPqY=";
  };

  bunDepsHash = "sha256-nvT50YsC+MLEkiraxtsRwmoPEkxoVLjqt0nM3WdLwFU=";
  # Filen patches two dependency packages; Bun materializes those patches in its cache.
  makeCacheWritable = true;
  bunFlags = [ "--no-progress" ];
  bunInstallFlags = [
    "--force"
    "--production"
  ];

  buildPhase = ''
    runHook preBuild

    bun build \
      --compile \
      --target=bun \
      --minify \
      --sourcemap src/index.ts \
      --outfile dist/filen \
      --define IS_RUNNING_AS_BINARY=true \
      --define "VERSION=v${finalAttrs.version}"

    runHook postBuild
  '';

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 dist/filen $out/bin/filen
    wrapProgram $out/bin/filen \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.cc ]}"

    runHook postInstall
  '';

  dontStrip = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  preVersionCheck = ''
    cat > filen-version << EOF
    #!/bin/sh
    exec $out/bin/filen --skip-update "\$@"
    EOF
    chmod +x filen-version
    versionCheckProgram="$(pwd)/filen-version"
  '';
  doInstallCheck = true;

  meta = {
    description = "CLI tool for interacting with the Filen cloud";
    homepage = "https://github.com/FilenCloudDienste/filen-cli";
    license = lib.licenses.agpl3Only;
    mainProgram = "filen";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
})
