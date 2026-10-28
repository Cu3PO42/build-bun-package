{ lib, pkgs, ... }:
{
  runtimeInputs = [ pkgs.gitMinimal ];

  settings = {
    tree-root-file = "flake.nix";
    on-unmatched = "debug";

    formatter.nixfmt = {
      command = lib.getExe pkgs.nixfmt;
      includes = [ "*.nix" ];
      excludes = [ "integration/*" ];
    };
  };
}
