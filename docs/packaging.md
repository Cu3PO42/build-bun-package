# Packaging guide

[README](../README.md) · [Packaging guide](./packaging.md) · [Reference](./reference.md) · [Design](./design.md) · [Contributing](../CONTRIBUTING.md)

Start with the [quick start](../README.md#quick-start) for a complete flake.
Examples below show attributes to add to that package unless they show a complete
builder call. In examples using `pkgs`, use your Nixpkgs package set for the
selected system (for example, `nixpkgs.legacyPackages.${system}`). For defaults
and hook contracts, use the [reference](./reference.md).

- [Workspaces and nested projects](#workspaces-and-nested-projects)
- [Build and install customization](#build-and-install-customization)
- [Lifecycle scripts and native dependencies](#lifecycle-scripts-and-native-dependencies)
- [Dependency fetching](#dependency-fetching)
- [Private registries](#private-registries)
- [Updating packages](#updating-packages)

## Workspaces and nested projects

Set `bunRoot` to the directory containing the lockfile, relative to the unpacked
source root. For a monorepo, set `bunWorkspace = "apps/my-app";` to select a
workspace's build script, executables, and manuals. This is a directory relative
to `bunRoot`, not a package name or filter pattern.

Dependencies are fetched for the complete lockfile, and installed and pruned
for the whole workspace by default. Use `bunInstallFlags` and `bunPruneFlags`
for Bun's install/prune filters; these do not reduce fetching. Several workspace
packages can share the same `bunDeps`.

Set `makeCacheWritable = true` if Bun needs to update the cache for local
packages, workspace bins, or `patchedDependencies`. It is already implied by
`bunRunScripts = true`.

## Build and install customization

Set `dontBunPrune = true` to keep development dependencies in the default
installation. To select another build script, set `bunBuildScript`.

Set `doCheck = true` to run `bun test` before installation and pruning. For a
package.json test script or another test runner, set `bunCheckScript = "test";`
to run `bun run test` instead. `bunCheckFlags` supplies test arguments. Checks
use the selected `bunWorkspace`, and respect `preCheck`, `postCheck`, and a
custom `checkPhase`. Set `dontBunCheck = true` to disable the default check hook.

For a bundled executable or static website, override `installPhase` to install
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

Custom phases follow the [phase and flag contracts](./reference.md#flags-and-custom-phases).
For nested projects, enter `bunRoot` before using relative build-output paths.

## Lifecycle scripts and native dependencies

Enable install scripts with `bunRunScripts = true`. Bun's dependency trust rules
still apply, and an explicit `--ignore-scripts` in `bunInstallFlags` or upstream
configuration can still disable scripts. This option controls installation;
the build hook runs independently, and packing always skips scripts.

### Use Node.js

The installed runtime defaults to the selected `bun` package. Set `runtime` to
Node.js for installed wrappers, dependency Node shebangs, and `node` subprocesses:

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

The shared `bunRuntimeHook` preserves the build's existing `node` command and
adds a Bun alias only when Node.js is absent. Shell phases and lifecycle scripts
use the same build environment. Installed wrappers supply `runtime` as `node`
for child processes.

Custom install phases must retain the standard `fixupPhase` so installed
shebangs use the selected runtime; see [shebang fixup](./reference.md#shebang-fixup).

Bun still fetches, installs, packs, and prunes dependencies, and the build hook
invokes `bun run`. Explicit `bun` commands and direct source-file execution use
Bun. `--bun` or `run.bun = true` in `bunfig.toml` can force Bun for commands
resolved through `PATH`. A Node shebang already patched to an absolute
interpreter still uses that interpreter during the build.

### Compile native dependencies

Bun can load prebuilt Node-API addons directly; Linux binaries may need the ELF
fixups described below. To compile dependencies with node-gyp, enable the optional toolchain:

```nix
{
  nodeGyp = true;
  bunRunScripts = true;
  # Optional: use Node.js throughout instead of Bun.
  runtime = pkgs.nodejs;
}
```

node-gyp runs with the build environment's `node` command and compiles against
headers for `nodeGypTarget`, which defaults to `runtime`. Changing the target
does not change the interpreter executing node-gyp or other build commands.
For a Bun target, the hooks prefer its `nodeHeaders` property and fall back to
`pkgs.bunNodeHeaders` when that property is absent. Our Bun package exposes these
headers through `passthru.nodeHeaders`. For a Node.js target, the headers come
from that package's source.

The hook compares the selected Bun target's reported Node.js compatibility
version with the headers' version. A mismatch emits a build-log warning with
both versions and the headers path; it does not fail the build. Stable Node-API
addons can remain compatible across header releases. Their targeted API version
must be supported by each runtime that loads them, and matching Node.js versions
does not make V8-specific addons compatible with Bun.

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
consumers. Selecting headers does not itself set an addon's `NAPI_VERSION`.
Incompatible addons need separate builds or dependency trees. Use install checks
to exercise the application's actual native addons with the final runtime.

If only a specific setup command is needed, leave automatic scripts disabled
and run it after dependency shebangs have been patched:

```nix
{
  nodeGyp = true;
  postBunInstall = ''
    (
      cd node_modules/my-native-addon
      node-gyp rebuild
    )
  '';
}
```

Supply any required root or workspace setup explicitly and in dependency order.
Packages that download prebuilt binaries can often use Nix-provided binaries
and upstream skip-download settings instead.

### Prepare Linux binaries

On Linux, add `pkgs.autoPatchelfHook` to `nativeBuildInputs` to prepare prebuilt
ELF executables and libraries before build/check phases. Supply their libraries
through `buildInputs` and configure the usual autoPatchelf settings as needed:

```nix
{
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];
}
```

With `bunRunScripts = true`, selected cache packages and project binaries are
also prepared before lifecycle scripts execute. Foreign platform packages in
the cache are left untouched. Early patching uses autoPatchelf's
`--relativize-rpath` so bundled libraries use `$ORIGIN` paths that survive copying
the package tree. Keep the relative layout of binaries and their bundled
libraries when writing a custom install phase. The standard autoPatchelf output
fixup still runs; no extra pre-fixup rebasing pass is needed.
`dontAutoPatchelf = true` disables both early patching and the standard output
fixup.

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

Build with Nix sandboxing enabled to enforce network isolation for lifecycle and
build scripts. Bun's `--offline` applies to installation; scripts can attempt
their own downloads. Supply any extra assets separately.

## Dependency fetching

### Choose a dependency provider

| Provider | Use when | Updating dependencies |
| --- | --- | --- |
| `fetchBunDeps` (default) | Using native Bun lockfiles, or opting into experimental foreign-lockfile migration | Recalculate `bunDepsHash` |
| `importBunLock` (experimental) | Using a text `bun.lock` and fetching packages individually from its integrity hashes | Update the lockfile and any explicit fetcher overrides |

The quick start uses `fetchBunDeps` implicitly. Both providers fetch the complete
lockfile even when building a single workspace. The cache must match the build's
lockfile byte for byte.

### Migrate another package manager's lockfile (experimental)

`fetchBunDeps` delegates lockfile parsing to Bun, so the approach can
fundamentally work with any lockfile format supported by the selected Bun
version: text `bun.lock`, binary `bun.lockb`, and other package managers'
lockfiles through [Bun's upstream migration support](https://bun.com/docs/pm/lockfile#automatic-lockfile-migration),
including supported npm, Yarn, and pnpm formats. This also applies when
`buildBunPackage` calls `fetchBunDeps` implicitly through `bunDepsHash`.
Migration is opt-in: set `bunMigrateLockfile = true` in `buildBunPackage` or
`fetchBunDeps` to enable it. The default is `false`, requiring a committed
`bun.lock` or `bun.lockb`. With migration enabled and neither Bun lockfile present,
`fetchBunDeps` runs `bun pm migrate` before fetching.
Supported foreign lockfiles are `npm-shrinkwrap.json`,
`package-lock.json`, `yarn.lock`, and `pnpm-lock.yaml`; the selected Bun version
determines which versions and features it can migrate. Bun handles selection
when several lockfiles are present. Unsupported inputs fail without falling
back to an unlocked install.

### Import a lockfile without `bunDepsHash` (experimental)

`importBunLock` is an alternative to `fetchBunDeps` that fetches each tarball
using the integrity hash already recorded in a text `bun.lock`. It requires
that text-based Bun lockfile and cannot directly import binary `bun.lockb` or
another package manager's lockfile. Convert those with Bun first.

```nix
bunflake.legacyPackages.${system}.buildBunPackage {
  pname = "my-app";
  version = "1.0.0";
  src = ./.;
  bunDeps = bunflake.legacyPackages.${system}.importBunLock { src = ./.; };
}
```

With the overlay, use `pkgs.importBunLock`. It returns a bundle of fetched
archives rather than an extracted Bun cache. `buildBunPackage` selects its config
hook automatically. With `stdenv.mkDerivation`, add
`importBunLock.bunConfigHook` to `nativeBuildInputs` instead of the cache hook.
The hook validates the original lockfile, redirects fetched resolutions to local
archives, and installs with `--offline --frozen-lockfile`. The locked dependency
graph, manifest version constraints, platform metadata, and trust list stay in
place. Patch keys in the lockfile and root manifest follow the new resolutions.

There is no aggregate hash to recalculate when dependencies change, and Nix can
reuse individual tarballs. Lockfile parsing uses pure Nix and needs no import
from derivation. The text lockfile must be available during evaluation; reading
it from an unbuilt derivation would require IFD.

Supported sources include npm registries, HTTP(S) tarballs, Git and GitHub,
local `.tgz`/`.tar.gz`/`.tar` archives, workspaces, `file:`/`link:` directories,
and `root:` self-references. Archive suffixes are case-insensitive. Aliases,
prereleases, catalogs, and dependency patches work with these sources.

Remote archives use lockfile integrity hashes; missing hashes can be supplied
through `fetcherOpts.<key>.hash`. Git uses the full locked commit, or an explicit
`fetcherOpts.<key>.rev`. Without a Git `hash`, Nix's `builtins.fetchGit` fetches at
evaluation time, as in `importNpmLock`. Supplying a Git `hash` selects Nixpkgs'
`fetchgit` so downloading happens during the build. Git transport options are
forwarded to the selected fetcher. GitHub rows use integrity-pinned codeload
archives, including legacy rows with a supplied hash.

The importer always uses a private writable cache; `makeCacheWritable` is
unnecessary. Local archives are read from the package source during installation,
including legacy rows without integrity. Binary `bun.lockb` requires conversion
with `bun install --save-text-lockfile --frozen-lockfile --lockfile-only`, or use
`fetchBunDeps`. See the [source inventory](./design.md#imported-source-types) for normalized
lockfile types and fetcher choices, and the [argument reference](./reference.md#importbunlock)
for configuration options.

### Configure importer registries and fetchers

Explicit tarball URLs in the lockfile take precedence over registry defaults.
For an empty URL, set `registry`/`scopedRegistries` to match upstream's registry
configuration. These arguments control Nix fetching; keep the project's
`.npmrc`/`bunfig.toml` for offline installation too.
`importBunLock` does not translate Bun's registry authentication to `fetchurl`.
Use `fetcherOpts` for Nix fetcher configuration, for example:

```nix
importBunLock {
  src = ./.;
  scopedRegistries."@myorg" = "https://registry.example.com";
  fetcherOpts."@myorg/package" = {
    url = "https://mirror.example.com/package-1.0.0.tgz";
  };
}
```

For private HTTP fetches, use `fetchurl`'s `netrcPhase`/`netrcImpureEnvVars` or other
builder-side credential configuration. Keep credential values out of Nix
expressions and the store. `bunDepsImpureEnvVars` configures `fetchBunDeps`
and does not affect this importer. Updating the imported lockfile replaces the
[aggregate-hash update workflow](#updating-packages).

## Private registries

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

[`nix-update`](https://github.com/Mic92/nix-update#usage) supports the dependency
cache through its custom dependency interface:

```sh
nix-update my-app --custom-dep bunDeps
nix-update --flake my-app --custom-dep bunDeps
# Recalculate hashes without changing the version:
nix-update my-app --version=skip --custom-dep bunDeps
```

Keep the literal `bunDepsHash` in the package's Nix expression.
`buildBunPackage` supplies a default `passthru.updateScript` using
`nix-update-script` with `--custom-dep bunDeps`. A caller-provided
`passthru.updateScript` takes precedence; set it to `null` to disable the default.
Other passthru attributes are preserved.

For a standalone `fetchBunDeps` derivation, `nix-update` recognizes its fixed-output
hash directly; no `--custom-dep` is needed:

```sh
nix-update my-deps --version=skip
```

This updates the literal `hash` in the fetcher's expression. When a package
supplies `bunDeps = fetchBunDeps { ... };` explicitly, `--custom-dep bunDeps` also
works, provided the hash literal is in that package's expression.

Automatic detection of a package's `bunDeps` without `--custom-dep` is not supported.
The lower-level `update-source-version` can recalculate the cache with
`--source-key=bunDeps --ignore-same-version` after updating the source. Neither
tool regenerates a Bun lockfile: upstream must commit it, or the package must
supply an updated lockfile explicitly.
