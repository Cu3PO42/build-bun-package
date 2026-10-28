<h1 style="text-align: center;">Bunniex</h1>
<p style="text-align: center">
<code>buildNpmPackage</code>, but for Bun!
</p>

![A bunny holding a package with a Nix logo on it.](./logo.png)

`buildBunPackage` allows easily packaging Bun applications and scripts for Nix while sticking as close to the familiar `buildNpmPackage` as reasonably possible.
This implementation is enabled by new commands in [Bun 1.4.4](https://bun.com/blog/bun-v1.4.4#bun-pm-fetch).

## Status

`buildBunPackage` is feature-complete and has been used to package real world applications.
You can probably use it for your package and encounter few issues.
`importBunLock` is currently experimental; it also works in limited test settings, but I have much lower confidence in it.

The project as a whole is in early stages and the public interface is not yet finalized, so expect breaking changes for now when updating.

This project is designed such that it should be able to be upstreamed to nixpkgs, but I currently make no promises of long term maintenance.

## Limitations

Since the commands this relies on are only available starting with Bun 1.4.4, which is at the time of writing the newest version, we do not know if the format will stay stable with newer versions.
It is possible that the hash for the dependency FOD will change with Bun updates.

## Differences from `buildNpmPackage`

- Install scripts are opt-in: Set `bunRunScripts = true` to enable them, subject to Bun's trusted-dependency rules.
  There is no equivalent to `npmRebuildFlags`: Bun runs scripts through a forced install after dependency preparation.
- By default, Bun executes scripts. Set `runtime = pkgs.nodejs;` to use Node.js throughout, or `buildRuntime` to select it only for build scripts.
- Executable project files, including local and workspace helpers, have their shebangs patched before installation.
- The default install phase creates executable wrappers using Bun. Set `runtime = pkgs.nodejs;` to use Node.js instead.
- Workspace selection uses a directory instead of a package name: `bunWorkspace` is relative to `bunRoot`, i.e. the folder in which the lockfile is located.
  Each Bun hook enters its required directory and restores the previous working directory, so custom phases must enter `bunRoot` themselves when needed.
- Obviously all names and parameters use `bun` instead of `npm` :)


## AI Disclosure

This code was written primarily by LLMs (mostly GPT-6.1 Sol) under my direction.
The end goal is to have all code (except possibly tests) reviewed by me (a human).
This is already true for the core logic and as of a prior state it was true for all code, but additional work has introduced new, not fully reviewed code.
I aim to review and clean this up soon.

Beware that any content beyond this line is also at least partially written by AI.

-----------------------------

## Usage

### Package an application

Add this repository as a flake input named `nix-bun`. No overlay is required:

```nix
{
  packages.${system}.my-app = nix-bun.legacyPackages.${system}.buildBunPackage {
    pname = "my-app";
    version = "1.0.0";
    src = ./.;
    bunDepsHash = nixpkgs.lib.fakeHash;
  };
}
```

Commit `package.json` and a supported lockfile. Build once with
`lib.fakeHash`, copy the `got: sha256-…` value from Nix's hash mismatch into
`bunDepsHash`, then build again. Repeat when dependencies change. To fetch only
the dependencies, run `nix build .#my-app.bunDeps`.

`fetchBunDeps` delegates lockfile parsing to Bun, so the approach can
fundamentally work with any lockfile format supported by the selected Bun
version: text `bun.lock`, binary `bun.lockb`, and other package managers'
lockfiles through [Bun's upstream migration support](https://bun.com/docs/pm/lockfile#automatic-lockfile-migration),
including supported npm, Yarn, and pnpm formats. This also applies when
`buildBunPackage` calls `fetchBunDeps` implicitly through `bunDepsHash`.
When no `bun.lock` or `bun.lockb` is present, `fetchBunDeps` runs `bun pm migrate`
before fetching. Supported foreign lockfiles are `npm-shrinkwrap.json`,
`package-lock.json`, `yarn.lock`, and `pnpm-lock.yaml`; the selected Bun version
determines which versions and features it can migrate. Bun handles selection
when several lockfiles are present. Unsupported inputs fail without falling
back to an unlocked install.

The cache contains the generated Bun lockfile and any manifest edits made by
migration. Migration can consult the registry for missing metadata; its temporary
registry cache is excluded from the fixed-output result. The separate
`bunHooks.bunMigrateHook`, propagated by the config hook, applies the saved result
after project patches and before offline installation. Upstream does not need to
commit a generated Bun lockfile. Manifest edits are merged by field, preserving
unrelated build-side changes such as scripts and descriptions. Conflicting edits
fail with the affected field; dependency changes still require a matching cache
and must pass Bun's frozen-lockfile validation.

By default, the builder installs dependencies offline with lifecycle scripts
disabled, runs `bun run build`, and installs the package's publishable files
and production dependencies. Executables declared in `package.json` receive
Bun wrappers by default; set `runtime = pkgs.nodejs;` for Node.js wrappers.
Declared manual pages are installed too. Set `dontBunBuild = true`
for a package without a build script. Set `dontBunPrune = true` to retain dev
dependencies in the default installation.

Set `doCheck = true` to run `bun test` before installation and pruning. For a
package.json test script or another test runner, set `bunCheckScript = "test";`
to run `bun run test` instead. `bunCheckFlags` supplies test arguments. Checks
use the selected `bunWorkspace`, and respect `preCheck`, `postCheck`, and a
custom `checkPhase`. Set `dontBunCheck = true` to disable the default check hook.

For a bundled executable or static website, override `installPhase` to install
only the build output:

```nix
nix-bun.legacyPackages.${system}.buildBunPackage {
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

The builder enables `__structuredAttrs` by default. In custom shell phases,
list attributes are Bash arrays; use `env` for values that child processes need
in their environment. Set `__structuredAttrs = false;` for compatibility with
phases that require the older attribute representation.

Supported systems are `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`.
Cross compilation is not supported.

### Import a lockfile without `bunDepsHash`

`importBunLock` is an alternative to `fetchBunDeps` that fetches each tarball
using the integrity hash already recorded in a text `bun.lock`. It requires
that text-based Bun lockfile and cannot directly import binary `bun.lockb` or
another package manager's lockfile. Convert those with Bun first.

```nix
nix-bun.legacyPackages.${system}.buildBunPackage {
  pname = "my-app";
  version = "1.0.0";
  src = ./.;
  bunDeps = nix-bun.legacyPackages.${system}.importBunLock { src = ./.; };
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
`fetchBunDeps`. See the [source-type analysis](./docs/import-bun-lock.md) for Bun's
normalized lockfile types, fetcher choices, and direct-install tradeoffs.

The importer accepts these arguments:

| Argument | Default | Purpose |
| --- | --- | --- |
| `src` | required | Source directory; used to locate the default lockfile |
| `bunRoot` | `"."` | Project directory relative to `src`, matching the builder's `bunRoot` |
| `lockFile` | `src + "/${bunRoot}/bun.lock"` | Text lockfile to import; must match the package build's lockfile byte for byte |
| `name` | `"imported-bun-deps"` | Source-bundle derivation name |
| `registry` | `"https://registry.npmjs.org"` | Registry for packages whose lockfile URL is empty |
| `scopedRegistries` | `{}` | Registry URLs keyed by scope, e.g. `"@myorg"` |
| `fetcherOpts` | `{}` | Per-package options for `fetchurl`, `fetchgit`, or `builtins.fetchGit`, keyed by the exact key in `bun.lock`'s `packages` object |

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
aggregate-hash update workflow described below.

### Use an overlay or individual helpers

Apply `nix-bun.overlays.default` to use your own Nixpkgs package set and access
`pkgs.buildBunPackage`. The overlay replaces `pkgs.bun` only when this
repository's Bun is newer. Nixpkgs follows `nixos-unstable`, with its revision
recorded in `flake.lock`.

Without the overlay, `nix-bun.legacyPackages.${system}` exposes `bun`,
`buildBunPackage`, `fetchBunDeps`, `importBunLock`, `bunNodeGyp`, `bunNodeHeaders`,
and the grouped `bunHooks`. This set contains only this project's helpers and
tools. Customize the package set through overlays, or use individual helpers'
`override` and packages' `overrideAttrs` methods.

The `packages.${system}` output exposes `bun`, `bunNodeGyp`, `bunNodeHeaders`, and
real-world examples named `example-<name>`, with no default package.

To use the hooks with `stdenv.mkDerivation`, add the desired hooks from
`pkgs.bunHooks` to `nativeBuildInputs` and supply `bunDeps`. Each hook propagates
the Bun package it was configured with.

### Workspaces and nested projects

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

### Lifecycle scripts and native dependencies

Enable install scripts with `bunRunScripts = true`. Bun's dependency trust rules
still apply, and an explicit `--ignore-scripts` in `bunInstallFlags` or upstream
configuration can still disable scripts. This option controls installation;
the build hook runs independently, and packing always skips scripts.

The default runtime is the selected `bun` package. Set `runtime` to Node.js to
use it for installed wrappers, dependency Node shebangs, and `node` commands
during installation, builds, and checks:

```nix
{
  runtime = pkgs.nodejs-slim;
}
```

`buildRuntime` defaults to `runtime`. Override it when build tools need a
different runtime from the installed application:

```nix
{
  # The installed application runs with Bun; build tools use Node.js.
  buildRuntime = pkgs.nodejs-slim;
}
```

The hooks supply a `node` command for `buildRuntime`, taking precedence over
incidental Node.js inputs. Installed dependency Node shebangs are retargeted to
`runtime`, so a build-only Node.js reference does not remain in those scripts.
Installed wrappers also supply that runtime as `node` for child processes.

Bun still fetches, installs, packs, and prunes dependencies, and the build hook
still invokes `bun run`. That command respects Node.js shebangs and `node`
commands using the build's `PATH`. Explicit `bun` commands and direct source-file
execution use Bun; `--bun` or `run.bun = true` in `bunfig.toml` can also force Bun
for scripts even when Node.js is available.

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

node-gyp runs with `buildRuntime` and compiles against headers for `runtime`.
For Bun, the headers match its reported Node.js compatibility version; for
Node.js, they come from the selected Node.js package. Node-API addons can work
across these runtimes, but matching Node.js versions does not make V8-specific
addons compatible with Bun. The toolchain supplies Python, node-gyp, and local
headers; stdenv supplies the compiler. Add package-specific libraries through
the usual inputs.

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
the cache are left untouched. Installed outputs are patched again before
stdenv audits RPATHs, so bundled libraries resolve from the final output rather
than a temporary build/cache directory. `dontAutoPatchelf = true` disables this
behavior and the standard autoPatchelf output fixup.

For a development shell with the native toolchain, use:

```nix
pkgs.mkShell {
  packages = [ pkgs.bunHooks.bunNodeGypHook ];
}
```

Run `bun install` normally, or `node-gyp rebuild` from a package with
`binding.gyp`. For genuine Node.js, use
`(pkgs.bunHooks.override { runtime = pkgs.nodejs; }).bunNodeGypHook`. For just Bun and the
fallback `node` command, use `pkgs.bunHooks.bunNodeFallbackHook` instead.

### Private registries

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

### Update packages

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

Automatic dependency detection without `--custom-dep` is not supported.
The lower-level `update-source-version` can recalculate the cache with
`--source-key=bunDeps --ignore-same-version` after updating the source. Neither
tool regenerates a Bun lockfile: upstream must commit it, or the package must
supply an updated lockfile explicitly.

### Build examples and run checks

Real-world package examples live in [`integration/`](./integration) and are
exposed under `packages.${system}` with an `example-` prefix. Build one explicitly, or fetch
just its cache:

```sh
nix build .#example-filen-cli
nix build .#example-opencode.bunDeps
```

Nix selects the current system automatically. These builds are excluded from
default flake checks because they can be large. The [opencode example](./integration/opencode.nix)
shows custom workspace filtering, dependency patches, and installation;
[swagger-typescript-api](./integration/swagger-typescript-api.nix) uses the
default build and install hooks.

Run `nix fmt` to format Nix with nixfmt, shell with shfmt, and
JavaScript/TypeScript with Bun. JavaScript/TypeScript test fixtures are
excluded to preserve their contents and hashes.
The shared configuration in [`treefmt.nix`](./treefmt.nix) applies to both
formatting and formatting checks. Run `nix fmt -- --ci` to format and fail if any
files change.

Run `nix flake check` on each supported system. `nix flake check --all-systems`
evaluates other systems but does not build their checks on the current host.
The checks include Nix formatting, ShellCheck, and GitHub Actions validation with
actionlint. To run only these checks, substitute your system in:

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

### Update the bundled tools

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

## Option reference

These are Nix derivation attributes. With the overlay, the builder is
`pkgs.buildBunPackage`; without it, use `nix-bun.legacyPackages.${system}.buildBunPackage`.

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bun` | provided Bun | Bun package used for fetching and hooks (>= 1.4.4), and for executable wrappers by default |
| `runtime` | selected `bun` | Runtime for installed wrappers and dependency Node shebangs; selects native addon target headers |
| `buildRuntime` | selected `runtime` | Runtime for Node shebangs and `node` commands during installation/build/check, and for node-gyp itself |
| `nodeGyp` | `false` | Add standalone node-gyp, Python and headers for the installed runtime |
| `bunDepsHash` | `""` | Recursive SHA-256 SRI hash of the dependency cache |
| `bunDeps` | fetched from `src` | Reuse an existing dependency cache derivation/path |
| `bunDepsNativeBuildInputs` | `[]` | Tools/setup hooks explicitly needed for fetching or source preparation, e.g. Git or jq |
| `bunDepsImpureEnvVars` | `[]` | Names of builder environment variables to expose only to dependency fetching, e.g. registry tokens |
| `bunRoot` | `"."` | Lockfile/workspace root relative to the unpacked source root |
| `bunWorkspace` | `null` | Workspace directory relative to `bunRoot`; selects its build script, bins and manuals |
| `bunFetchFlags` | `[]` | Extra `bun pm fetch` arguments |
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
| `preBunInstall`, `postBunInstall` | unset | Hooks around offline installation; the pre-hook runs before automatic source/cache preparation |
| `preBunInstallScripts` | unset | With `bunRunScripts`, runs after the initial script-free install and automatic patching, before the forced reinstall; `bunPreparedCachePackages` contains the selected writable cache directories |
| `makeCacheWritable` | `false` | Copy the dependency cache to writable temporary storage; implied by `bunRunScripts` |
| `makeWrapperArgs` | `[]` | Additional arguments for each executable wrapper |
| `dontBunInstall` | `false` | Disable the default install phase |
| `bunConfigHook`, `bunBuildHook`, `bunCheckHook`, `bunInstallHook` | default hooks | Replace individual setup hooks |

### Flags and custom phases

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
`bunDeps` separately, keep the foreign lockfiles, `pnpm-workspace.yaml`, and
`.yarnrc.yml` consistent with the cached migration inputs.

### Native toolchain overrides

The standalone helpers are `pkgs.bunNodeGyp` and `pkgs.bunNodeHeaders`.
Override `bunHooks`' `bunNodeHeaders` or `python3` argument for another
header set or Python; custom headers must expose `version`. When using the
hooks independently with another Bun, override their `bun` argument too.
`buildBunPackage` selects matching hooks automatically through its `bun`,
`runtime`, and `buildRuntime` attributes. Direct hook users can override these
arguments on `bunHooks`, for example
`(pkgs.bunHooks.override { runtime = pkgs.nodejs; }).bunInstallHook`.

## Implementation notes and limitations

### Dependency cache design

The cache is a recursively hashed directory rather than a compressed archive,
avoiding an extra compression/extraction pass and allowing store deduplication.
Binary caches can compress NAR transfers independently. For `fetchBunDeps`, Bun
handles lockfile parsing and cache layout, avoiding a separate parser or
npm-cache mapper.
Projects with only local dependencies can have an empty dependency cache.

Reused caches must have matching format metadata and a byte-for-byte identical
lockfile. Fixed-output cache paths depend on the cache name and content hash, so a
Bun upgrade can reuse a cache when its contents stay unchanged. Regenerate the
hash when those contents change. Changes to this project's cache format require
updating the format marker and expected hashes.
For migrated projects, metadata additionally records the foreign lockfiles,
workspace/Yarn migration configuration, and manifest transformations. The
migration hook validates those inputs and applies only migration's field edits;
the config hook then checks the generated Bun lockfile as usual.

Fetching covers all platforms in the lockfile, while offline installation
selects the build host's dependencies. This lets workspaces and platforms share
a cache, but can be expensive: workspace selection and install filters do not
reduce downloads. `importBunLock` also fetches the complete locked archive set,
but extracts only packages selected by installation on the build host. Its
source bundle contains archive/checkout links and original-lockfile metadata,
without Bun, a source-tree copy, or an extraction step. The config hook changes fetched
resolutions into local tarballs in the build tree, and Bun installs them directly
into a private cache and `node_modules`. Git checkouts retain their Git
resolutions and are copied into native Git cache entries; this avoids rewriting
Git identities or manufacturing new archive hashes. The importer needs neither a
loopback server nor Darwin networking permissions. The existing hooks still own
lifecycle preparation, patching, linking, and pruning.

The rewritten build-tree lockfile and patch keys contain store paths. They are
kept through build and prune so later Bun commands see consistent resolutions;
package manifests retain their original dependency constraints. A package that
explicitly publishes its lockfile or patched-dependency metadata can therefore
retain archive store references. Use `fetchBunDeps` when the original source
identities must be preserved. `preBunInstall` runs before importer archives are
extracted, so it can prepare project files but cannot assume a populated cache.

The fetcher's source-preparation allowlist prevents package phases and setup
hooks from running during fetching or introducing dependency cycles.

### Writable caches, scripts, and sandboxing

The store cache is read directly by default. `makeCacheWritable` uses a private
temporary copy, leaving the shared cache unchanged. `bunRunScripts` also enables
this copy. Setting `makeCacheWritable` alone leaves scripts disabled.
The config hook propagates Nixpkgs' `writableTmpDirAsHomeHook` to provide a
writable temporary home when needed, preserving an already writable `HOME`.

With scripts enabled, an initial offline install skips scripts and uses Bun's
hoisted linker and symlink backend. The final install honors the selected
linker. This lets Bun apply `patchedDependencies` to original package
contents first. The symlinked manifests identify the selected cache packages,
whose shebangs can then be patched without modifying the original inputs to
dependency patches. When `autoPatchelfHook` is supplied, their ELF binaries are
prepared at the same point. A forced offline install copies those prepared
packages and runs trusted scripts. The forced reinstall is necessary: an ordinary second
install skips dependency scripts. No staging-cache links are shipped.

`preBunInstallScripts` runs after that initial install and automatic shebang/ELF
patching, before the forced reinstall. It runs only with `bunRunScripts = true`.
The Bash array `bunPreparedCachePackages` contains the selected writable cache
directories. Apply custom dependency edits there: replacing symlinked files in
the staging `node_modules` tree can leave the cache unchanged, so those edits
would be lost during the reinstall. Prepare any new executable files added by
the hook as needed. `postBunInstall` runs after the final install and its fixups.

The separation of installation and script execution is inspired by
[bun2nix's lifecycle phases](https://github.com/nix-community/bun2nix/blob/0f2a1f0b6f42cebe3b149bf62d38754c5e0e9729/nix/mk-derivation/hook.sh)
and Nixpkgs' `npm ci --ignore-scripts` followed by `npm rebuild`. Bun has no
equivalent rebuild command, so preparation and the final copy install remain
separate Bun installs.

Executable project files are also patched before installation, including
workspace and local `file:` dependency helpers. This happens after
`preBunInstall`, so helpers created by that hook are covered too.
Executable `bun.lockb` files are excluded: changing their shebang would corrupt
the binary lockfile's offsets.
Custom cache edits in `preBunInstall` can still interfere with dependency
patches that expect original file contents.

Build with Nix sandboxing enabled to enforce network isolation for arbitrary
lifecycle and build scripts. Bun's `--offline` applies to package installation;
scripts can attempt their own downloads. Supply any extra assets separately.

### Installed package layout

Bun's publish-file selection (`files`, ignore rules, and package metadata)
determines installed package files. The installer uses an archive because Bun
has no equivalent of npm's machine-readable `pack --json` file list. Dependencies
come from the pruned installed tree rather than the archive, preserving
unbundled dependencies and lifecycle-script changes as well as bundled ones.

The directory structure beneath `$out/lib/node_modules/<root-package-name>`
preserves workspace and local-package links, including hoisted dependencies and
the isolated linker's shared `.bun` store. Flattening a workspace or copying
only the selected member would leave broken links after removing the source.
This is not a minimal dependency closure: other installed workspaces remain.
Use a custom `installPhase` for bundles or selected artifacts.

Local package links outside `bunRoot` are rejected. Packages selected for packing
need a name and version; a workspace root without a version acts as a container
with only its manifest and dependencies installed.

### Runtime and native compatibility

The default hooks add no Node.js, npm, Python, node-gyp, or headers. The fallback
`node` is a permanent store symlink to Bun, so patched shebangs remain usable
after the build. The selected `buildRuntime` supplies the `node` command.
Explicit Bun commands continue to use Bun.

The optional node-gyp toolchain uses pinned tools and local headers to avoid
automatic downloads. It sets `npm_config_node_gyp`, `npm_config_nodedir`,
`npm_config_target`, and `npm_config_python`; Bun's lifecycle trust rules still
apply. Darwin uses cctools and Nixpkgs' deterministic Xcode-version fallback.
Bun supports Node-API addons; V8-specific addons may require changes.

Standalone node-gyp is itself built with `buildBunPackage` and a committed
lockfile, keeping dependency resolution in Bun instead of maintaining a custom
archive list and installer. Its headers match the pinned Bun's reported
`process.versions.node`, independently of a Node.js runtime package; a flake
check verifies the versions match.

### Verification boundaries

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

For upstream context, see the
[Bun 1.4.4 release notes](https://bun.com/blog/bun-v1.4.4#bun-pm-fetch) and
[Nixpkgs JavaScript documentation](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md).
