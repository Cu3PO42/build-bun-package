# Reference

[README](../README.md) · [Packaging guide](./packaging.md) · [Reference](./reference.md) · [Design](./design.md) · [Contributing](../CONTRIBUTING.md)

This reference defines the builder attributes and the hooks they select. For a
walkthrough and examples, start with the [packaging guide](./packaging.md).

- [Reference](#reference)
  - [buildBunPackage](#buildbunpackage)
    - [Runtime and native toolchain](#runtime-and-native-toolchain)
    - [Dependency fetching](#dependency-fetching)
    - [Project selection](#project-selection)
    - [Build, check, and install](#build-check-and-install)
    - [Hooks](#hooks)
  - [fetchBunDeps](#fetchbundeps)
  - [importBunLock](#importbunlock)
  - [Setup hooks](#setup-hooks)
  - [Custom phases](#custom-phases)
  - [Dependency preparation hooks](#dependency-preparation-hooks)
  - [Shebang fixup](#shebang-fixup)
  - [Native toolchain overrides](#native-toolchain-overrides)
  - [Package-set integration](#package-set-integration)

## buildBunPackage

`buildBunPackage` is the main entry point into this package.
Access it via `bunflake.legacyPackages.${system}.buildBunPackage` or use the overlay.
It accepts standard `stdenv.mkDerivation` attributes alongside the Bun-specific
attributes below. Where applicable, these follow their `npm` counterparts in
`buildNpmPackage`.

### Runtime and native toolchain

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bun` | provided Bun | Bun package used for fetching and hooks (>= 1.4.4), and for executable wrappers by default |
| `runtime` | selected `bun` | Runtime for installed wrappers and dependency Node shebangs |
| `nodeGypTarget` | selected `runtime` | Target whose headers and Node.js version are used to compile native addons; does not select the build interpreter |
| `nodeGyp` | `false` | Add standalone node-gyp, Python and headers for `nodeGypTarget` |

### Dependency fetching

By default, the builder calls `fetchBunDeps` with `bunDepsHash`. Supplying
`bunDeps` replaces that fetch step with an existing cache or importer bundle.

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bunDepsHash` | `""` | Recursive SHA-256 SRI hash of the dependency cache |
| `bunDeps` | fetched from `src` | Reuse an existing dependency cache derivation/path |
| `bunMigrateLockfile` | `false` | Enable build-side migration replay and, with the default `bunDeps`, fetch-side migration; explicit fetchers must enable migration separately |
| `bunDepsNativeBuildInputs` | `[]` | Tools/setup hooks explicitly needed for fetching or source preparation, e.g. Git or jq |
| `bunDepsImpureEnvVars` | `[]` | Names of builder environment variables to expose only to dependency fetching, e.g. registry tokens |
| `bunFetchFlags` | `[]` | Extra `bun pm fetch` arguments |
| `makeCacheWritable` | `false` | Copy the dependency cache to writable temporary storage; implied by `bunRunScripts` |

### Project selection

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bunRoot` | `"."` | Lockfile/workspace root relative to the unpacked source root |
| `bunWorkspace` | `null` | Workspace directory relative to `bunRoot`; selects its build script, bins and manuals. Dependencies are fetched for the entire lockfile. |

### Build, check, and install

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bunInstallFlags` | `[]` | Extra install arguments |
| `bunRunScripts` | `false` | Prepare a private cache before permitting Bun's trusted install scripts; otherwise append `--ignore-scripts` |
| `bunBuildScript` | `"build"` | Script passed to `bun run` |
| `bunCheckScript` | `null` | Package script to check with `bun run`; otherwise use `bun test`; requires `doCheck = true` |
| `bunFlags` | `[]` | Common Bun options before script names, applied to fetch, install, run, test, pack and prune; e.g. `[ "--silent" ]` |
| `bunBuildFlags` | `[]` | Arguments passed to the build script |
| `bunCheckFlags` | `[]` | Arguments passed to `bun test` or the selected check script |
| `dontBunBuild` | `false` | Skip the default build script |
| `dontBunCheck` | `false` | Disable the default check hook |
| `dontBunPrune` | `false` | Retain dev dependencies in the default installation |
| `bunPruneFlags` | `[]` | Extra arguments to `bun prune` |
| `bunPackFlags` | `[]` | Extra `bun pm pack` arguments |
| `makeWrapperArgs` | `[]` | Additional arguments for each executable wrapper |
| `dontBunInstall` | `false` | Disable the default install phase |

### Hooks

Use shell hooks to extend dependency installation, or replace a setup hook to
change an entire step. The [setup hook inventory](#setup-hooks) describes the
available implementations.

| Attribute | Default | Purpose |
| --- | --- | --- |
| `preBunInstall`, `postBunInstall` | unset | Hooks around offline installation; the pre-hook runs before automatic source/cache preparation |
| `preBunInstallScripts` | unset | With `bunRunScripts`, runs after the initial script-free install and automatic patching, before the forced reinstall; `bunPreparedCachePackages` contains the selected writable cache directories |
| `bunConfigHook`, `bunBuildHook`, `bunCheckHook`, `bunInstallHook` | default hooks | Replace individual setup hooks |

## fetchBunDeps

`fetchBunDeps` returns a fixed-output dependency cache as created by Bun. It accepts
standard `stdenvNoCC.mkDerivation` attributes for source preparation and the
following fetching attributes:

| Attribute | Default | Purpose |
| --- | --- | --- |
| `name` | `"bun-deps"` | Cache derivation name |
| `hash` | `""` | Recursive dependency-cache hash; corresponds to the builder's `bunDepsHash` |
| `bunRoot` | `"."` | Lockfile root relative to the unpacked source |
| `bunMigrateLockfile` | `false` | Migrate a foreign lockfile if no Bun lockfile exists |
| `bunFlags`, `bunFetchFlags` | `[]` | Common Bun flags and fetch-specific flags |
| `nativeBuildInputs` | `[]` | Extra fetcher tools; corresponds to `bunDepsNativeBuildInputs` |
| `impureEnvVars` | Proxy variables | Builder environment variable names allowed during fetching; corresponds to `bunDepsImpureEnvVars` |

The default name above applies to direct calls. When called by
`buildBunPackage`, the fetcher receives `"${name}-bun-deps"`, where `name` is the
parent derivation's name (normally `"${pname}-${version}"`).

Override the helper's `bun` argument to select a different Bun package.
See [dependency fetching](./packaging.md#dependency-fetching) for provider choice
and migration, and [private registries](./packaging.md#private-registries) for credentials.

## importBunLock

`importBunLock` is an experimental alternative to `fetchBunDeps`. It returns a
source bundle for a text `bun.lock`; use it as the builder's `bunDeps`. There is
no aggregate hash: remote sources use individual integrity hashes or pinned Git
commits. Missing pins can be supplied through `fetcherOpts`.
See the [import workflow](./packaging.md#import-a-lockfile-without-bundepshash-experimental).

| Argument | Default | Purpose |
| --- | --- | --- |
| `src` | required | Source directory; used to locate the default lockfile |
| `bunRoot` | `"."` | Project directory relative to `src`, matching the builder's `bunRoot` |
| `lockFile` | `src + "/${bunRoot}/bun.lock"` | Text lockfile to import; must match the package build's lockfile byte for byte |
| `name` | `"imported-bun-deps"` | Source-bundle derivation name |
| `registry` | `"https://registry.npmjs.org"` | Registry for packages whose lockfile URL is empty |
| `scopedRegistries` | `{}` | Registry URLs keyed by scope, e.g. `"@myorg"` |
| `fetcherOpts` | `{}` | Per-package options for `fetchurl`, `fetchgit`, or `builtins.fetchGit`, keyed by the exact key in `bun.lock`'s `packages` object |

## Setup hooks

`buildBunPackage` selects these hooks for you. To compose them with
`stdenv.mkDerivation`, add the required members of `pkgs.bunHooks` to
`nativeBuildInputs`. Hooks propagate their required tools and supporting hooks.

| Hook | Purpose and timing |
| --- | --- |
| `bunRuntimeHook` | Supplies Bun and a `node` fallback; registers output shebang fixups for the selected runtime |
| `bunFetchMigrateHook` | Runs foreign-lockfile migration after source patching in the dependency fetcher and records the result |
| `bunMigrateHook` | Replays a cached migration after source patching, before dependency configuration in the package build |
| `bunConfigHook` | Validates an extracted cache and installs dependencies offline after source patching; prepares shebangs, optional ELF fixups, and lifecycle scripts |
| `bunImportConfigHook` | Adapts a source bundle for installation through `bunConfigHook`; also exposed as `importBunLock.bunConfigHook` |
| `bunBuildHook` | Supplies the default build phase, running the selected package script |
| `bunCheckHook` | Supplies the default check phase, running `bun test` or the selected check script |
| `bunInstallHook` | Supplies the default install phase, pruning dependencies, packing publishable files, and installing wrappers and manuals |
| `bunNodeGypHook` | Configures node-gyp, Python, and local target headers for native builds |

## Custom phases

Dependency configuration runs in `postPatchHooks`, even with a custom
`configurePhase`. A custom `patchPhase` must call `runHook prePatch` and
`runHook postPatch` to retain it.

The build, check, and install hooks supply phases only when no corresponding
phase is provided and their opt-out (`dontBunBuild`, `dontBunCheck`, or
`dontBunInstall`) is unset.
Custom phases must enter `bunRoot` themselves and restore the directory before
the next phase. `preBunInstall`, `preBunInstallScripts`, and `postBunInstall`
run inside `bunRoot`.

For the default dependency fetcher, the builder forwards `src`, `srcs`,
`sourceRoot`, `prePatch`, `patchPhase`, `patches`, `postPatch`, and `patchFlags`.
It does not forward package `nativeBuildInputs`, `buildInputs`, or `env`.
See [source preparation](./packaging.md#prepare-sources-for-fetching) for sharing
patch tools and supplying a custom fetcher.

## Dependency preparation hooks

The installation hooks expose three points for dependency edits:

| Shell hook | Contract |
| --- | --- |
| `preBunInstall` | Runs after cache setup and before project shebang patching and installation; imported archives may not yet be extracted |
| `preBunInstallScripts` | Runs only with `bunRunScripts = true`, after the initial script-free install and automatic shebang/ELF preparation, before the forced reinstall |
| `postBunInstall` | Runs after the final dependency install and its shebang/ELF preparation, before the build phase |

In `preBunInstallScripts`, the Bash array `bunPreparedCachePackages` contains the
selected writable cache directories. Apply dependency edits there so they
survive the reinstall. Prepare any new
executable files added by your hook as needed.

## Shebang fixup

Dependency preparation patches shebangs for the build environment. During the
standard `fixupPhase`, we patch shebangs again to potentially replace installed Node shebangs to use `runtime`.
Development outputs retain build interpreters.

Custom install phases must retain `fixupPhase` or perform their own shebang
fixup. Set `dontPatchShebangs` to disable automatic output patching. The
[design notes](./design.md#native-toolchain-implementation) describe how runtime
selection and interpreter rewriting are implemented.

## Native toolchain overrides

`buildBunPackage` selects matching hooks through its `bun`, `runtime`, and
`nodeGypTarget` attributes. When using hooks directly, override `bunHooks`
instead, for example:

```nix
(pkgs.bunHooks.override { runtime = pkgs.nodejs; }).bunInstallHook
```

For further toolchain customization, `bunHooks` accepts these overrides:

| Argument/property | Purpose |
| --- | --- |
| `bun` | Bun package propagated by the hooks; override when using another Bun directly |
| `runtime` | Installed runtime; defaults to `bun` |
| `nodeGypTarget` | Target for addon headers; defaults to `runtime` |
| `python3` | Python used by node-gyp |
| `bunNodeHeaders` | Fallback headers for Bun targets without a `nodeHeaders` property |

A Bun target can expose custom headers as `passthru.nodeHeaders`; the header
derivation must expose `version`. For a Node.js target, headers come from that
package's source. The standalone tools are `pkgs.bunNodeGyp` and
`pkgs.bunNodeHeaders`.

## Package-set integration

The helpers can be used through an overlay or the flake's smaller package set.
Apply `bunflake.overlays.default` to use your own Nixpkgs package set and access
`pkgs.buildBunPackage`. The overlay replaces `pkgs.bun` only when this
repository's Bun is newer. Nixpkgs follows `nixos-unstable`, with its revision
recorded in `flake.lock`.

Without the overlay, `bunflake.legacyPackages.${system}` exposes `bun`,
`buildBunPackage`, `fetchBunDeps`, `importBunLock`, `bunNodeGyp`, `bunNodeHeaders`,
and the grouped `bunHooks`. This set contains only this project's helpers and
tools. Customize the package set through overlays, or use individual helpers'
`override` and packages' `overrideAttrs` methods.

The `packages.${system}` output exposes `bun`, `bunNodeGyp`, `bunNodeHeaders`, and
real-world examples named `example-<name>`, with no default package.

For direct `stdenv.mkDerivation` use, supply `bunDeps` and select the
[setup hooks](#setup-hooks) for the phases you need.
