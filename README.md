# nix-bun

`buildBunPackage` builds Bun projects using a fixed-output dependency fetch followed
by an offline install. Includes Bun 1.4.4 and a nixpkgs overlay.

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

1. `fetchBunDeps` unpacks and patches the source and runs `bun pm fetch`
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
   excludes packed dependencies, and installs the pruned `node_modules` once.
   Bins receive Bun wrappers and declared manual pages are installed.

The cache format changed: **existing `bunDepsHash` values must be regenerated**
with `lib.fakeHash`, even when the lockfile has not changed. A reused `bunDeps`
cache must contain matching version metadata and the same lockfile.

By default Bun reads the store cache directly. Set `makeCacheWritable = true`
when dependency patches or lifecycle scripts modify existing package files or
when Bun needs to write to the cache. Some lifecycle-enabled installs require
cache writes even when installed files use `copyfile`. This option copies the
cache to `$TMPDIR` first.

The archive applies Bun’s publish-file selection (`files`, ignore rules and package metadata); it is not merely a way to copy `node_modules`. The installer copies dependencies separately after pruning.

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

## Options

| Attribute | Default | Purpose |
| --- | --- | --- |
| `bun` | overlay Bun | Bun package used for fetching, hooks, and executable wrappers (>= 1.4.4) |
| `bunDepsHash` | `""` | Recursive SHA-256 SRI hash of the dependency cache |
| `bunDeps` | fetched from `src` | Reuse an existing dependency cache derivation/path |
| `bunRoot` | `"."` | Project directory relative to the unpacked source root |
| `bunFetchFlags` | `[]` | Extra `bun pm fetch` arguments |
| `bunInstallFlags` | `[]` | Extra install arguments, e.g. `[ "--ignore-scripts" ]` |
| `bunBuildScript` | `"build"` | Script passed to `bun run` |
| `bunFlags` | `[]` | Common Bun options before script names, applied to fetch, install, run, pack and prune; e.g. `[ "--silent" ]` |
| `bunBuildFlags` | `[]` | Arguments passed to the build script |
| `dontBunBuild` | `false` | Skip the default build script |
| `dontBunPrune` | `false` | Retain dev dependencies in the default installation |
| `bunPruneFlags` | `[]` | Extra arguments to `bun prune` |
| `bunPackFlags` | `[]` | Extra `bun pm pack` arguments |
| `makeCacheWritable` | `false` | Copy the dependency cache to writable temporary storage |
| `makeWrapperArgs` | `[]` | Additional arguments for each executable wrapper |
| `dontBunInstall` | `false` | Disable the default install phase |
| `bunConfigHook`, `bunBuildHook`, `bunInstallHook` | default hooks | Replace individual setup hooks |

The hooks are also available independently as `pkgs.bunHooks.bunConfigHook`,
`bunBuildHook`, and `bunInstallHook`. Add Bun and the desired hooks to
`nativeBuildInputs` and provide `bunDeps` when using `stdenv.mkDerivation`.
The config hook runs in `postPatchHooks`, including when `configurePhase` is
overridden. The build and install hooks register phases only when no phase is
provided and their opt-out is unset. Each hook enters `bunRoot` and restores the
working directory afterward. Custom phases that previously relied on the
configure phase leaving the shell in `bunRoot` must enter it themselves and
restore the working directory before the next phase.

Source selection, unpack and patch settings, caller preparation inputs, and
`env` are forwarded to the dependency fetcher. This explicit selection avoids
passing package build and install phases into the fixed-output fetch. The hook
flags are derivation attributes; Nix passes list-valued flags as shell arrays.
Only put options accepted by all five commands in `bunFlags`; use the
command-specific flags for other options. `bunBuildFlags` are script arguments,
so Bun options belong in `bunFlags`. Add compilers, `pkg-config`,
Node.js, Python, or other lifecycle script tools through the usual inputs. Bun
executes trusted dependency lifecycle scripts during `bun install`, so a
separate `npm rebuild` would run them again. Native addons may invoke node-gyp:
provide a compatible Node.js, Python, compiler and local Node headers, and
configure node-gyp for those headers so it does not download them during the
sandboxed build. This helper does not configure node-gyp automatically.

For monorepos, fetch and install dependencies from the workspace root. Run workspace scripts through a custom `buildPhase` when you need workspace-specific Bun options. Workspace links work
during the build; use a custom `installPhase` to install the intended workspace
or bundle. Copying the root's `node_modules` alone cannot preserve links to
workspace source directories outside that tree. See `tests/fixtures/workspace`.
Cross compilation is not supported by this initial implementation.

## Scope and checks

The checks exercise direct and writable caches, lifecycle mutations, trusted
scripts, patched dependencies, independent and replacement hooks, custom phases,
nested roots, workspace links, scoped wrappers and manuals, pruning, and cache
validation. They also cover a binary lockfile and a fixture combining a pinned
Git dependency, an HTTP tarball, and a non-default registry. Distinct cache
output names force independent platform fetches. Run `nix flake check` on each
supported system to verify the caches and builds.

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
