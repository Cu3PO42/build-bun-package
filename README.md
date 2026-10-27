# nix-bun

`buildBunPackage` builds Bun projects using a fixed-output dependency fetch followed
by an offline install. Includes Bun 1.4.4 and a nixpkgs overlay.
See [the implementation review](./REVIEW.md) for the Nixpkgs comparison,
workspace/native-module validation, and remaining limitations.

```sh
nix build path:.#checks.aarch64-darwin.example  # or your supported system
./result/bin/bun-example 3   # odd
nix flake check path:.
```

## Use in a flake

Add this repository as an input named `nix-bun`. The helpers are available
without applying an overlay:

```nix
let
  bunPkgs = nix-bun.legacyPackages.${system};
in {
  packages.${system}.my-app = bunPkgs.buildBunPackage {
    pname = "my-app";
    version = "1.0.0";
    src = ./.;
    bunDepsHash = nixpkgs.lib.fakeHash;
  };
}
```

Top-level `fetchBunDeps`, `bunConfigHook`, `bunBuildHook`, `bunInstallHook`,
`bunNodeFallbackHook`, `bunNodeGypHook`, `bunNodeShim`, `bunNodeGyp`,
`bunNodeHeaders`, `bunHooks`, and `bun` are also indexed by `${system}`.
For example, use `nix-bun.bunNodeGypHook.${system}` in a development shell.
The complete scope remains available as `nix-bun.legacyPackages.${system}`
and supports `overrideScope` for customization. To use your own Nixpkgs package
set, apply `nix-bun.overlays.default`.

Commit `package.json` and `bun.lock` (or `bun.lockb`). Build once with
`lib.fakeHash`, copy the `got: sha256-…` value from Nix's hash mismatch into
`bunDepsHash`, then build again. Repeat when dependencies change. To fetch just
an application's dependencies, use `nix build .#my-app.bunDeps`.

The optional overlay exposes the same helpers and replaces `pkgs.bun` only
when the provided Bun is newer. An equal or newer Nixpkgs Bun is retained. Supported systems are `aarch64-darwin`,
`aarch64-linux`, and `x86_64-linux`. `packages` exposes Bun and the real-world
integration packages; there is no default package. The synthetic example is
available as `checks.${system}.example`. Nixpkgs follows `nixos-unstable`, with
the exact revision recorded only in `flake.lock`.

## Build and installation

1. `fetchBunDeps` unpacks and patches the source and runs `bun pm fetch --frozen-lockfile`
   for all platforms directly into a recursively hashed cache. The cache contains
   `.nix-bun/format-version` and a byte-for-byte copy of the selected lockfile.
   No dependency lifecycle scripts run during fetching.
2. The config hook validates the cache and lockfile, then runs `bun install
   --offline --frozen-lockfile --backend copyfile`. Bun runs lifecycle scripts
   according to its trust rules during this install. Installed dependencies are
   made writable and their shebangs patched. `BUN_INSTALL_GLOBAL_STORE=0` keeps
   dependencies in the package tree.
3. The build hook runs `bun run build` by default.
4. The install hook uses `bun pm pack --ignore-scripts` to select package files,
   excludes packed dependencies, and installs pruned `node_modules` at their
   project-relative paths.
   Bins receive Bun wrappers and declared manual pages are installed.

A reused `bunDeps` cache must contain matching format metadata and the same
lockfile. Cache output paths depend on the cache name and content hash, so a Bun upgrade
can reuse an existing cache. Regenerate the hash only when the cache contents
change. Fresh-fetch checks deliberately invalidate test outputs when fetcher
inputs change, independently of this reuse policy.

By default Bun reads the store cache directly. Set `makeCacheWritable = true`
when dependency patches or lifecycle scripts modify existing package files or
when Bun needs to write to the cache. Some lifecycle-enabled installs require
cache writes even when installed files use `copyfile`. This option copies the
cache to `$TMPDIR` first.

The archive applies Bun’s publish-file selection (`files`, ignore rules and
package metadata) to the current package. It does not pack the dependency graph,
but it can include packages declared in `bundledDependencies`. Extraction excludes
all `node_modules` paths because the complete pruned dependency tree is copied
separately, including unbundled dependencies and changes made by lifecycle scripts.
Bun has no equivalent of npm's machine-readable `pack --json` file list, so the
installer extracts an archive instead.

`bunInstallPackageTree` walks linked local packages and preserves their paths
relative to `bunRoot`. It packs each local package once, copies its own
`node_modules`, and rewrites dependency links into the installed tree. Workspaces
and `file:` packages can link outside the selected member; isolated linking also
uses a shared `.bun` store. Flattening or copying just the member would leave
broken links after the source directory is removed. This traversal handles those
layouts; custom artifact-only installers can skip it.

The default installer prunes dev dependencies after building and testing. Set
`dontBunPrune = true` to retain them. For a bundled executable or static website,
override `installPhase` to install only the build output:

```nix
pkgs.buildBunPackage {
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

## Real-world integration: opencode

`nix build .#opencode` builds opencode 2.1.1 with `buildBunPackage`.
The [derivation](./tests/opencode.nix) follows the package in the pinned nixpkgs:
source, patches, build commands, executable wrapping, JSON schemas, shell
completions, and the installed version check are retained. The Photon dependency
patch needs a whitespace-only correction to its context lines for Bun 1.4.4.

The custom fixed-output `node_modules` derivation is replaced by `bunDepsHash`
and an offline install. Installation keeps nixpkgs' root, CLI, desktop, and app
workspace filters and skips lifecycle scripts. The upstream dependency-link
normalization scripts run in `postBunInstall`; `makeCacheWritable` allows Bun to
apply dependency patches. The cache fetches all platforms, while the offline
install selects the build host's native dependencies. Unlike nixpkgs' filtered
`node_modules` fetcher, `bun pm fetch` downloads the whole lockfile; this cache
is about 8.2 GB unpacked.

This is an opt-in integration test and is **excluded from the default flake
checks** because it is substantially larger than the synthetic fixtures.
`nix build .#opencode` includes the web UI, schemas, shell completions, and
installed version check. To fetch only its cache, run
`nix build .#opencode.bunDeps`.

## Updating packages

[`nix-update`](https://github.com/Mic92/nix-update#usage) can update source and
dependency hashes using its existing custom dependency interface:

```sh
nix-update my-app --custom-dep bunDeps
# For a package exposed through a flake:
nix-update --flake my-app --custom-dep bunDeps
# Recalculate hashes without changing the version:
nix-update my-app --version=skip --custom-dep bunDeps
```

Keep the literal `bunDepsHash` in the package's Nix expression. The updater
builds `bunDeps` with a blank output hash and replaces the old hash with the
reported hash. This path was verified with nix-update 1.16.0 against a temporary
package with an intentionally wrong hash. No separate Bun prefetch tool is
needed. `buildBunPackage` automatically supplies `passthru.updateScript` using
`nix-update-script { extraArgs = [ "--custom-dep" "bunDeps" ]; }`.
A caller-provided `passthru.updateScript` takes precedence; set it to `null`
to disable the default. Other passthru attributes are preserved.

Automatic detection without that flag would require adding `bunDeps.outputHash`
to nix-update's evaluation and dependency-hash updater registry. The lower-level
`update-source-version` can recalculate this FOD with `--source-key=bunDeps`
and `--ignore-same-version` after updating the source. Neither tool regenerates a Bun lockfile; upstream
must commit it, or the package must supply an updated lockfile explicitly.

## Private registries

Bun reads registry configuration from the source's `bunfig.toml` or `.npmrc`.
Keep credentials as environment references, for example:

```toml
[install.scopes]
myorg = { url = "https://registry.example.com/", token = "$NPM_TOKEN" }
```

Then opt only the required variable names into dependency fetching:

```nix
bunDepsImpureEnvVars = [ "NPM_TOKEN" ];
```

For direct `fetchBunDeps` calls use `impureEnvVars = [ "NPM_TOKEN" ];`.
The existing proxy variables are retained. The ordinary offline package build
does not receive these credentials. Never embed token values in Nix `env`,
flags, source URLs, or committed configuration: those enter the Nix store.
Private dependency contents themselves also enter the store/cache.

Nix must have the values in the **builder process's environment**. With a
multi-user installation that means the daemon environment, including on remote
builders; exporting a token in the client shell or using `--impure` is not
enough. Nix also offers `impure-env` for trusted users when
`configurable-impure-env` is enabled on the daemon. See the
[Nix documentation](https://nix.dev/manual/nix/2.31/language/advanced-attributes#adv-attr-impureEnvVars).
The mock-registry test supplies public test credentials internally; it does not
configure daemon credentials. Keep the same registry configuration for offline
installation because Bun's cache keys depend on the registry.

## Regular integration: swagger-typescript-api

`nix build .#swagger-typescript-api` builds version 13.13.0 from the same source
as the pinned nixpkgs package. It is also included in the default flake checks.
The derivation uses the default build and install hooks: `bun run build`,
production pruning, package-file selection (including templates), and a Bun
wrapper for `swagger-typescript-api`. Node.js is not an input.
The installed CLI is checked with `--version`, `--help`, and `generate --help`;
these smoke checks do not generate a client or access the network. The
all-platform dependency cache is approximately 1.54 GiB (NAR size).

## Options

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bun` | provided Bun | Bun package used for fetching, hooks, and executable wrappers (>= 1.4.4) |
| `nodejs` | `null` | Optional genuine Node.js runtime for build/lifecycle compatibility and node-gyp; selects matching Node sources when `nodeGyp` is enabled |
| `nodeGyp` | `false` | Add standalone node-gyp, Python and local headers; run with Bun by default or the selected `nodejs` |
| `bunDepsHash` | `""` | Recursive SHA-256 SRI hash of the dependency cache |
| `bunDeps` | fetched from `src` | Reuse an existing dependency cache derivation/path |
| `bunDepsNativeBuildInputs` | `[]` | Tools/setup hooks explicitly needed for fetching or source preparation, e.g. Git or jq |
| `bunDepsImpureEnvVars` | `[]` | Names of builder environment variables to expose only to dependency fetching, e.g. registry tokens |
| `bunRoot` | `"."` | Lockfile/workspace root relative to the unpacked source root |
| `bunWorkspace` | `null` | Workspace directory relative to `bunRoot`; selects its build script, bins and manuals |
| `bunFetchFlags` | `[]` | Extra `bun pm fetch` arguments |
| `bunInstallFlags` | `[]` | Extra install arguments, e.g. `[ "--ignore-scripts" ]` |
| `bunBuildScript` | `"build"` | Script passed to `bun run` |
| `bunFlags` | `[]` | Common Bun options before script names, applied to fetch, install, run, pack and prune; e.g. `[ "--silent" ]` |
| `bunBuildFlags` | `[]` | Arguments passed to the build script |
| `dontBunBuild` | `false` | Skip the default build script |
| `dontBunPrune` | `false` | Retain dev dependencies in the default installation |
| `bunPruneFlags` | `[]` | Extra arguments to `bun prune` |
| `bunPackFlags` | `[]` | Extra `bun pm pack` arguments |
| `preBunInstall`, `postBunInstall` | unset | Hooks around offline installation; the pre-hook can patch a writable cache before lifecycle scripts |
| `makeCacheWritable` | `false` | Copy the dependency cache to writable temporary storage |
| `makeWrapperArgs` | `[]` | Additional arguments for each executable wrapper |
| `dontBunInstall` | `false` | Disable the default install phase |
| `bunConfigHook`, `bunBuildHook`, `bunInstallHook` | default hooks | Replace individual setup hooks |

The hooks are also available independently as `pkgs.bunHooks.bunConfigHook`,
`bunBuildHook`, and `bunInstallHook`. Add the desired hooks to
`nativeBuildInputs` and provide `bunDeps` when using `stdenv.mkDerivation`.
Each hook propagates the Bun package it was configured with.
The config hook runs in `postPatchHooks`, including when `configurePhase` is
overridden. The build and install hooks register phases only when no phase is
provided and their opt-out is unset. Each hook enters `bunRoot` and restores the
working directory afterward. Custom phases that previously relied on the
configure phase leaving the shell in `bunRoot` must enter it themselves and
restore the working directory before the next phase.

Source selection, unpack and patch settings are passed explicitly to the
dependency fetcher. Package `nativeBuildInputs`, `buildInputs`, and `env` are
not forwarded. If a shared `postPatch` runs jq, add jq to both
`nativeBuildInputs` and `bunDepsNativeBuildInputs`; Git dependencies normally
need Git only in `bunDepsNativeBuildInputs`. For custom fetcher environment or
phases, supply `bunDeps = fetchBunDeps { ... };` explicitly. The hook
flags are derivation attributes. Hooks use stdenv's `concatTo` convention for
strings, structured arrays, and shell `*FlagsArray` variables. Set
`__structuredAttrs = true` when hook flag arguments contain spaces; ordinary
unstructured list attributes become space-separated strings. The fetcher
shell-escapes its Nix flag lists and preserves spaces in either mode.
Only put options accepted by all five commands in `bunFlags`; use the
command-specific flags for other options. `bunBuildFlags` are script arguments,
so Bun options belong in `bunFlags`.

The default hooks use Bun as the JavaScript runtime and do not add Node.js,
npm, node-gyp, Python, or Node headers. If no `node` executable is present after
stdenv assembles `PATH`, they append a permanent store-path `node` symlink to
Bun. This works in custom shell phases and in patched dependency shebangs.
An explicitly supplied Node.js runtime takes precedence, matching Bun's own
fallback behavior. For build scripts that need real Node.js, set
`nodejs = pkgs.nodejs-slim;` or add a Node.js package to `nativeBuildInputs`.

Prebuilt Node-API addons do not need an additional hook. To compile dependencies
using node-gyp, enable the optional toolchain:

```nix
nodeGyp = true;
makeCacheWritable = true; # when installation needs to modify the cache
```

The flag adds `bunHooks.bunNodeGypHook`, configured with the builder's selected
Bun and Node.js. To run node-gyp with genuine Node.js and compile against its
matching sources instead, use:

```nix
nodeGyp = true;
nodejs = pkgs.nodejs; # or pkgs.nodejs-slim
```

This selects Node.js for node-gyp's wrapper and `node` commands in the build;
installed application wrappers still use Bun. Merely adding Node.js to
`nativeBuildInputs` changes `PATH`, but does not select node-gyp's runtime or
headers. For independent hooks, use
`pkgs.bunNodeGypHook.override { nodejs = pkgs.nodejs; }`.

`bunNodeGypHook` supplies Python, local Node headers, and the standalone upstream
`node-gyp` package executed with Bun. The tool and its dependencies are fetched
as individually hashed npm archives; no Bun lockfile, Node.js, or npm is needed
to build it. Its small, flat dependency closure is pinned in
[`node-gyp/packages.json`](./node-gyp/packages.json); updates must keep all
transitive dependencies and their compatible versions in sync. Darwin receives cctools and the same deterministic Xcode-version
fallback used by Nixpkgs' bundled gyp. The builder's stdenv supplies the compiler;
add package-specific libraries through the usual inputs. The hook sets
`npm_config_node_gyp`, `npm_config_nodedir`, `npm_config_target` and
`npm_config_python` so compilation uses pinned tools and local headers rather
than downloading them. It does not change Bun's lifecycle trust rules.

The helper packages are `pkgs.bunNodeGyp` and `pkgs.bunNodeHeaders`. The latter
fetches the official Node header archive matching the pinned Bun's reported
`process.versions.node`, independently of any Node.js runtime package. A flake
check verifies that these versions match. To use another header set or Python,
override the native hook's `bunNodeHeaders` or `python3` argument; a custom
header derivation must expose its `version`. If selecting another Bun, use
`pkgs.bunNodeGypHook.override { bun = myBun; }` alongside `bun = myBun` in the
builder. With `nodeGyp = true`, the builder selects the hook's Bun automatically.
Bun supports Node-API addons; V8-specific addons may require changes.

To update Bun and its matching headers, run from the repository root:

```sh
$(nix-build --no-out-link -A bun.updateScript)
```

The `passthru.updateScript` updates Bun's platform hashes with nixpkgs'
`update-source-version`, builds the selected Bun to query its Node compatibility
version, then updates the header version and hash. It checks the headers even
when Bun is already current. Pass a Bun version as an argument to select a
specific release. `bunNodeHeaders.updateScript` runs the same updater.

The same hook works in development shells:

```nix
pkgs.mkShell {
  packages = [ pkgs.bunNodeGypHook ];
}
```

This supplies Bun, the fallback `node` command, node-gyp, Python and local header
configuration; `mkShell` supplies the compiler. Continue using `bun install`
normally, or run `node-gyp rebuild` directly from a package with `binding.gyp`.
Commands inside `.gyp` files can also invoke `node`. Prefer this setup when you
want a Nix-managed native toolchain: Bun's automatic fallback can fetch node-gyp
but does not supply the complete pinned compiler/Python/header environment.
For a Bun shell with just the `node` fallback and no native toolchain, use
`pkgs.bunHooks.bunNodeFallbackHook` instead.

Bun 1.4.4 has no `rebuild` command. An install with `--ignore-scripts` followed
by a normal install **does not replay dependency scripts**. `bun pm trust`
operates on untrusted dependencies and changes the trust configuration; using
`npm rebuild` indiscriminately would run scripts Bun blocks. We therefore run
Bun's permitted scripts in the initial install and patch shebangs afterward.
This differs from npm: a lifecycle script that executes a dependency with a
hardcoded `/bin/bash` or `/usr/bin/env` shebang can fail before patching. Such
packages need an explicit fix, for example `makeCacheWritable = true` and a
`preBunInstall` hook that patches the cache:

```nix
makeCacheWritable = true;
preBunInstall = ''
  patchShebangs "$BUN_INSTALL_CACHE_DIR"
'';
```

Use a package-specific cache patch when a dependency patch needs the original
file contents. The `lifecycle-shebangs` check exercises this preparation path.

For monorepos, keep `bunRoot` at the workspace root containing the lockfile.
Set `bunWorkspace = "apps/my-app";` to build and expose one workspace's bins
and manuals. Set `makeCacheWritable = true` when Bun needs to update the cache
for local packages or workspace bins. Dependencies are installed and pruned
for the whole workspace by default.
`bun pm fetch` always downloads the complete workspace lockfile; `bunWorkspace`
does not narrow that cache. `buildNpmPackage` likewise fetches the complete npm
lockfile, while its workspace option affects later build/pack/prune commands.
Bun install/prune filtering can be requested explicitly with `bunInstallFlags`
and `bunPruneFlags`; it does not reduce fetching. Keeping a single full cache
allows several workspace packages to share `bunDeps`.
The installer preserves the project directory layout beneath
`$out/lib/node_modules/<root-package-name>`, packing linked workspace packages
separately and copying both root and workspace-local `node_modules`. A root
without a version acts as a container: only its manifest and dependencies are
installed. Packages passed to `bun pm pack` require a name and version. This
preserves hoisted and isolated-linker dependencies after the source is removed.
Local package links outside `bunRoot` are rejected; include them under that
root or provide a custom installer. This is not a minimal dependency closure
for the selected workspace: other installed workspaces are retained. For a
bundle or a subset of build artifacts, use a custom `installPhase`.

`bunRoot` and `bunWorkspace` serve different purposes. Each hook enters the
project root; the build hook additionally enters the selected workspace. Neither
changes the working directory of later phases. Unlike npm's workspace option,
`bunWorkspace` is a directory, not a package name or filter pattern. Cross
compilation is not supported.

## Scope and checks

The checks exercise direct and writable caches, lifecycle mutations, trusted
scripts using Bun as `node`, native Node-API addons built with Bun (implicit and
explicit node-gyp builds), standalone node-gyp cache validation, runtime closure
checks without Node.js/npm, persistent shebangs, explicit Node.js precedence,
patched dependencies, independent and replacement hooks, custom phases,
nested roots, catalog workspaces and JSONC lockfiles, installed workspaces with
both hoisted and isolated linkers, scoped wrappers and manuals, structured flag
arrays, pruning, and cache validation. They also cover a binary lockfile,
duplicate identical Git URLs under two aliases, an explicitly Windows-only optional dependency, an authenticated local
registry, and a fixture combining a pinned Git dependency, an HTTP tarball, and
a non-default registry. Distinct cache output names and derivation salts force independent platform fetches when
fetcher inputs change. Run `nix flake check` on each supported system to verify
the caches and builds, or use the remote-builder command in [REVIEW.md](./REVIEW.md).

The ordinary build must run with Nix sandboxing enabled to enforce network
isolation for arbitrary lifecycle/build scripts. Bun's `--offline` governs the
package installation itself; it does not prevent a project's scripts from
performing their own downloads. Native dependencies that download extra assets
in scripts need those assets supplied separately.

The Git, tarball, and registry fixture covers one public GitHub repository, one
npm tarball, and the public Yarn registry. The authentication fixture exercises
a bearer-token registry, rejects missing/incorrect credentials, checks the cache
for token leakage, and installs offline after the server stops and the token is
unset. Other Git protocols and private Git authentication remain untested.

A hash-free `importBunLock` is left for a follow-up. The intended approach is to
parse the text lockfile, fetch individual tarballs with their recorded integrity
hashes, and assemble the cache without network access. That also needs explicit
handling for JSONC, custom registries, Git sources, and Bun's cache naming rules
(including prerelease versions). The fixed-output cache helper does not rely on
those internal naming rules.

The new commands are described in the
[Bun 1.4.4 release notes](https://bun.com/blog/bun-v1.4.4#bun-pm-fetch).

For the corresponding npm, Yarn, and pnpm packaging patterns, see the
[Nixpkgs JavaScript documentation](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md).
