{ pkgs }:
let
  library = pkgs.runCommandCC "bun-elf-library" { } ''
    mkdir -p "$out/lib"
    echo 'int answer(void) { return 40; }' > answer.c
    $CC -shared -fPIC answer.c -Wl,-soname,libanswer.so -o "$out/lib/libanswer.so"
  '';
  fixture =
    pkgs.runCommandCC "bun-elf-fixture"
      {
        nativeBuildInputs = [
          pkgs.bun
          pkgs.patchelf
        ];
      }
      ''
        export HOME="$TMPDIR/home" BUN_INSTALL_CACHE_DIR="$TMPDIR/cache"
        mkdir -p "$HOME" "$out" package/bin package/lib
        echo 'int bundled(void) { return 2; }' > bundled.c
        $CC -shared -fPIC bundled.c -Wl,-soname,libbundled.so -o package/lib/libbundled.so
        cat > main.c <<'C'
        #include <stdio.h>
        extern int answer(void);
        extern int bundled(void);
        int main(void) { printf("%d\n", answer() + bundled()); return 0; }
        C
        $CC main.c -L${library}/lib -lanswer -Lpackage/lib -lbundled -o package/bin/tool
        patchelf --set-interpreter /missing/ld.so --set-rpath /missing package/bin/tool
        cat > package/package.json <<'JSON'
        {
          "name": "elf-tool", "version": "1.0.0", "bin": {"elf-tool": "bin/tool"},
          "scripts": {"postinstall": "./bin/tool >> lifecycle-runs"}
        }
        JSON
        tar -czf "$out/tool.tgz" package
        # Same-architecture ELF with an unavailable library, in a platform excluded
        # by Bun. Preparing the entire all-platform cache would fail on this file.
        patchelf --replace-needed libanswer.so libmust-not-resolve.so package/bin/tool
        cat > package/package.json <<'JSON'
        {"name": "foreign-tool", "version": "1.0.0", "os": ["!linux"]}
        JSON
        tar -czf "$out/foreign.tgz" package
        rm -rf package
        cat > "$out/package.json" <<'JSON'
        {
          "name": "elf-example", "version": "1.0.0",
          "dependencies": {"elf-tool": "file:./tool.tgz"},
          "optionalDependencies": {"foreign-tool": "file:./foreign.tgz"},
          "trustedDependencies": ["elf-tool"],
          "scripts": {"build": "elf-tool > build-ran"}
        }
        JSON
        cd "$out"
        bun install --lockfile-only --ignore-scripts
        # Bun does not serialize local tarball platform metadata. Include the
        # exclusion explicitly to exercise selection from an all-platform cache.
        substituteInPlace bun.lock --replace-fail \
          '"foreign-tool@./foreign.tgz", {}' \
          '"foreign-tool@./foreign.tgz", { "os": "!linux" }'
      '';
  # These local tarballs contain binaries built for the test's platform. Use
  # the actual fetcher without fixed-output hashing; no network is needed.
  deps = (pkgs.fetchBunDeps { src = fixture; }).overrideAttrs (_: {
    outputHash = null;
    outputHashAlgo = null;
    outputHashMode = null;
  });
  package = pkgs.buildBunPackage {
    pname = "bun-elf-example";
    version = "1";
    src = fixture;
    bunDeps = deps;
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ library ];
    bunRunScripts = true;
    doInstallCheck = true;
    installCheckPhase = ''
      packageOut="$out/lib/node_modules/elf-example"
      test "$(cat "$packageOut/build-ran")" = 42
      test "$(cat "$packageOut/node_modules/elf-tool/lifecycle-runs")" = 42
      test ! -e "$packageOut/node_modules/foreign-tool"
      test "$(patchelf --print-interpreter "$packageOut/node_modules/elf-tool/bin/tool")" != /missing/ld.so
      test "$(patchelf --print-interpreter "$(find "$bunDeps" -type f -path '*/bin/tool' | head -n1)")" = /missing/ld.so
      sourceTree=$PWD
      cd "$TMPDIR"
      rm -rf "$sourceTree" "$BUN_INSTALL_CACHE_DIR"
      test "$("$packageOut/node_modules/elf-tool/bin/tool")" = 42
    '';
  };
in
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  elf-lifecycle = package;
  elf-isolated = package.overrideAttrs (_: {
    bunInstallFlags = [ "--linker=isolated" ];
  });
  elf-build-only = package.overrideAttrs (_: {
    bunRunScripts = false;
    makeCacheWritable = true;
    installCheckPhase = ''
      packageOut="$out/lib/node_modules/elf-example"
      test "$(cat "$packageOut/build-ran")" = 42
      test ! -e "$packageOut/node_modules/elf-tool/lifecycle-runs"
      test "$("$packageOut/node_modules/elf-tool/bin/tool")" = 42
    '';
  });
  elf-disabled = pkgs.testers.testBuildFailure' {
    drv = package.overrideAttrs (_: {
      dontAutoPatchelf = true;
    });
    expectedBuilderLogEntries = [ "postinstall script from \"elf-tool\" exited" ];
  };
}
