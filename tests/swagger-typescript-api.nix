{
  lib,
  buildBunPackage,
  fetchFromGitHub,
  versionCheckHook,
}:

# Based on nixpkgs pkgs/by-name/sw/swagger-typescript-api/package.nix.
# The default hooks build, prune, pack the templates, and wrap the CLI.
buildBunPackage (finalAttrs: {
  pname = "swagger-typescript-api";
  version = "13.13.0";

  src = fetchFromGitHub {
    owner = "acacode";
    repo = "swagger-typescript-api";
    rev = "v${finalAttrs.version}";
    hash = "sha256-lV24rJwgmcTODyvb/qkpKWII4EhKd+xGrs1uwjuSVq4=";
  };

  bunDepsHash = "sha256-eqt/OddO/yJvexnR6wesc1EZtvbOxXKp+xmpZgF79kQ=";
  makeWrapperArgs = [
    "--set"
    "NODE_ENV"
    "production"
  ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/swagger-typescript-api" --help > help.txt
    grep -q generate help.txt
    "$out/bin/swagger-typescript-api" generate --help > generate-help.txt
    grep -q -- --path generate-help.txt

    runHook postInstallCheck
  '';

  meta = {
    description = "Generate TypeScript API clients from an OpenAPI specification";
    homepage = "https://github.com/acacode/swagger-typescript-api";
    license = lib.licenses.mit;
    mainProgram = "swagger-typescript-api";
  };
})
