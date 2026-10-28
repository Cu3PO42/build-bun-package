{
  lib,
  buildBunPackage,
  curl,
  fetchFromGitHub,
  makeWrapper,
}:

# Based on nixpkgs' pkgs/by-name/ku/kulala-core/package.nix.
# Exercises a root workspace build that emits both JavaScript and a WASM asset.
buildBunPackage (finalAttrs: {
  pname = "kulala-core";
  version = "0.37.0";

  src = fetchFromGitHub {
    owner = "mistweaverco";
    repo = "kulala-core";
    tag = "v${finalAttrs.version}";
    hash = "sha256-rqfxp+i2o2DA8vle8yr+C6TzHcF2Q7kwYkW2VLMaKw0=";
  };

  bunDepsHash = "sha256-45uy+nuF80xujf+PEdy0238Uc3zITP+vE9Io9pxZzeg=";
  # The upstream package builds only the core CLI entry point. Its root
  # `build` script also generates vendored curl/jq binaries for other targets.
  buildPhase = ''
    runHook preBuild

    echo '{ "version": "${finalAttrs.version}" }' > packages/core/version.json
    (
      cd packages/core
      bun build src/cli.ts \
        --target=bun \
        --outdir=dist \
        --asset-naming='[name].[ext]'
    )

    runHook postBuild
  '';

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm644 packages/core/dist/cli.js $out/lib/kulala-core/kulala-core.js
    install -Dm644 packages/core/dist/liblua5.1.wasm $out/lib/kulala-core/liblua5.1.wasm
    makeWrapper ${lib.getExe finalAttrs.bun} $out/bin/kulala-core \
      --add-flags $out/lib/kulala-core/kulala-core.js \
      --set KULALA_CURL_PATH ${lib.getExe curl}

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -s "$out/lib/kulala-core/liblua5.1.wasm"
    response=$(
      printf '%s' '{"action":"from_curl","curl":"curl https://example.com"}' |
        "$out/bin/kulala-core"
    )
    [[ "$response" == *'"ok": true'* ]]
    [[ "$response" == *'GET https://example.com'* ]]

    runHook postInstallCheck
  '';

  meta = {
    description = "HTTP client library powering the Kulala toolchain";
    homepage = "https://github.com/mistweaverco/kulala-core";
    license = lib.licenses.mit;
    mainProgram = "kulala-core";
    platforms = finalAttrs.bun.meta.platforms;
  };
})
