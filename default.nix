# Entry point for nixpkgs maintenance tools such as update-source-version.
{
  system ? builtins.currentSystem,
}:
let
  flake = builtins.getFlake (toString ./.);
in
flake.legacyPackages.${system}
// {
  # Let maintenance tools map flake source positions back to this checkout.
  inherit (flake) outPath;
}
