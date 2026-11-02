# Contributing to bunflake

[README](./README.md) · [Packaging guide](./docs/packaging.md) · [Reference](./docs/reference.md) · [Design](./docs/design.md)

The builder and hooks are designed with eventual inclusion in Nixpkgs in mind.
To keep that path open, follow
[Nixpkgs' contributing guidelines](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md)
and [package conventions](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md).
Keep dependencies explicit through `callPackage`, use `lib.extendMkDerivation`
for the builder, and keep the implementation independent of the flake wrapper.

## Format and run checks

Start with formatting and evaluation, then build the checks for your platform:

```sh
nix fmt
nix flake check --all-systems --no-build
nix flake check --keep-going --print-build-logs
```

The evaluation step covers all supported systems; the last command builds checks
only for the current system. Before submitting changes, run the applicable
builds on each supported platform, locally or through native remote builders.

Run `nix fmt` to format Nix with nixfmt, shell with shfmt, and
JavaScript/TypeScript with Bun. JavaScript/TypeScript test fixtures are
excluded to preserve their contents and hashes.
The shared configuration in [`treefmt.nix`](./treefmt.nix) applies to both
formatting and formatting checks. Run `nix fmt -- --ci` to format and fail if any
files change.

Dependency checks rely on reproducible fixture contents and offline builds.
Use sandboxing when checking offline behavior, and investigate unexpected
fixed-output hash mismatches before changing their expected values. Fixture
bytes contribute to hashes, so formatters must leave them unchanged.

Checks cover both repository conventions and package behavior. The former
include formatting, Nix diagnostics and parsing, shell and workflow linting,
and Nix examples in Markdown. The latter exercise the builder, dependency
providers, and installed applications; the [coverage notes](#verification-boundaries)
below explain what those tests establish.
Nixpkgs' broader formatter configuration additionally checks JavaScript outside
`pkgs/` with Biome and keep-sorted markers. This repository uses Bun's formatter
for JavaScript and TypeScript. Run Nixpkgs' formatter after transplanting files.

For a documentation or lint-only change, you can select individual checks.
For example, substitute your system in:

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

The tests distinguish successful evaluation from a working installed package.
[`tests/`](./tests) exercises cache validation, offline installation, lifecycle
scripts, both workspace linkers, pruning, and runtime behavior after the source
has been removed. Native checks cover Bun and Node.js, shebang-changing
patches, and early Linux ELF preparation.

Cache checks use `testers.invalidateFetcherByDrvHash` where a fresh fetch is
required. This prevents changed fetcher inputs from passing solely because Nix
reused an existing fixed-output result.

### Lockfiles and migration

Source checks cover text/JSONC and binary Bun lockfiles, catalogs, local
`file:`/`link:` dependencies, Git aliases, public GitHub and HTTP sources, and a
non-default registry. Workspace checks include a sibling whose CLI has not yet
been built.

The `migration-real-*` checks use complete dependency snapshots from real npm,
npm shrinkwrap, pnpm, Yarn Classic, and Yarn Berry projects, including Nixpkgs
packages. They verify offline installation, nested version resolution, optional
dependencies, executable links, and module behavior. Their combined dependency
caches are limited to 32 MiB. See the
[fixture provenance and update notes](./tests/fixtures/migration-real/README.md)
before changing these inputs.

### Importer sources

The `import-lock-*` checks exercise registry and scoped URLs, aliases,
prereleases, HTTP and GitHub archives, Git checkouts and fetcher selection,
local archives, root references, workspaces, catalogs, dependency patches, and
lifecycle-script settings. Checkout cases include executable bits, symlinks,
and native Git cache tags. All importer checks run with sandboxing enabled and
import from derivation disabled.

Local archive cases include compressed and uncompressed formats and legacy
entries without integrity hashes. Linux cases also exercise ELF preparation
and foreign optional binaries with both linkers. Generated-source fixtures
supply an independently available `lockFile`, demonstrating that evaluation
does not need to build the source first.

The JSONC parser also has a differential test against `Bun.JSONC.parse`. Run
`bun tests/test-jsonc.ts` to compare 1,009 valid inputs and 17 malformed inputs
with import from derivation disabled.

### Authentication boundaries

The authenticated mock registry tests credential rejection, token leakage, and
offline installation after credentials have been removed and the server stopped.
It does not configure daemon credentials. Private hosted Git authentication
and Git transports beyond those represented by local tests remain unverified.

## Implementation

See [the design notes](./docs/design.md) for cache formats, installation stages,
source normalization, and implementation tradeoffs.

## Preparing an upstream contribution

Passing this repository's checks establishes that the standalone helpers work
within the tested boundaries. An upstream contribution also needs integration
with Nixpkgs' package layout, tests, and review process. The steps below require
an actual Nixpkgs checkout:

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
