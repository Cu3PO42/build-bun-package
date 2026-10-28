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

    formatter.nixfmt = {
      command = lib.getExe pkgs.nixfmt;
      includes = [ "*.nix" ];
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
        "--use-tabs"
        "--single-quote"
        "--no-semi"
      ];
    };
  };
}
