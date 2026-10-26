{
  buildBunPackage,
  fixtureSrc ? ./fixtures/basic,
  projectRoot ? ".",
  dependencyCache ? null,
  dontBunPrune ? false,
}:

buildBunPackage {
  pname = "bun-example";
  version = "1.0.0";
  src = fixtureSrc;
  bunRoot = projectRoot;
  bunDeps = dependencyCache;
  inherit dontBunPrune;
  bunDepsHash = "sha256-LcB/R9IKKY4Wi7Q2mop2HRE0oH5/GZtIPIXAufkq+rM=";
  bunInstallFlags = [ "--ignore-scripts" ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    test "$(bun dist/cli.js 3)" = odd
    test "$(bun dist/cli.js 4)" = even
    # The dev dependency and its platform-specific optional binary came from
    # the pack and work without an install script or network access.
    test "$(bun node_modules/esbuild/bin/esbuild --version)" = 0.25.0
    runHook postCheck
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/bun-example" 3)" = odd
    test "$("$out/bin/bun-example" 4)" = even
    test ! -e "$out/lib/node_modules/bun-example/cli.js"
    test -d "$out/lib/node_modules/bun-example/node_modules/is-odd"
    test -d "$out/lib/node_modules/bun-example/node_modules/is-number"
    ${
      if dontBunPrune then
        ''
          test -d "$out/lib/node_modules/bun-example/node_modules/esbuild"
          test "$(bun "$out/lib/node_modules/bun-example/node_modules/esbuild/bin/esbuild" --version)" = 0.25.0
        ''
      else
        ''
          test ! -e "$out/lib/node_modules/bun-example/node_modules/esbuild"
          test ! -e "$out/lib/node_modules/bun-example/node_modules/.bin/esbuild"
          test -z "$(find "$out/lib/node_modules/bun-example/node_modules/@esbuild" -mindepth 1 -print 2>/dev/null)"
        ''
    }
    runHook postInstallCheck
  '';
  meta.mainProgram = "bun-example";
}
