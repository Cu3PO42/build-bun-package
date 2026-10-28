# `buildBunPackage` - `buildNpmPackage`, but for Bun

`buildBunPackage` allows easily packaging Bun applications and scripts for Nix while sticking as close to the familiar `buildNpmPackage` as reasonably possible.
This implementation is enabled by new commands in [Bun 1.4.4](https://bun.com/blog/bun-v1.4.4#bun-pm-fetch).

This is an early implementation and comes with no guarantees nor any promise of long term maintenance.

## Limitations

Since the commands this relies on are only available starting with the newest version, we do not know if the format will stay stable with newer versions.
It is possible that the hash for the dependency FOD will change with Bun updates.

## Differences from `buildNpmPackage`

- Install scripts are opt-in: Set `bunRunScripts = true` to enable them, subject to Bun's trusted-dependency rules.
  There is no equivalent to `npmRebuildFlags` since a similar command does not exist for Bun and we work around shebang issues seperately.
- By default, Bun is used to execute any scripts. If you want to keep Node.js, add it as a `nativeBuildInput`.
- Executable project files, including local and workspace helpers, have their shebangs patched before installation.
- The default install phase creates executable wrappers using Bun. Set `bunRuntime = pkgs.nodejs;` to use Node.js instead.
- Workspace selection uses a directory instead of a package name: `bunWorkspace` is relative to `bunRoot`, i.e. the folder in which the lockfile is located.
  Each Bun hook enters its required directory and restores the previous working directory, so custom phases must enter `bunRoot` themselves when needed.
- Obviously all names and parameters use `bun` instead of `npm` :)


## AI Disclosure

This code was written primarily by LLMs (mostly GPT-6.1 Sol) under my direction.
However, all of the core code excluding tests was reviewed by me (a human).
Further reviews are in progress.

Beware that any content beyond this line is also at least partially written by AI.

-----------------------------

## Usage

### Package an application

Add this repository as a flake input named `nix-bun`. No overlay is required:

```nix
{
  packages.${system}.my-app = nix-bun.buildBunPackage.${system} {
    pname = "my-app";
    version = "1.0.0";
    src = ./.;
    bunDepsHash = nixpkgs.lib.fakeHash;
  };
}
```

Commit `package.json` and `bun.lock` (or `bun.lockb`). Build once with
`lib.fakeHash`, copy the `got: sha256-…` value from Nix's hash mismatch into
`bunDepsHash`, then build again. Repeat when dependencies change. To fetch only
the dependencies, run `nix build .#my-app.bunDeps`.

By default, the builder installs dependencies offline with lifecycle scripts
disabled, runs `bun run build`, and installs the package's publishable files
and production dependencies. Executables declared in `package.json` receive
Bun wrappers by default; set `bunRuntime = pkgs.nodejs;` for Node.js wrappers.
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
nix-bun.buildBunPackage.${system} {
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

Supported systems are `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`.
Cross compilation is not supported.

### Use an overlay or individual helpers

Apply `nix-bun.overlays.default` to use your own Nixpkgs package set and access
`pkgs.buildBunPackage`. The overlay replaces `pkgs.bun` only when this
repository's Bun is newer. Nixpkgs follows `nixos-unstable`, with its revision
recorded in `flake.lock`.

Without the overlay, top-level `fetchBunDeps`, `bunConfigHook`, `bunBuildHook`, `bunCheckHook`,
`bunInstallHook`, `bunNodeFallbackHook`, `bunNodeGypHook`, `bunNodeShim`,
`bunNodeGyp`, `bunNodeHeaders`, `bunHooks`, and `bun` are indexed by `${system}`.
The complete scope is available as `nix-bun.legacyPackages.${system}` and
supports `overrideScope`. The `packages` output exposes Bun, with no default
package.

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

The default runtime is Bun, including a fallback `node` command when none is
already on `PATH`. For scripts that need genuine Node.js, set
`nodejs = pkgs.nodejs-slim;` or add Node.js to `nativeBuildInputs`.
Select the runtime for installed application wrappers independently with
`bunRuntime = pkgs.nodejs-slim;`. It defaults to the selected `bun` package and
does not change the build or lifecycle runtime. To use Node.js for both:

```nix
nodejs = pkgs.nodejs-slim;
bunRuntime = pkgs.nodejs-slim;
```

Bun still fetches, installs, packs, and prunes dependencies, and the build hook
still invokes `bun run`. That command respects Node.js shebangs and `node`
commands using the build's `PATH`. Explicit `bun` commands and direct source-file
execution use Bun; `--bun` or `run.bun = true` in `bunfig.toml` can also force Bun
for scripts even when Node.js is available.

Prebuilt Node-API addons need no additional hook. To compile dependencies with
node-gyp, enable the optional toolchain:

```nix
nodeGyp = true;
bunRunScripts = true;
# Optional: run node-gyp with genuine Node.js and its matching headers.
nodejs = pkgs.nodejs;
```

Omit `nodejs` to run node-gyp with Bun and headers matching Bun's reported Node
compatibility version. Merely adding Node.js to `nativeBuildInputs` changes
`PATH`, but does not select node-gyp's runtime or headers. The toolchain supplies
Python, node-gyp, and local headers; stdenv supplies the compiler. Add
package-specific libraries through the usual inputs.

If only a specific setup command is needed, leave automatic scripts disabled
and run it after dependency shebangs have been patched:

```nix
nodeGyp = true;
postBunInstall = ''
  (
    cd node_modules/my-native-addon
    node-gyp rebuild
  )
'';
```

Supply any required root or workspace setup explicitly and in dependency order.
Packages that download prebuilt binaries can often use Nix-provided binaries
and upstream skip-download settings instead.

For a development shell with the native toolchain, use:

```nix
pkgs.mkShell {
  packages = [ pkgs.bunNodeGypHook ];
}
```

Run `bun install` normally, or `node-gyp rebuild` from a package with
`binding.gyp`. For genuine Node.js, use
`pkgs.bunNodeGypHook.override { nodejs = pkgs.nodejs; }`. For just Bun and the
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
bunDepsImpureEnvVars = [ "NPM_TOKEN" ];
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
exposed under `hydraJobs.${system}.integration`. Build one explicitly, or fetch
just its cache:

```sh
nix build .#hydraJobs.aarch64-darwin.integration.filen-cli
nix build .#hydraJobs.aarch64-darwin.integration.opencode.bunDeps
```

Substitute your system as needed. These builds are excluded from default flake
checks because they can be large. The [opencode example](./integration/opencode.nix)
shows custom workspace filtering, dependency patches, and installation;
[swagger-typescript-api](./integration/swagger-typescript-api.nix) uses the
default build and install hooks.

Run `nix flake check` on each supported system. `nix flake check --all-systems`
evaluates other systems but does not build their checks on the current host.
The checks include Nix formatting, ShellCheck, and GitHub Actions validation with
actionlint. Integration code is excluded from formatting checks. To run only
these checks, substitute your system in:

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

Pass a Bun version as an argument to select a release. The updater checks headers
even when Bun is already current; `bunNodeHeaders.updateScript` uses the same
updater. To update standalone node-gyp, change its dependency in
[`pkgs/node-gyp/source/package.json`](./pkgs/node-gyp/source/package.json),
regenerate the adjacent lockfile with Bun, and recalculate its `bunDepsHash`.

## Option reference

These are Nix derivation attributes. With the overlay, the builder is
`pkgs.buildBunPackage`; without it, use `nix-bun.buildBunPackage.${system}`.

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bun` | provided Bun | Bun package used for fetching and hooks (>= 1.4.4), and for executable wrappers by default |
| `bunRuntime` | selected `bun` | Runtime package for installed executable wrappers, e.g. `pkgs.nodejs-slim`; independent of the build/lifecycle runtime |
| `nodejs` | `null` | Optional genuine Node.js runtime for build/lifecycle compatibility and node-gyp; selects matching Node sources when `nodeGyp` is enabled |
| `nodeGyp` | `false` | Add standalone node-gyp, Python and local headers; run with Bun by default or the selected `nodejs` |
| `bunDepsHash` | `""` | Recursive SHA-256 SRI hash of the dependency cache |
| `bunDeps` | fetched from `src` | Reuse an existing dependency cache derivation/path |
| `bunDepsNativeBuildInputs` | `[]` | Tools/setup hooks explicitly needed for fetching or source preparation, e.g. Git or jq |
| `bunDepsImpureEnvVars` | `[]` | Names of builder environment variables to expose only to dependency fetching, e.g. registry tokens |
| `bunRoot` | `"."` | Lockfile/workspace root relative to the unpacked source root |
| `bunWorkspace` | `null` | Workspace directory relative to `bunRoot`; selects its build script, bins and manuals |
| `bunFetchFlags` | `[]` | Extra `bun pm fetch` arguments |
| `bunInstallFlags` | `[]` | Extra install arguments |
| `bunRunScripts` | `false` | Copy the cache, patch its shebangs, and permit Bun's trusted install scripts; otherwise append `--ignore-scripts` |
| `bunBuildScript` | `"build"` | Script passed to `bun run` |
| `bunCheckScript` | `null` | Package script to check with `bun run`; otherwise use `bun test`; requires `doCheck = true` |
| `bunFlags` | `[]` | Common Bun options before script names, applied to fetch, install, run, pack and prune; e.g. `[ "--silent" ]` |
| `bunBuildFlags` | `[]` | Arguments passed to the build script |
| `bunCheckFlags` | `[]` | Arguments passed to `bun test` or the selected check script |
| `dontBunBuild` | `false` | Skip the default build script |
| `dontBunCheck` | `false` | Disable the default check hook |
| `dontBunPrune` | `false` | Retain dev dependencies in the default installation |
| `bunPruneFlags` | `[]` | Extra arguments to `bun prune` |
| `bunPackFlags` | `[]` | Extra `bun pm pack` arguments |
| `preBunInstall`, `postBunInstall` | unset | Hooks around offline installation; the pre-hook runs before automatic cache shebang patching |
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
space-separated strings. The fetcher shell-escapes its Nix flag lists and
preserves spaces in either mode.

The config hook runs in `postPatchHooks`, even with a custom `configurePhase`.
The build, check, and install hooks supply phases only when no corresponding phase is
provided and their opt-out is unset. Each hook restores the working directory;
custom phases must enter `bunRoot` themselves and restore the directory before
the next phase. `preBunInstall` and `postBunInstall` run inside `bunRoot`.

Source selection, unpack, and patch settings are forwarded to the dependency
fetcher, but package `nativeBuildInputs`, `buildInputs`, and `env` are not.
If a shared `postPatch` needs jq, add it to both `nativeBuildInputs` and
`bunDepsNativeBuildInputs`; Git dependencies normally need Git only in
`bunDepsNativeBuildInputs`. For custom fetcher environment or phases, supply
`bunDeps = fetchBunDeps { ... };` explicitly. Direct fetcher calls use `hash`
instead of `bunDepsHash`, and `nativeBuildInputs` instead of
`bunDepsNativeBuildInputs`.

### Native toolchain overrides

The standalone helpers are `pkgs.bunNodeGyp` and `pkgs.bunNodeHeaders`.
Override `bunNodeGypHook`'s `bunNodeHeaders` or `python3` argument for another
header set or Python; custom headers must expose `version`. When using the
hook independently with another Bun, override its `bun` argument too.
`buildBunPackage` selects matching hooks automatically through its `bun` and
`nodejs` attributes. To select the installed runtime when using hooks directly,
use `(pkgs.bunHooks.override { bunRuntime = pkgs.nodejs; }).bunInstallHook`.

## Implementation notes and limitations

### Dependency cache design

The cache is a recursively hashed directory rather than a compressed archive,
avoiding an extra compression/extraction pass and allowing store deduplication.
Binary caches can compress NAR transfers independently. Bun handles lockfile
parsing and cache layout, avoiding a separate parser or npm-cache mapper.
Projects with only local dependencies can have an empty dependency cache.

Reused caches must have matching format metadata and a byte-for-byte identical
lockfile. Their output paths depend on the cache name and content hash, so a
Bun upgrade can reuse a cache when its contents stay unchanged. Regenerate the
hash when those contents change. Changes to this project's cache format require
updating the format marker and expected hashes.

Fetching covers all platforms in the lockfile, while offline installation
selects the build host's dependencies. This lets workspaces and platforms share
a cache, but can be expensive: workspace selection and install filters do not
reduce downloads. There is no hash-free `importBunLock` helper; individual
integrity-based fetches would need separate handling of JSONC, registries, Git
sources, and Bun's internal cache naming rules.

The fetcher's source-preparation allowlist prevents package phases and setup
hooks from running during fetching or introducing dependency cycles.

### Writable caches, scripts, and sandboxing

The store cache is read directly by default. `makeCacheWritable` uses a private
temporary copy, leaving the shared cache unchanged. `bunRunScripts` also enables
this copy so dependency shebangs can be patched before scripts execute;
`preBunInstall` runs before that patching. Setting `makeCacheWritable` alone
leaves scripts disabled.

Executable project files are also patched before installation, including
workspace and local `file:` dependency helpers. This happens after
`preBunInstall`, so helpers created by that hook are covered too.
Cache edits can interfere with dependency patches that expect original file
contents.

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
after the build. An explicitly supplied Node.js on `PATH` takes precedence.

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

[`tests/`](./tests) covers caches, lifecycle scripts, native builds with Bun and
Node.js, hooks, flag handling, workspaces with hoisted and isolated linkers,
pruning, and installed runtime behavior. Fresh-fetch checks use
`testers.invalidateFetcherByDrvHash` so changed fetcher inputs cannot pass by
reusing a cached fixed-output result.

Source coverage includes text/JSONC and binary lockfiles, catalogs, duplicate
Git aliases, local `file:` and `link:` dependencies, foreign optional dependencies,
a public GitHub dependency, an HTTP tarball, and a non-default registry. Workspace
checks also cover consuming a sibling whose CLI has not been built. The
authenticated mock registry checks credential rejection, token leakage, and offline
installation after removing credentials and stopping the server. It does not
configure daemon credentials.
Other Git protocols and private Git authentication remain untested.

For upstream context, see the
[Bun 1.4.4 release notes](https://bun.com/blog/bun-v1.4.4#bun-pm-fetch) and
[Nixpkgs JavaScript documentation](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md).
