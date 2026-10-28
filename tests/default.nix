{ pkgs }:
let
  example = pkgs.callPackage ./example.nix { };
  workspaces = import ./workspaces.nix { inherit pkgs; };
  sources = import ./sources.nix { inherit pkgs; };
in
{
  inherit example;
  registry-auth = import ./registry-auth.nix { inherit pkgs; };
}
// workspaces
// sources
// import ./native.nix { inherit pkgs example; }
// import ./runtime.nix { inherit pkgs example; }
// import ./lifecycle.nix { inherit pkgs example; }
// import ./hooks.nix { inherit pkgs example; }
// import ./checks.nix { inherit pkgs example; }
// import ./evaluation.nix { inherit pkgs example; }
// import ./lint.nix { inherit pkgs; }
// import ./cache.nix {
  inherit pkgs example;
  inherit (workspaces) workspace catalogs;
  duplicateGit = sources.duplicate-git;
  foreignOptional = sources.foreign-optional;
}
