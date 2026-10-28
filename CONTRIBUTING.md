# Contributing

The builder and hooks are intended for eventual inclusion in Nixpkgs. Follow
[Nixpkgs' contributing guidelines](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md)
and [package conventions](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md).
Keep dependencies explicit through `callPackage`, use `lib.extendMkDerivation`
for the builder, and keep the implementation independent of the flake wrapper.

Run these commands before submitting changes:

```sh
nix fmt
nix flake check --all-systems --no-build
nix flake check --keep-going --print-build-logs
```

The last command builds checks for the current system. CI runs Linux checks on
pull requests. Dispatch CI with `all-platforms` and `integration` enabled to
exercise all three supported systems and the real application packages. Use
sandboxed builds when checking offline behavior; do not change fixed-output
hashes merely to silence unexpected mismatches. Fixture bytes contribute to
hashes, so formatters must leave them unchanged.

The checks include nixfmt, nixf-diagnose with Nixpkgs' enabled rules,
EditorConfig, ShellCheck, actionlint, yamlfmt, zizmor, Nix examples in Markdown,
and parsing every Nix file with stable
Nix, latest Nix, and Lix. They also cover builder overrides, imported lockfiles,
offline installation, lifecycle scripts, workspaces, and native dependencies.
Nixpkgs' broader formatter configuration additionally checks JavaScript outside
`pkgs/` with Biome and keep-sorted markers. This repository uses Bun's formatter
for JavaScript and TypeScript. Run Nixpkgs' formatter after transplanting files.

## Preparing an upstream contribution

These steps require an actual Nixpkgs checkout and cannot be certified by this
repository's CI:

- Register the helpers through Nixpkgs' package set. Place build infrastructure
  under `pkgs/build-support`; reconcile the Bun and node-gyp changes with the
  existing packages instead of submitting parallel copies of them.
- Move the public API documentation into the JavaScript section of the Nixpkgs
  manual. Wire the tests into `pkgs/test` and/or `passthru.tests` so Nixpkgs CI can
  discover them without this flake. Include a real consumer of the builder.
- Add a willing maintainer for new maintained packages. Check metadata with
  `config.checkMeta = true` and evaluation with `config.allowAliases = false`.
- Run `nix fmt` in Nixpkgs, its parser checks, and
  `./ci/nixpkgs-vet.sh master` against the intended base branch. The vet job
  checks Nixpkgs-specific package layout and changes relative to the base; it
  is not a generic linter for this standalone tree.
- Run applicable package tests and `nixpkgs-review wip` to check affected
  consumers. Report exactly which platforms were built and tested.
- Split changes into logical commits using Nixpkgs' `attribute: change` subject
  convention, with no trailing period. Add a maintainer entry in a separate
  preceding commit if needed. Include release notes for significant changes.
- Complete human review before submission and disclose nontrivial automation
  as required by the current Nixpkgs policy. This repository's README describes
  its AI involvement and unfinished human review; that notice does not replace
  the disclosure required for upstream commits and PR text.

Consult the current [Nixpkgs lint workflow](https://github.com/NixOS/nixpkgs/blob/master/.github/workflows/lint.yml)
and [formatter configuration](https://github.com/NixOS/nixpkgs/blob/master/ci/treefmt.nix)
when updating our checks. Passing local checks is preparation for upstream
review, not a guarantee of acceptance.
