# nix-bun

`buildBunPackage` builds Bun projects using a fixed-output dependency fetch followed
by an offline install. Includes Bun 1.4.4 and a nixpkgs overlay.
See [the implementation review](./REVIEW.md) for the Nixpkgs comparison,
workspace/native-module validation, and remaining limitations.

```sh
nix build path:.#example
./result/bin/bun-example 3   # odd
nix flake check path:.
```

## Use in a flake

Add this repository as an input named `nix-bun`, then apply its overlay:

```nix
let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ nix-bun.overlays.default ];
  };
in {
  packages.${system}.my-app = pkgs.buildBunPackage {
    pname = "my-app";
    version = "1.0.0";
    src = ./.;
    bunDepsHash = pkgs.lib.fakeHash;
  };
}
```

Commit `package.json` and `bun.lock` (or `bun.lockb`). Build once with
`lib.fakeHash`, copy the `got: sha256-…` value from Nix's hash mismatch into
`bunDepsHash`, then build again. Repeat when dependencies change. To fetch just
an application's dependencies, use `nix build .#my-app.bunDeps`.

The helpers are also available through
`nix-bun.legacyPackages.${system}.{buildBunPackage,fetchBunDeps}`. The overlay
replaces `pkgs.bun` with the provided 1.4.4 derivation. Supported systems are
`aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`.

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

The cache format changed: **existing `bunDepsHash` values must be regenerated**
with `lib.fakeHash`, even when the lockfile has not changed. A reused `bunDeps`
cache must contain matching version metadata and the same lockfile. Cache
output names include the selected Bun version and derivation identity, forcing
fetching again after Bun changes even if an old fixed-output cache was already
substituted. This changes output paths without changing the cache content hash.

By default Bun reads the store cache directly. Set `makeCacheWritable = true`
when dependency patches or lifecycle scripts modify existing package files or
when Bun needs to write to the cache. Some lifecycle-enabled installs require
cache writes even when installed files use `copyfile`. This option copies the
cache to `$TMPDIR` first.

The archive applies Bun’s publish-file selection (`files`, ignore rules and
package metadata). Dependencies are copied separately after pruning.

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
| `bun` | overlay Bun | Bun package used for fetching, hooks, and executable wrappers (>= 1.4.4) |
| `nodejs` | `null` | Optional genuine Node.js runtime for build/lifecycle compatibility; otherwise `node` runs Bun |
| `bunDepsHash` | `""` | Recursive SHA-256 SRI hash of the dependency cache |
| `bunDeps` | fetched from `src` | Reuse an existing dependency cache derivation/path |
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

Source selection, unpack and patch settings, caller preparation inputs, and
`env` are forwarded to the dependency fetcher. This explicit selection avoids
passing package build and install phases into the fixed-output fetch. The hook
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
using node-gyp, add the optional toolchain:

```nix
nativeBuildInputs = [ pkgs.bunNodeGypHook ];
makeCacheWritable = true; # when installation needs to modify the cache
```

`bunNodeGypHook` supplies Python, local Node headers, and the standalone upstream
`node-gyp` package executed with Bun. Neither Node.js nor npm is used to build or
run that tool. Darwin receives cctools and the same deterministic Xcode-version
fallback used by Nixpkgs' bundled gyp. The builder's stdenv supplies the compiler;
add package-specific libraries through the usual inputs. The hook sets
`npm_config_node_gyp`, `npm_config_nodedir`, `npm_config_target` and
`npm_config_python` so compilation uses pinned tools and local headers rather
than downloading them. It does not change Bun's lifecycle trust rules.

The helper packages are `pkgs.bunNodeGyp` and `pkgs.bunNodeHeaders`. The latter
fetches the official Node 26.3.0 header archive, independently of any Node.js
runtime package. To use another header set or Python, override the native hook's
`bunNodeHeaders` or `python3` argument; a custom header derivation must expose
its `version`. If selecting another Bun, use
`pkgs.bunNodeGypHook.override { bun = myBun; }` alongside `bun = myBun` in the
builder. Bun supports Node-API addons; V8-specific addons may require changes.

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
for local packages or workspace bins. Dependencies are installed and pruned for the whole workspace.
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
arrays, pruning, and cache validation. They also cover a binary lockfile and a fixture combining a pinned
Git dependency, an HTTP tarball, and a non-default registry. Distinct cache
output names and derivation salts force independent platform fetches when
fetcher inputs change. Run `nix flake check` on each supported system to verify
the caches and builds, or use the remote-builder command in [REVIEW.md](./REVIEW.md).

The ordinary build must run with Nix sandboxing enabled to enforce network
isolation for arbitrary lifecycle/build scripts. Bun's `--offline` governs the
package installation itself; it does not prevent a project's scripts from
performing their own downloads. Native dependencies that download extra assets
in scripts need those assets supplied separately.

The Git, tarball, and registry fixture covers one public GitHub repository, one
npm tarball, and the public Yarn registry. Private registry authentication and
other Git protocols are not covered; authentication is not exposed as a
dedicated option.

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
