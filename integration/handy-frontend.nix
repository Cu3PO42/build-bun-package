{
  lib,
  stdenv,
  buildBunPackage,
  fetchFromGitHub,
}:

# Based on nixpkgs pkgs/by-name/ha/handy/package.nix.
# Exercises an isolated install, lifecycle scripts, and Handy's cache normalizer.
buildBunPackage (finalAttrs: {
  pname = "handy-frontend";
  version = "0.9.8";
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "cjpais";
    repo = "Handy";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3j73ss9pwkcK4MfeNY/9PFp//Cbc0OSICDdlmHprSso=";
  };

  bunDepsHash =
    {
      "aarch64-darwin" = "sha256-XoAbBfMmGgoC42BYtFEQGjiRiJKwogzYzT8YKu0HON8=";
      "aarch64-linux" = "sha256-y9FGfLqY7Z9MW9YyTU7q3BZIQjWP2qgY11qLGDEOO7Y=";
      "x86_64-linux" = "sha256-E0OCM5lR0k4jsdYHsFgWMiTObOA80gBNgmerw8qaHks=";
    }
    .${stdenv.hostPlatform.system};
  bunFetchFlags = [
    "--os=${stdenv.hostPlatform.node.platform}"
    "--cpu=${stdenv.hostPlatform.node.arch}"
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ "--libc=glibc" ];
  bunRunScripts = true;
  bunInstallFlags = [
    "--linker=isolated"
    "--force"
    "--no-progress"
  ];
  postBunInstall = ''
    bun --bun .nix/scripts/normalize-install.ts
  '';

  bunBuildScript = "build";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/handy-frontend
    cp -R dist $out/share/handy-frontend/

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s "$out/share/handy-frontend/dist/index.html"
    runHook postInstallCheck
  '';

  meta = {
    description = "Frontend build for the Handy desktop app";
    homepage = "https://handy.computer";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
