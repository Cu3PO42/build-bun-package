# Contributing to bunflake

[README](./README.md) · [Packaging guide](./docs/packaging.md) · [Reference](./docs/reference.md) · [Design](./docs/design.md)

The builder and hooks are intended for eventual inclusion in Nixpkgs. Follow
[Nixpkgs' contributing guidelines](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md)
and [package conventions](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md).
Keep dependencies explicit through `callPackage`, use `lib.extendMkDerivation`
for the builder, and keep the implementation independent of the flake wrapper.

## Format and run checks

Run `nix fmt` to format Nix with nixfmt, shell with shfmt, and
JavaScript/TypeScript with Bun. JavaScript/TypeScript test fixtures are
excluded to preserve their contents and hashes.
The shared configuration in [`treefmt.nix`](./treefmt.nix) applies to both
formatting and formatting checks. Run `nix fmt -- --ci` to format and fail if any
files change.

Run these commands before submitting changes:

```sh
nix fmt
nix flake check --all-systems --no-build
nix flake check --keep-going --print-build-logs
```

The last command builds checks for the current system. Use sandboxed builds
when checking offline behavior; do not change fixed-output
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

Run `nix flake check` on each supported system. `nix flake check --all-systems`
evaluates other systems but does not build their checks on the current host.
To run only the formatting, ShellCheck, and actionlint checks, substitute your
system in:

```sh
nix build --no-link .#checks.x86_64-linux.formatting \
  .#checks.x86_64-linux.shellcheck .#checks.x86_64-linux.actionlint
```

GitHub Actions runs the checks on `x86_64-linux` for pull requests and pushes to
`master`. Use **Actions → CI → Run workflow** to enable `all-platforms` for native
`aarch64-linux` and `aarch64-darwin` runners, or `integration` for the real-world
package builds. Integration builds run separately for each package and platform
after the checks pass; Linux-only examples are skipped on Darwin. Nix build
results are cached through GitHub Actions without additional cache credentials.

To build all checks through configured remote builders:

```sh
nix build --no-link --keep-going --impure --expr '
  let flake = builtins.getFlake (toString ./.);
  in builtins.concatLists (map
    (system: builtins.attrValues flake.checks.${system})
    (builtins.attrNames flake.checks))
'
```

Real-world examples are documented in the [README](./README.md#examples).

## Update the bundled tools

To update Bun and matching headers, run from the repository root:

```sh
$(nix-build --no-out-link -A bun.updateScript)
```

This runs Nixpkgs' Bun updater to select the latest stable release, then updates
the matching headers even when Bun is already current. To update only the
headers for the currently selected Bun, run:

```sh
$(nix-build --no-out-link -A bunNodeHeaders.updateScript)
```

To update standalone node-gyp, change its dependency in
[`pkgs/node-gyp/source/package.json`](./pkgs/node-gyp/source/package.json),
regenerate the adjacent lockfile with Bun, and recalculate its `bunDepsHash`.

## Verification boundaries

[`tests/`](./tests) covers caches, lifecycle scripts, shebang-changing dependency
patches, early ELF fixups, native builds with Bun and Node.js, check hooks and
test failures, flag handling, workspaces with hoisted and isolated linkers,
pruning, and installed runtime behavior. Fresh-fetch checks use
`testers.invalidateFetcherByDrvHash` so changed fetcher inputs cannot pass by
reusing a cached fixed-output result.

`migration-real-*` checks use complete npm, npm shrinkwrap, pnpm, Yarn Classic,
and Yarn Berry dependency snapshots from real projects, including nixpkgs
packages. They verify offline installation, nested version resolution, optional
dependencies, executable links, and module behavior. Their combined dependency
caches are limited to 32 MiB.
See the [fixture provenance and update notes](./tests/fixtures/migration-real/README.md).

Source coverage includes text/JSONC and binary lockfiles, catalogs, duplicate
Git aliases, local `file:` and `link:` dependencies, foreign optional dependencies,
a public GitHub dependency, an HTTP tarball, and a non-default registry. Workspace
checks also cover consuming a sibling whose CLI has not been built. The
authenticated mock registry checks credential rejection, token leakage, and offline
installation after removing credentials and stopping the server. It does not
configure daemon credentials.
Other Git protocols and private Git authentication remain untested.

`import-lock-*` checks repeat builds with imported caches, including custom and
scoped registries, aliases, prereleases, direct tarballs, and both linkers.
Run `bun tests/test-jsonc.ts` for a differential parser test against
`Bun.JSONC.parse`: 1,009 valid inputs and 17 malformed inputs, with IFD disabled.

Local-archive checks include compressed and uncompressed archives, legacy rows
without integrity, self-references, and installed links after deleting the source.
Linux importer checks also cover ELF preparation and lifecycle scripts with both
linkers. They pass a separately available `lockFile` for a generated source,
avoiding IFD even when that source contains platform-specific compiled tarballs.

### Importer source coverage

The `import-lock-*` checks cover registry/scoped URLs, aliases, prereleases,
direct and legacy HTTP archives, pinned and legacy GitHub archives, real Git
checkouts, Git fetcher selection, executable bits, checkout symlinks, native Git
tags, local archive formats, root references, workspaces, catalogs, patches,
trusted and disabled lifecycle scripts, and source deletion after installation.
Linux checks also exercise ELF preparation and a foreign optional binary with
both hoisted and isolated linkers. All checks run with sandboxing enabled and
import from derivation disabled.

## Implementation

See [the design notes](./docs/design.md) for cache formats, installation stages,
source normalization, and implementation tradeoffs.

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
