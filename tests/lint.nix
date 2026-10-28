{ pkgs }:
let
  src = pkgs.lib.cleanSource ../.;
in
{
  formatting = (pkgs.treefmt.withConfig ../treefmt.nix).check src;

  shellcheck = pkgs.runCommand "nix-bun-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    cd ${src}
    find . -type f -name '*.sh' -exec shellcheck {} +
    touch "$out"
  '';

  actionlint =
    pkgs.runCommand "nix-bun-actionlint"
      {
        nativeBuildInputs = [
          pkgs.actionlint
          pkgs.shellcheck
        ];
      }
      ''
        cd ${src}
        actionlint .github/workflows/*.yml
        touch "$out"
      '';
}
