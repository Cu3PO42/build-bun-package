{
  lib,
  buildBunPackage,
  bun,
  stdenv,
  runtime ? bun,
}:
buildBunPackage {
  pname = "bun-node-gyp";
  version = (lib.importJSON ./source/package.json).dependencies.node-gyp;
  inherit bun;
  inherit runtime;
  src = ./source;
  bunDepsHash = "sha256-4QskgdxeYqkRXvJ9GD3S0LqaSZDZXFk1l+L6Q/xb0u0=";
  dontBunBuild = true;

  # Match Nixpkgs' deterministic Xcode/CLT fallback.
  postBunInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    patch -p1 < ${./darwin.patch}
  '';

  meta = {
    description = "Standalone node-gyp running with ${
      if lib.getName runtime == "bun" then "Bun" else "Node.js"
    }";
    homepage = "https://github.com/nodejs/node-gyp";
    license = lib.licenses.mit;
    mainProgram = "node-gyp";
  };
}
