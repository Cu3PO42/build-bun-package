{ pkgs }:
let
  src = pkgs.lib.cleanSource ../.;
  nixSrc = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.fileFilter (file: file.hasExt "nix") ../.;
  };
  parse =
    nix:
    pkgs.runCommand "nix-bun-parse-${nix.name}" { nativeBuildInputs = [ nix ]; } ''
      export NIX_STORE_DIR="$TMPDIR/store"
      export NIX_STATE_DIR="$TMPDIR/state"
      nix-store --init
      cd ${nixSrc}
      find . -type f -name '*.nix' -print0 | while IFS= read -r -d "" file; do
        if ! nix-instantiate --parse "$file" > /dev/null 2> "$TMPDIR/diagnostics"; then
          cat "$TMPDIR/diagnostics" >&2
          exit 1
        fi
        # Like nixpkgs CI, reject deprecation warnings as well as parse errors.
        if test -s "$TMPDIR/diagnostics"; then
          cat "$TMPDIR/diagnostics" >&2
          exit 1
        fi
      done
      touch "$out"
    '';
in
{
  parse-nix-stable = parse pkgs.nixVersions.stable;
  parse-nix-latest = parse pkgs.nixVersions.latest;
  parse-lix = parse pkgs.lix;

  formatting =
    (pkgs.treefmt.withConfig {
      imports = [ ../treefmt.nix ];
      _module.args.bun = pkgs.bun;
    }).check
      src;

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
