# Reference

[README](../README.md) · [Packaging guide](./packaging.md) · [Reference](./reference.md) · [Design](./design.md) · [Contributing](../CONTRIBUTING.md)

- [Package-set integration](#package-set-integration)
- [buildBunPackage](#buildbunpackage)
- [fetchBunDeps](#fetchbundeps)
- [importBunLock](#importbunlock)
- [Flags and custom phases](#flags-and-custom-phases)
- [Dependency preparation hooks](#dependency-preparation-hooks)
- [Shebang fixup](#shebang-fixup)
- [Native toolchain overrides](#native-toolchain-overrides)

## Package-set integration

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

To use the hooks with `stdenv.mkDerivation`, add the desired hooks from
`pkgs.bunHooks` to `nativeBuildInputs` and supply `bunDeps`. Each hook propagates
the Bun package it was configured with.
The config and install hooks require Bun >= 1.4.4 and check this when selected,
including when used independently of `buildBunPackage`.

## buildBunPackage

These are Nix derivation attributes. With the overlay, the builder is
`pkgs.buildBunPackage`; without it, use `bunflake.legacyPackages.${system}.buildBunPackage`.

### Runtime and native toolchain

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bun` | provided Bun | Bun package used for fetching and hooks (>= 1.4.4), and for executable wrappers by default |
| `runtime` | selected `bun` | Runtime for installed wrappers and dependency Node shebangs |
| `nodeGypTarget` | selected `runtime` | Target whose headers and Node.js version are used to compile native addons; does not select the build interpreter |
| `nodeGyp` | `false` | Add standalone node-gyp, Python and headers for `nodeGypTarget` |

### Dependency fetching

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bunDepsHash` | `""` | Recursive SHA-256 SRI hash of the dependency cache |
| `bunDeps` | fetched from `src` | Reuse an existing dependency cache derivation/path |
| `bunMigrateLockfile` | `false` | Allow migration from another package manager's lockfile when no Bun lockfile is present; also available on `fetchBunDeps` |
| `bunDepsNativeBuildInputs` | `[]` | Tools/setup hooks explicitly needed for fetching or source preparation, e.g. Git or jq |
| `bunDepsImpureEnvVars` | `[]` | Names of builder environment variables to expose only to dependency fetching, e.g. registry tokens |
| `bunFetchFlags` | `[]` | Extra `bun pm fetch` arguments |
| `makeCacheWritable` | `false` | Copy the dependency cache to writable temporary storage; implied by `bunRunScripts` |

### Project selection

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bunRoot` | `"."` | Lockfile/workspace root relative to the unpacked source root |
| `bunWorkspace` | `null` | Workspace directory relative to `bunRoot`; selects its build script, bins and manuals |

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

| Attribute | Default | Purpose |
| --- | --- | --- |
| `preBunInstall`, `postBunInstall` | unset | Hooks around offline installation; the pre-hook runs before automatic source/cache preparation |
| `preBunInstallScripts` | unset | With `bunRunScripts`, runs after the initial script-free install and automatic patching, before the forced reinstall; `bunPreparedCachePackages` contains the selected writable cache directories |
| `bunConfigHook`, `bunBuildHook`, `bunCheckHook`, `bunInstallHook` | default hooks | Replace individual setup hooks |

## fetchBunDeps

`fetchBunDeps` returns a fixed-output extracted dependency cache. It accepts
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

Override the helper's `bun` argument to select a different Bun package.
See [dependency fetching](./packaging.md#dependency-fetching) for provider choice
and migration, and [private registries](./packaging.md#private-registries) for credentials.

## importBunLock

Experimental. Returns a source bundle for a text `bun.lock`; use it as the
builder's `bunDeps`. See the [import workflow](./packaging.md#import-a-lockfile-without-bundepshash-experimental).

| Argument | Default | Purpose |
| --- | --- | --- |
| `src` | required | Source directory; used to locate the default lockfile |
| `bunRoot` | `"."` | Project directory relative to `src`, matching the builder's `bunRoot` |
| `lockFile` | `src + "/${bunRoot}/bun.lock"` | Text lockfile to import; must match the package build's lockfile byte for byte |
| `name` | `"imported-bun-deps"` | Source-bundle derivation name |
| `registry` | `"https://registry.npmjs.org"` | Registry for packages whose lockfile URL is empty |
| `scopedRegistries` | `{}` | Registry URLs keyed by scope, e.g. `"@myorg"` |
| `fetcherOpts` | `{}` | Per-package options for `fetchurl`, `fetchgit`, or `builtins.fetchGit`, keyed by the exact key in `bun.lock`'s `packages` object |

## Flags and custom phases

The builder enables `__structuredAttrs` by default. In custom shell phases,
list attributes are Bash arrays; use `env` for values that child processes need
in their environment. Set `__structuredAttrs = false;` for compatibility with
phases that require the older attribute representation.

Only put options accepted by fetch, install, run, test, pack, and prune in `bunFlags`;
use command-specific attributes for other options. `bunBuildFlags` are arguments
to the build script, so Bun options belong in `bunFlags`.

Hooks accept strings, structured arrays, and shell `*FlagsArray` variables using
stdenv's `concatTo` convention. Set `__structuredAttrs = true` when hook flag
arguments contain spaces; ordinary unstructured list attributes become
space-separated strings. The fetcher uses the same convention: `preInstall`
can modify `bunFlags` and `bunFetchFlags` or add arguments through
`bunFlagsArray` and `bunFetchFlagsArray`.

The config hook runs in `postPatchHooks`, even with a custom `configurePhase`.
The build, check, and install hooks supply phases only when no corresponding phase is
provided and their opt-out is unset. Each hook restores the working directory;
custom phases must enter `bunRoot` themselves and restore the directory before
the next phase. `preBunInstall`, `preBunInstallScripts`, and `postBunInstall`
run inside `bunRoot`.

Source selection (`src`, `srcs`, `sourceRoot`) and common patch settings
(`prePatch`, `patchPhase`, `patches`, `postPatch`, `patchFlags`) are forwarded to the dependency
fetcher, but package `nativeBuildInputs`, `buildInputs`, and `env` are not.
If a shared `postPatch` needs jq, add it to both `nativeBuildInputs` and
`bunDepsNativeBuildInputs`; Git dependencies normally need Git only in
`bunDepsNativeBuildInputs`. For custom unpacking, fetcher environment, or phases,
supply `bunDeps = fetchBunDeps { ... };` explicitly. Direct fetcher calls use `hash`
instead of `bunDepsHash`, and `nativeBuildInputs` instead of
`bunDepsNativeBuildInputs`.
Custom `patchPhase` implementations must call `runHook prePatch` and
`runHook postPatch`, as in a normal stdenv build. Foreign-lockfile migration
uses the patched manifests in both the fetcher and package build. When supplying
`bunDeps` separately, enable `bunMigrateLockfile` on both `buildBunPackage` and
`fetchBunDeps`, and keep the foreign lockfiles, `pnpm-workspace.yaml`, and
`.yarnrc.yml` consistent with the cached migration inputs. For independent hook
use with a migrated cache, add `bunHooks.bunMigrateHook` alongside
`bunHooks.bunConfigHook` in `nativeBuildInputs`.

## Dependency preparation hooks

`preBunInstallScripts` runs after the initial script-free install and automatic shebang/ELF
patching, before the forced reinstall. It runs only with `bunRunScripts = true`.
The Bash array `bunPreparedCachePackages` contains the selected writable cache
directories. Apply custom dependency edits there: replacing symlinked files in
the staging `node_modules` tree can leave the cache unchanged, so those edits
would be lost during the reinstall. Prepare any new executable files added by
the hook as needed. `postBunInstall` runs after the final install and its fixups.

## Shebang fixup

Early shebang patching uses build interpreters. An output fixup hook runs
`patchShebangs --host --update` to select `runtime` for installed Node shebangs,
including previously patched store paths and files copied by custom install
phases. Development outputs use the build environment with `--build --update`.
A small helper handles absolute commands after `env -S`, which the pinned
nixpkgs `patchShebangs` cannot repatch. Custom phases must retain the standard
`fixupPhase` (or perform their own shebang fixup); `dontPatchShebangs` disables
automatic output patching.

## Native toolchain overrides

The standalone helpers are `pkgs.bunNodeGyp` and `pkgs.bunNodeHeaders`.
To attach custom headers to a Bun target, set its `passthru.nodeHeaders`;
header derivations must expose `version`. Override `bunHooks`' `bunNodeHeaders`
argument to change the fallback used by Bun targets without that property, or
its `python3` argument to use another Python. When using hooks independently
with another Bun, override their `bun` argument too.
`buildBunPackage` selects matching hooks automatically through its `bun`,
`runtime`, and `nodeGypTarget` attributes. Direct hook users can override these
arguments on `bunHooks`, for example
`(pkgs.bunHooks.override { runtime = pkgs.nodejs; }).bunInstallHook`.
