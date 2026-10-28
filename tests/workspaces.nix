{ pkgs }:
let
  catalogs = pkgs.buildBunPackage {
    pname = "bun-catalog-example";
    version = "1";
    src = ./fixtures/catalogs;
    bunDepsHash = "sha256-s318Wt8d+fBK6qijgUNG5sTN5LC0d9Cu6D5/ekVQFXg=";
    bunWorkspace = "apps/cli";
    makeCacheWritable = true;
    doInstallCheck = true;
    installCheckPhase = ''
      cd "$TMPDIR"
      rm -rf "$NIX_BUILD_TOP/catalogs"
      test "$("$out/bin/workspace-cli")" = 'catalogs work'
    '';
  };

  workspace = pkgs.buildBunPackage {
    pname = "bun-workspace-example";
    version = "1.0.0";
    src = ./fixtures/workspace;
    bunDepsHash = "sha256-a/YgadTQr130SaPzXwbNMC2Eqwak0VRUboCi/OFcARY=";
    makeCacheWritable = true;
    bunFlags = [ "--silent" ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share"
      cp dist/index.js "$out/share/workspace.js"
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$(bun "$out/share/workspace.js")" = 'workspace works'
    '';
  };
in
{
  inherit workspace catalogs;

  workspace-installed = pkgs.buildBunPackage {
    pname = "bun-workspace-installed";
    version = "1";
    src = ./fixtures/workspace;
    bunDeps = workspace.bunDeps;
    bunWorkspace = "apps/cli";
    makeCacheWritable = true;
    # Root publish selection deliberately excludes workspace sources. Linked
    # packages must be installed independently of this list.
    nativeBuildInputs = [ pkgs.jq ];
    postPatch = ''
      jq '.files = ["package.json"]' package.json > package.json.new
      mv package.json.new package.json
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/workspace-cli")" = 'workspace works'
      test -f "$out/lib/node_modules/workspace-example/packages/message/index.js"
      test ! -e "$out/lib/node_modules/workspace-example/apps/cli/index.js"
      # Resolve every dependency link after removing the original source tree.
      cd "$TMPDIR"
      rm -rf "$NIX_BUILD_TOP/workspace"
      test "$("$out/bin/workspace-cli")" = 'workspace works'
      while IFS= read -r -d "" link; do test -e "$link"; done < <(find "$out" -type l -print0)
    '';
  };

  workspace-isolated = pkgs.buildBunPackage {
    pname = "bun-workspace-isolated";
    version = "1";
    src = ./fixtures/workspace;
    bunDeps = workspace.bunDeps;
    bunWorkspace = "apps/cli";
    makeCacheWritable = true;
    bunInstallFlags = [ "--linker=isolated" ];
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/workspace-cli")" = 'workspace works'
      while IFS= read -r -d "" link; do test -e "$link"; done < <(find "$out" -type l -print0)
    '';
  };

  workspace-unbuilt-bin = pkgs.buildBunPackage {
    pname = "bun-workspace-unbuilt-bin";
    version = "1";
    src = ./fixtures/workspace-bins;
    bunDepsHash = "sha256-NyVRlJQTng259hC14hNoXFgIONeAayoC5sKYz7OKPzQ=";
    bunWorkspace = "apps/selected";
    makeCacheWritable = true;
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      # Only the selected workspace was built; its dependency also declares a
      # CLI whose absent build output must not prevent library consumption.
      test ! -e apps/unbuilt/dist
      test ! -e "$out/bin/unbuilt-workspace"
      cd "$TMPDIR"
      rm -rf "$NIX_BUILD_TOP/workspace-bins"
      test "$("$out/bin/selected-workspace")" = 'workspace bins work'
      while IFS= read -r -d "" link; do test -e "$link"; done < <(find "$out" -type l -print0)
      runHook postInstallCheck
    '';
  };
}
