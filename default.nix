# Entry point for nixpkgs maintenance tools such as update-source-version.
{
  system ? builtins.currentSystem,
}:
(builtins.getFlake (toString ./.)).legacyPackages.${system}
