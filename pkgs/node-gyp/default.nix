{
  lib,
  buildBunPackage,
  bun,
  stdenv,
  makeWrapper,
  nodejs ? null,
}:
let
  runtime = if nodejs == null then bun else nodejs;
in
buildBunPackage {
  pname = "bun-node-gyp";
  version = (lib.importJSON ./source/package.json).dependencies.node-gyp;
  inherit bun;
  src = ./source;
  bunDepsHash = "sha256-CB6mi3g6vG2m9Oxj41QMWxY9WMfywpKu9t9yZrJ/+S0=";
  nativeBuildInputs = [ makeWrapper ];
  dontBunBuild = true;

  # Match Nixpkgs' deterministic Xcode/CLT fallback.
  postBunInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    patch -p1 < ${./darwin.patch}
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib"
    cp -R node_modules "$out/lib/"
    makeWrapper ${lib.getExe runtime} "$out/bin/node-gyp" \
      --add-flags "$out/lib/node_modules/node-gyp/bin/node-gyp.js"
    runHook postInstall
  '';

  meta = {
    description = "Standalone node-gyp running with ${if nodejs == null then "Bun" else "Node.js"}";
    homepage = "https://github.com/nodejs/node-gyp";
    license = lib.licenses.mit;
    mainProgram = "node-gyp";
  };
}
