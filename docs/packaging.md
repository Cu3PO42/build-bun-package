# Packaging guide

[README](../README.md) · [Packaging guide](./packaging.md) · [Reference](./reference.md) · [Design](./design.md) · [Contributing](../CONTRIBUTING.md)

Start with the [quick start](../README.md#quick-start) for a complete flake.
Examples below show attributes to add to that package unless they show a complete
builder call. In examples using `pkgs`, use your Nixpkgs package set for the
selected system (for example, `nixpkgs.legacyPackages.${system}`). For defaults
and hook contracts, use the [reference](./reference.md).

- [Packaging guide](#packaging-guide)
  - [Workspaces and nested projects](#workspaces-and-nested-projects)
  - [Build and install customization](#build-and-install-customization)
    - [Customize phases and flags](#customize-phases-and-flags)
  - [Lifecycle scripts and native dependencies](#lifecycle-scripts-and-native-dependencies)
    - [Use Node.js](#use-nodejs)
    - [Compile native dependencies](#compile-native-dependencies)
    - [Prepare Linux binaries](#prepare-linux-binaries)
    - [Use the native toolchain in a development shell](#use-the-native-toolchain-in-a-development-shell)
  - [Dependency fetching](#dependency-fetching)
    - [Choose a dependency provider](#choose-a-dependency-provider)
    - [Migrate another package manager's lockfile (experimental)](#migrate-another-package-managers-lockfile-experimental)
    - [Import a lockfile without `bunDepsHash` (experimental)](#import-a-lockfile-without-bundepshash-experimental)
    - [Configure importer registries and fetchers](#configure-importer-registries-and-fetchers)
    - [Prepare sources for fetching](#prepare-sources-for-fetching)
  - [Private registries](#private-registries)
  - [Updating packages](#updating-packages)

## Workspaces and nested projects

The quick start assumes that the lockfile and application live at the source
root. For a nested project, set `bunRoot` to the directory containing the
lockfile, relative to the unpacked source root. Dependency commands then run
from that directory.

A monorepo introduces a second choice: which workspace to build and expose as
the installed application. Set `bunWorkspace = "apps/my-app";` to select that
workspace's build script, executables, and manuals. The value is a directory
relative to `bunRoot`, not a package name or filter pattern.

Dependencies are fetched for the complete lockfile, and installed and pruned
for the whole workspace by default. Use `bunInstallFlags` and `bunPruneFlags`
for Bun's install/prune filters if needed; these do not reduce fetching. This
also means several workspace packages can share the same `bunDeps`.

Local packages, workspace bins, and `patchedDependencies` may require Bun to
write to its cache. If installation fails because the store cache is read-only,
set `makeCacheWritable = true` to give the build a private copy. Enabling
`bunRunScripts` also makes the cache writable.

## Build and install customization

After installing dependencies, the builder runs `bun run build`. Set
`bunBuildScript` to choose another script, or `dontBunBuild = true` for a
package that needs no build step.

To check the result before installation, set `doCheck = true`. This runs
`bun test` in the selected workspace. For a package.json test script or another
test runner, set `bunCheckScript = "test";` to run `bun run test` instead.
`bunCheckFlags` supplies test arguments.

The default install phase prunes development dependencies and installs the
package's publishable files, dependencies, executables, and manuals. Set
`dontBunPrune = true` if the installed application needs development dependencies.
For a bundled executable or static website, replace `installPhase` to install
only the build output:

```nix
bunflake.legacyPackages.${system}.buildBunPackage {
  pname = "my-site";
  version = "1.0.0";
  src = ./.;
  bunDepsHash = "sha256-…";
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R dist/. "$out/"
    runHook postInstall
  '';
}
```

### Customize phases and flags

Before replacing a whole phase, consider whether a `preBuild`, `postBuild`,
`preCheck`, or `postCheck` hook is enough. These let you extend the default
behavior while retaining its workspace selection and directory handling.

When replacing a phase, enter `bunRoot` yourself before using relative project
paths. For example, the `dist` path above assumes the project is at the source
root. Keep the standard `fixupPhase` so the runtime and binary fixups still run.
The [phase contract](./reference.md#flags-and-custom-phases) specifies when each
hook runs and which opt-outs disable default phases.

Use command-specific flags for options that apply to only one step. In
particular, `bunBuildFlags` supplies arguments to the build script; Bun options
belong in `bunFlags`, which is shared by fetch, install, run, test, pack, and
prune. Only put options accepted by all those commands in `bunFlags`.

The builder enables `__structuredAttrs` by default, so list attributes are Bash
arrays in custom shell phases. Use `env` for values that child processes need
in their environment. Older phases that require space-separated list strings
can opt out with `__structuredAttrs = false`, but then flag values containing
spaces will no longer remain separate arguments.

## Lifecycle scripts and native dependencies

Some dependencies need installation scripts to generate files or prepare native
code. These scripts are disabled by default; enable them with
`bunRunScripts = true`. Bun's dependency trust rules still apply, and an explicit
`--ignore-scripts` in `bunInstallFlags` or upstream configuration can still
disable scripts.

Scripts run in the Nix build environment. Depending on what they do, you may
need to supply Node.js, a compiler toolchain, or libraries for prebuilt binaries,
as described below.

### Use Node.js

The installed runtime defaults to the selected `bun` package. To run installed
wrappers with Node.js, set `runtime`:

```nix
{
  runtime = pkgs.nodejs-slim;
}
```

A Node.js `runtime` is also made available during the build. To use Node.js only
for building while keeping Bun for the installed application, add it to the
usual build inputs:

```nix
{
  nativeBuildInputs = [ pkgs.nodejs-slim ];
}
```

If no `node` command is available, `bunRuntimeHook` supplies a link to Bun.
Shell phases and lifecycle scripts use this same build environment.

Custom install phases must retain the standard `fixupPhase` so installed
shebangs use the selected runtime; see [shebang fixup](./reference.md#shebang-fixup).

Bun still fetches, installs, and patches dependencies regardless of `runtime`.
The standard build hook invokes `bun run`, which respects Node shebangs.
To run those tools with Bun, leave Node.js out of the build environment or patch
their interpreters explicitly. Once Nix has patched a shebang to an absolute
Node.js path, `--bun` does not redirect that interpreter to Bun.

### Compile native dependencies

Bun can load prebuilt Node-API addons directly; Linux binaries may need the ELF
fixups described below. To compile dependencies with node-gyp, enable the
optional toolchain:

```nix
{
  nodeGyp = true;
  bunRunScripts = true;
  # Optional: use Node.js for building instead of Bun.
  nativeBuildInputs = [ pkgs.nodejs ];
}
```

node-gyp runs with the build environment's `node` command and compiles against
headers for `nodeGypTarget`, which defaults to `runtime`.
The target setting is independent of the runtime executing the build: it
selects the runtime that will load the compiled addon. The hooks provide local
headers for that target, so node-gyp does not need to download them. See
[toolchain overrides](./reference.md#native-toolchain-overrides) to use custom
headers.

The toolchain supplies Python, node-gyp, and local headers; stdenv supplies the
compiler. Add package-specific libraries through the usual inputs. For addons
used only by Node.js build tools, select that compilation target explicitly:

```nix
{
  nativeBuildInputs = [ pkgs.nodejs ];
  nodeGypTarget = pkgs.nodejs;
  nodeGyp = true;
  bunRunScripts = true;
  # The installed application still uses Bun.
}
```

An addon loaded during both build and runtime must be compatible with both
consumers. For Node-API addons, this includes choosing a `NAPI_VERSION` supported
by both; selecting headers does not set that value for you. Addons tied to V8
may need upstream changes to work with Bun. If the runtimes need incompatible
builds, provide separate dependency trees through custom phases; the builder
does not automate that setup.

Packages that download prebuilt binaries can often use Nix-provided binaries
and upstream skip-download settings instead.

### Prepare Linux binaries

Prebuilt Linux binaries often refer to a dynamic loader and libraries at paths
that do not exist in a Nix build. `autoPatchelfHook` adjusts these references to
use Nix store paths. Add it to `nativeBuildInputs` and supply the required
libraries through `buildInputs`:

```nix
{
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];
}
```

The Bun hooks perform early ELF preparation only when `autoPatchelfHook` is
present and `dontAutoPatchelf` is unset. This step runs after dependency installation, before build and check phases.
With `bunRunScripts = true`, it also prepares selected cache packages and
project binaries before lifecycle scripts run.

Early preparation uses relative `$ORIGIN` paths for bundled libraries so they
remain usable when the package tree is copied. Preserve the relative layout of
binaries and their bundled libraries in custom install phases. The usual
`autoPatchelfHook` output fixup still runs afterward; `dontAutoPatchelf = true`
disables both steps. See the [installation design](./design.md#installation-stages)
for how this fits around dependency patches and scripts.

### Use the native toolchain in a development shell

For a development shell with the native toolchain, use:

```nix
pkgs.mkShell {
  packages = [ pkgs.bunHooks.bunNodeGypHook ];
}
```

Run `bun install` normally, or `node-gyp rebuild` from a package with
`binding.gyp`. For Node.js execution and headers, add `pkgs.nodejs` alongside
`(pkgs.bunHooks.override { nodeGypTarget = pkgs.nodejs; }).bunNodeGypHook`. For just Bun
and runtime setup, use `pkgs.bunHooks.bunRuntimeHook` instead.

## Dependency fetching

### Choose a dependency provider

A dependency provider
fetches the locked sources first; the package build then installs them offline.
The default provider lets Bun prepare its own cache, while the experimental
importer uses Nix to fetch each source individually:

| Provider | Use when | Updating dependencies |
| --- | --- | --- |
| `fetchBunDeps` (default) | Using native Bun lockfiles, or opting into experimental foreign-lockfile migration | Recalculate `bunDepsHash` |
| `importBunLock` (experimental) | Using a text `bun.lock` and fetching packages individually from its integrity hashes | Update the lockfile and any explicit fetcher overrides |

`buildBunPackage` uses `fetchBunDeps` implicitly, as in the quick start. Both
providers fetch the complete lockfile even when building a single workspace,
and both require that lockfile to match the build's lockfile exactly.

### Migrate another package manager's lockfile (experimental)

A project does not need to use Bun upstream before you can package it with
`buildBunPackage`. If it has an npm, Yarn, or pnpm lockfile instead, set
`bunMigrateLockfile = true`:

```nix
{
  bunMigrateLockfile = true;
  bunDepsHash = pkgs.lib.fakeHash;
}
```

When neither `bun.lock` nor `bun.lockb` is present, the dependency fetcher runs
`bun pm migrate` before fetching. It saves the generated Bun lockfile and any
manifest edits in the cache, then replays them during the offline package build.
Determine `bunDepsHash` in the same way as in the quick start. Upstream does not
need to commit the generated Bun lockfile.

Supported foreign lockfiles are `npm-shrinkwrap.json`, `package-lock.json`,
`yarn.lock`, and `pnpm-lock.yaml`. The selected Bun version determines which
versions and features it can migrate, and chooses the input when several
lockfiles are present. Unsupported inputs fail rather than falling back to an
unlocked install. Migration is experimental and disabled by default.

Migration uses the patched source in both derivations. Keep the foreign
lockfiles, manifests, `pnpm-workspace.yaml`, and `.yarnrc.yml` consistent between
fetching and building. Unrelated build-side manifest edits can be preserved;
conflicting migration edits fail with the affected manifest.

If you supply `bunDeps = fetchBunDeps { ... };` explicitly, enable
`bunMigrateLockfile` on both that fetcher and `buildBunPackage`: one produces the
migration result and the other replays it. With independent hooks, use
`bunFetchMigrateHook` in the fetcher and `bunMigrateHook` alongside `bunConfigHook`
in the application build.

### Import a lockfile without `bunDepsHash` (experimental)

With `importBunLock`, each remote archive is fetched using its own integrity
hash, usually already recorded in `bun.lock`. This removes the aggregate
`bunDepsHash` and lets Nix reuse individual downloads when dependencies change:

```nix
bunflake.legacyPackages.${system}.buildBunPackage {
  pname = "my-app";
  version = "1.0.0";
  src = ./.;
  bunDeps = bunflake.legacyPackages.${system}.importBunLock { src = ./.; };
}
```

The importer requires a text `bun.lock` available during Nix evaluation. It
parses that file in pure Nix, without import from derivation. For a generated
source, supply an independently available `lockFile` rather than reading it
from an unbuilt derivation. Convert a binary `bun.lockb` with Bun first:

```sh
bun install --save-text-lockfile --frozen-lockfile --lockfile-only
```

The result is a bundle of fetched sources, not a complete Bun install cache, therefore a different setup hook is needed. `buildBunPackage` selects the
appropriate hook automatically; with `stdenv.mkDerivation`, add
`importBunLock.bunConfigHook` to `nativeBuildInputs` instead of the ordinary
cache hook. Installation uses a private writable cache, so `makeCacheWritable`
is unnecessary.

Registry packages, HTTP(S) archives, Git/GitHub dependencies, local archives,
workspaces, and local directory links are supported. Local sources come from
the package source; remote sources need a hash or pinned Git commit. The next
section explains how to supply missing pins and configure their fetchers.
The [source inventory](./design.md#imported-source-types) describes the exact
lockfile representations.

To install archives offline, the hook rewrites remote archive resolutions to
local paths while retaining the dependency graph, version constraints, platform
metadata, and trust list. Those paths remain in the build tree through pruning.
If your build needs the original resolution identities, use `fetchBunDeps`.
The [design notes](./design.md#imported-source-installation) explain this tradeoff.

### Configure importer registries and fetchers

The options in this section are arguments to `importBunLock`. Unlike
`fetchBunDeps`, it uses Nix fetchers directly, so it needs its own registry and
fetcher configuration.

Explicit tarball URLs in the lockfile take precedence over registry defaults.
For an empty URL, set `registry`/`scopedRegistries` to match upstream's registry
configuration. These arguments control Nix fetching; keep the project's
`.npmrc`/`bunfig.toml` for offline installation too.
`importBunLock` does not translate Bun's registry authentication to `fetchurl`.
Use `fetcherOpts`, keyed by the exact entry in `bun.lock`'s `packages` object,
to configure an individual fetch. For example, redirect a private package to a
mirror:

```nix
importBunLock {
  src = ./.;
  scopedRegistries."@myorg" = "https://registry.example.com";
  fetcherOpts."@myorg/package" = {
    url = "https://mirror.example.com/package-1.0.0.tgz";
  };
}
```

For remote archives without an integrity hash, supply `fetcherOpts.<key>.hash`.
Git dependencies use the full locked commit; older entries without one need
`fetcherOpts.<key>.rev`. Without a Git `hash`, the importer uses
`builtins.fetchGit` during evaluation. Adding a Git `hash` selects Nixpkgs'
`fetchgit`, moving the download to a fetcher build. Other Git options follow
the selected fetcher's interface. GitHub entries use integrity-pinned codeload
archives instead.

For private HTTP fetches, use `fetchurl`'s `netrcPhase`/`netrcImpureEnvVars` or other
builder-side credential configuration. Keep credential values out of Nix
expressions and the store. `bunDepsImpureEnvVars` configures `fetchBunDeps`
and does not affect this importer. Updating the imported lockfile replaces the
[aggregate-hash update workflow](#updating-packages).

### Prepare sources for fetching

The dependency fetcher and application build must agree on the prepared
lockfile and manifests. `buildBunPackage` forwards source selection and common
patch settings to its default fetcher, so ordinary patches apply in both places.
A custom `patchPhase` must call `runHook prePatch` and `runHook postPatch` to
retain dependency setup and migration.

Tools needed by shared patch commands must also be present in both derivations.
For example, a `postPatch` using jq needs it in both `nativeBuildInputs` and
`bunDepsNativeBuildInputs`. Package `buildInputs` and `env` are not forwarded;
Git dependencies normally need Git only in `bunDepsNativeBuildInputs`.

For custom unpacking, fetcher environment, or phases, supply
`bunDeps = fetchBunDeps { ... };` explicitly. Direct calls use `hash` instead of
`bunDepsHash`, and `nativeBuildInputs` instead of `bunDepsNativeBuildInputs`.

## Private registries

With the default `fetchBunDeps` provider, Bun performs the network requests.
Keep registry configuration in the source's `bunfig.toml` or `.npmrc`, with
credentials supplied through environment references:

```toml
[install.scopes]
myorg = { url = "https://registry.example.com/", token = "$NPM_TOKEN" }
```

Opt only the required variable names into dependency fetching:

```nix
{
  bunDepsImpureEnvVars = [ "NPM_TOKEN" ];
}
```

For direct `fetchBunDeps` calls, use `impureEnvVars = [ "NPM_TOKEN" ];`.
Proxy variables are retained. The ordinary offline build does not receive
these credentials. Keep the same registry configuration for offline installation:
Bun's cache keys depend on the registry.

Nix needs the values in the **builder process's environment**. With a multi-user
installation, configure the daemon environment, including on remote builders;
exporting a token in the client shell or using `--impure` is not enough.
Nix also offers `impure-env` for trusted users when `configurable-impure-env`
is enabled on the daemon; see the
[Nix documentation](https://nix.dev/manual/nix/2.31/language/advanced-attributes#adv-attr-impureEnvVars).
Never embed token values in Nix `env`, flags, source URLs, or committed
configuration: these enter the Nix store. Private dependency contents also
enter the store/cache.

The importer uses Nix fetchers directly; follow [its registry and fetcher setup](#configure-importer-registries-and-fetchers) instead of using `bunDepsImpureEnvVars`.

## Updating packages

`buildBunPackage` supplies a default `passthru.updateScript` using
`nix-update-script`. It already passes `--custom-dep bunDeps`, so running that
update script updates the source and recalculates the dependency hash without
extra configuration. A caller-provided `passthru.updateScript` takes precedence;
set it to `null` to disable the default. Other passthru attributes are preserved.

Keep the literal `bunDepsHash` in the package's Nix expression so the updater
can rewrite it. If you invoke `nix-update` directly, include the custom dependency
argument yourself:

```sh
nix-update my-app --custom-dep bunDeps
nix-update --flake my-app --custom-dep bunDeps
# Recalculate hashes without changing the version:
nix-update my-app --version=skip --custom-dep bunDeps
```

For a standalone `fetchBunDeps` derivation, `nix-update` recognizes its fixed-output
hash directly; no `--custom-dep` is needed:

```sh
nix-update my-deps --version=skip
```

This updates the literal `hash` in the fetcher's expression. When a package
supplies `bunDeps = fetchBunDeps { ... };` explicitly, `--custom-dep bunDeps` also
works, provided the hash literal is in that package's expression.

The lower-level `update-source-version` can recalculate the cache with
`--source-key=bunDeps --ignore-same-version` after updating the source.

These tools recalculate hashes rather than regenerating lockfiles. Use the
updated upstream lockfile, supply an updated lockfile yourself, or let the
opt-in migration workflow generate one from the updated foreign lockfile.

For `importBunLock`, update the source and lockfile together, along with any
explicit fetcher pins. There is no aggregate hash to update; replace the default
update script if your package needs a different update workflow.
