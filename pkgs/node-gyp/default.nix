{
  lib,
  buildBunPackage,
  bun,
  stdenv,
  nodejs ? null,
}:
let
  runtime = if nodejs == null then bun else nodejs;
in
buildBunPackage {
  pname = "bun-node-gyp";
  version = (lib.importJSON ./source/package.json).dependencies.node-gyp;
  inherit bun;
  bunRuntime = runtime;
  src = ./source;
  bunDepsHash = "sha256-CB6mi3g6vG2m9Oxj41QMWxY9WMfywpKu9t9yZrJ/+S0=";
  dontBunBuild = true;

  # Match Nixpkgs' deterministic Xcode/CLT fallback.
  postBunInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    patch -p1 < ${./darwin.patch}
  '';

  meta = {
    description = "Standalone node-gyp running with ${if nodejs == null then "Bun" else "Node.js"}";
    homepage = "https://github.com/nodejs/node-gyp";
    license = lib.licenses.mit;
    mainProgram = "node-gyp";
  };
}
