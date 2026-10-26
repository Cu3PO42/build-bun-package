{
  lib,
  buildBunPackage,
  bun,
  stdenv,
}:

buildBunPackage {
  pname = "bun-node-gyp";
  version = (lib.importJSON ./node-gyp/package.json).dependencies.node-gyp;
  inherit bun;
  src = ./node-gyp;
  bunDepsHash = "sha256-CB6mi3g6vG2m9Oxj41QMWxY9WMfywpKu9t9yZrJ/+S0=";
  bunInstallFlags = [ "--ignore-scripts" ];
  dontBunBuild = true;

  # Keep the same deterministic Xcode/CLT fallback as Nixpkgs' bundled gyp,
  # applied to the standalone upstream package instead of a Node.js install.
  postBunInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    patch -p1 < ${./node-gyp/darwin.patch}
  '';

  meta = {
    description = "Standalone node-gyp running with Bun";
    homepage = "https://github.com/nodejs/node-gyp";
    license = lib.licenses.mit;
    mainProgram = "node-gyp";
  };
}
