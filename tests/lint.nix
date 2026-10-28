{ pkgs }:
let
  src = pkgs.lib.cleanSource ../.;
in
{
  formatting = pkgs.runCommand "nix-bun-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    cd ${src}
    find . -path ./integration -prune -o -type f -name '*.nix' -exec nixfmt --check {} +
    touch "$out"
  '';

  shellcheck = pkgs.runCommand "nix-bun-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    cd ${src}
    find . -type f -name '*.sh' -exec shellcheck {} +
    touch "$out"
  '';
}
