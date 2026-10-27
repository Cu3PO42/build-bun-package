{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bun,
  nodejs ? null,
}:
let
  # The upstream tarball does not bundle its dependencies. Pin each archive
  # directly; this small, flat closure needs no package-manager bootstrap.
  runtime = if nodejs == null then bun else nodejs;
  packages = lib.importJSON ./node-gyp/packages.json;
  archive =
    name:
    let
      package = packages.${name};
    in
    fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${builtins.baseNameOf name}-${package.version}.tgz";
      inherit (package) hash;
    };
in
stdenvNoCC.mkDerivation {
  pname = "bun-node-gyp";
  inherit (packages.node-gyp) version;
  src = archive "node-gyp";
  nativeBuildInputs = [ makeWrapper ];
  patches = lib.optionals stdenvNoCC.hostPlatform.isDarwin [ ./node-gyp/darwin.patch ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    packageOut="$out/lib/node_modules/node-gyp"
    mkdir -p "$packageOut"
    cp -R . "$packageOut/"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: _package: ''
        mkdir -p "$packageOut/node_modules/"${lib.escapeShellArg name}
        tar -xzf ${archive name} -C "$packageOut/node_modules/"${lib.escapeShellArg name} --strip-components=1
      '') (builtins.removeAttrs packages [ "node-gyp" ])
    )}
    makeWrapper ${lib.getExe runtime} "$out/bin/node-gyp" \
      --add-flags "$packageOut/bin/node-gyp.js"
    runHook postInstall
  '';
  meta = {
    description = "Standalone node-gyp running with ${if nodejs == null then "Bun" else "Node.js"}";
    homepage = "https://github.com/nodejs/node-gyp";
    license = lib.licenses.mit;
    mainProgram = "node-gyp";
    inherit (bun.meta) platforms;
  };
}
