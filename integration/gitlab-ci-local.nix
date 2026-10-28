{
  lib,
  buildBunPackage,
  fetchFromGitHub,
  makeWrapper,
  nodejs-slim,
  versionCheckHook,
}:

# Based on nixpkgs pkgs/by-name/gi/gitlab-ci-local/package.nix.
# Exercises a Node-targeted bundle, an explicit Node compatibility runtime,
# package patching, and the default package install/wrapper hooks.
buildBunPackage (finalAttrs: {
  pname = "gitlab-ci-local";
  version = "4.76.1";

  src = fetchFromGitHub {
    owner = "firecow";
    repo = "gitlab-ci-local";
    rev = finalAttrs.version;
    hash = "sha256-GnNmpiNhrGrHSnk9hYdL23ONalRFIEaJtbCIiphebak=";
  };

  bunDepsHash = "sha256-CB9XSOGPryiHeYKwZA+lZ6e+UmgfgKGsjIUG0tgYg9Q=";
  runtime = nodejs-slim;
  bunBuildScript = "build:node";

  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"version": "0.0.0"' '"version": "${finalAttrs.version}"'

    substituteInPlace src/index.ts \
      --replace-fail 'yargs(process.argv.slice(2))' 'yargs(process.argv.slice(2)).scriptName("gitlab-ci-local")'
  '';

  preBuild = ''
    test "$(node -p 'process.versions.node')" = '${nodejs-slim.version}'
    node -e 'if (process.versions.bun) process.exit(1)'
  '';

  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    rm "$out/bin/gitlab-ci-local"
    makeWrapper ${lib.getExe nodejs-slim} "$out/bin/gitlab-ci-local" \
      --add-flags "$out/lib/node_modules/gitlab-ci-local/dist/index.js"
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";

  meta = {
    description = "Run GitLab pipelines locally";
    homepage = "https://github.com/firecow/gitlab-ci-local";
    license = lib.licenses.mit;
    mainProgram = "gitlab-ci-local";
  };
})
