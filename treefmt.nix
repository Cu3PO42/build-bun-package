{
  lib,
  pkgs,
  bun,
  ...
}:
{
  runtimeInputs = [ pkgs.gitMinimal ];

  settings = {
    tree-root-file = "flake.nix";
    on-unmatched = "debug";
    excludes = [ "output/*" ];

    formatter.nixfmt = {
      command = lib.getExe pkgs.nixfmt;
      includes = [ "*.nix" ];
    };

    formatter.nixf-diagnose = {
      command = lib.getExe pkgs.nixf-diagnose;
      includes = [ "*.nix" ];
      priority = -1;
      # Match nixpkgs/ci/treefmt.nix; nixfmt runs after automatic fixes.
      options = [
        "--auto-fix"
        "--ignore=sema-unused-def-lambda-noarg-formal"
        "--ignore=sema-unused-def-lambda-witharg-arg"
        "--ignore=sema-unused-def-lambda-witharg-formal"
        "--ignore=sema-unused-def-let"
        "--ignore=sema-primop-removed-prefix"
        "--ignore=sema-primop-overridden"
        "--ignore=sema-constant-overridden"
        "--ignore=sema-primop-unknown"
      ];
    };

    formatter.editorconfig-checker = {
      command = lib.getExe pkgs.editorconfig-checker;
      includes = [ "*" ];
      excludes = [ "tests/fixtures/*" ];
      options = [
        "-disable-indent-size"
        "-disable-charset"
      ];
      priority = 1;
    };

    formatter.yamlfmt = {
      command = lib.getExe pkgs.yamlfmt;
      includes = [
        "*.yml"
        "*.yaml"
      ];
      options = [
        "-formatter"
        "retain_line_breaks=true"
      ];
    };

    formatter.zizmor = {
      command = lib.getExe pkgs.zizmor;
      includes = [
        ".github/workflows/*.yml"
        ".github/workflows/*.yaml"
      ];
      options = [ "--offline" ];
    };

    formatter.markdown-code-runner = {
      command = lib.getExe pkgs.markdown-code-runner;
      includes = [ "*.md" ];
      options = [
        "--config=${
          pkgs.writers.writeTOML "markdown-code-runner-config" {
            presets.nixfmt = {
              language = "nix";
              command = [
                (lib.getExe pkgs.nixfmt)
                "-"
              ];
            };
          }
        }"
      ];
    };

    formatter.shfmt = {
      command = lib.getExe pkgs.shfmt;
      includes = [ "*.sh" ];
      options = [
        "-w"
        "-i"
        "4"
        "-ci"
      ];
    };

    formatter.bun = {
      command = lib.getExe bun;
      includes = [
        "*.js"
        "*.ts"
      ];
      # Fixture contents can contribute to fixed-output hashes.
      excludes = [ "tests/fixtures/*" ];
      options = [
        "fmt"
        "--no-script"
        "--single-quote"
        "--no-semi"
      ];
    };
  };
}
