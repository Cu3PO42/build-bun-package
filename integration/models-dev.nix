{
  lib,
  stdenv,
  buildBunPackage,
  fetchFromGitHub,
  jq,
}:

# Based on nixpkgs pkgs/by-name/mo/models-dev/package.nix.
# Exercises a Bun workspace install followed by a package-scoped build.
buildBunPackage (finalAttrs: {
  pname = "models-dev";
  version = "0.0.5-unstable-2026-10-17";
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "models.dev";
    rev = "d1853abfc1125d500cf04abaefc7b2839c8f43e1";
    hash = "sha256-C6qkWUUwv5NQ5iQGqC6a2N8axtOLzSDkbIhnHBs8ciA=";
  };

  bunDepsHash =
    {
      "aarch64-darwin" = "sha256-6c+nIfhPdJZzu5LcFQe/bVEt7M5RvBx7zFWBc3A1Pcg=";
      "aarch64-linux" = "sha256-5aJho2L1uL3rZaBrqJMdR/xWIfaQ0VA/rNnDTvEaxmU=";
      "x86_64-linux" = "sha256-e9vxFfH1HAs5ZBzalenKyF1R9TKYUj0GyKW9VA2GtdM=";
    }
    .${stdenv.hostPlatform.system};
  bunFetchFlags = [
    "--os=${stdenv.hostPlatform.node.platform}"
    "--cpu=${stdenv.hostPlatform.node.arch}"
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ "--libc=glibc" ];

  nativeBuildInputs = [ jq ];

  buildPhase = ''
    runHook preBuild

    cd packages/web
    bun run ./script/build.ts
    bun ${./models-dev-generate-schema.ts} ./dist/_api.json ./dist/model-schema.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/dist
    cp -R dist/. $out/dist/

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    jq -e '."$defs".Model.enum | length > 0' "$out/dist/model-schema.json" >/dev/null
    test -s "$out/dist/_api.json"
    runHook postInstallCheck
  '';

  passthru.jsonschema = "${finalAttrs.finalPackage}/dist/model-schema.json";

  meta = {
    description = "Comprehensive open-source database of AI model specifications";
    homepage = "https://models.dev";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
