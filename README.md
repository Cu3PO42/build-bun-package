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

1. `fetchBunDeps` unpacks and patches the source, runs
   `bun pm fetch --os '*' --cpu '*' --libc '*'`, then `bun pm cache pack`.
   It restores the pack into a clean cache, makes index symlinks relative, and
   hashes the directory using Nix's recursive SHA-256 hash. No dependency
   lifecycle scripts run during fetching. Fetching all platforms lets the same
   hash work on Darwin and Linux.
2. The package build copies that directory into a private writable cache and runs
   `bun install --offline --frozen-lockfile`. Lifecycle scripts run here under
   Bun's usual trust rules, with the build's tools and sandbox restrictions.
3. `bun run build` runs by default.
4. `bun pm pack --ignore-scripts` selects the package's published files, and
   `bun prune --production` removes dev dependencies. The package files and
   remaining `node_modules` are installed under `$out/lib/node_modules/<package-name>`.
   Each `package.json` bin gets a wrapper in `$out/bin` that invokes Bun.

Bun packs files in filesystem traversal order, so pack bytes differ between
Darwin and Linux even when package contents match. The pack/unpack round trip
selects just the lockfile entries, and Nix's recursive directory hash removes
file ordering and timestamp differences. Relative index symlinks keep the cache
relocatable. Cache format changes in future Bun versions may require a new hash.

Integration checks, including native optional dependencies and installed CLI
wrappers, pass on aarch64-darwin, aarch64-linux, and x86_64-linux. Linux builds run
on the configured remote builder.

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
| `bunDepsHash` | `""` | Recursive SHA-256 SRI hash of the dependency cache |
| `bunDeps` | fetched from `src` | Reuse an existing dependency cache derivation/path |
| `bunRoot` | `"."` | Project directory relative to the unpacked source root |
| `bunFetchFlags` | `[]` | Extra `bun pm fetch` arguments |
| `bunInstallFlags` | `[]` | Extra install arguments, e.g. `[ "--ignore-scripts" ]` |
| `bunBuildScript` | `"build"` | Script passed to `bun run` |
| `bunBuildFlags` | `[]` | Arguments passed to the build script |
| `dontBunBuild` | `false` | Skip the default build script |
| `dontBunPrune` | `false` | Retain dev dependencies in the default installation |
| `bunPackFlags` | `[]` | Extra `bun pm pack` arguments |

Normal stdenv phases and hooks work, including `preBuild`, `postInstall`,
`buildPhase`, `installPhase`, `doCheck`, and `checkPhase`. An overridden phase
must call its own pre/post hooks. Overriding `configurePhase` also replaces
cache setup and dependency installation. `sourceRoot`, `patches`, `prePatch`,
and `postPatch` are shared with the dependency fetcher so both stages see the
same manifests, lockfiles, and patches. Add compilers, `pkg-config`, Node.js,
Python, or other lifecycle script tools through the usual build inputs.

For monorepos, fetch and install from the workspace root. Workspace links work
during the build; use a custom `installPhase` to install the intended workspace
or bundle. Copying the root's `node_modules` alone cannot preserve links to
workspace source directories outside that tree. See `tests/fixtures/workspace`.
Cross compilation is not supported by this initial implementation.

## Scope and checks

The checks cover a CLI with transitive runtime dependencies and a native optional
dev dependency, production pruning and its opt-out, package file selection,
installed wrappers, a nested project,
hooks, workspace links, rejection of an empty offline cache, and rejection of a
changed manifest with a frozen lockfile. Each platform also fetches its own
cache under a distinct output name to verify that the hash is shared.
To check cache reproducibility:

```sh
nix build path:.#example.bunDeps --no-link --rebuild -L
nix flake check path:. --all-systems --no-build
```

`nix flake check --all-systems` evaluates all systems but only builds checks for
the current system. With a configured Linux builder, run all Linux checks with:

```sh
nix build --no-link -L \
  path:.#checks.{aarch64-linux,x86_64-linux}.{example,nested,workspace,keep-dev-dependencies,offline-failures,dependency-cache}
```

The ordinary build must run with Nix sandboxing enabled to enforce network
isolation for arbitrary lifecycle/build scripts. Bun's `--offline` governs the
package installation itself; it does not prevent a project's scripts from
performing their own downloads. Native dependencies that download extra assets
in scripts need those assets supplied separately.

Git dependencies, private registries, and patched dependencies have not yet been
covered by the integration fixtures. Authentication configuration is not exposed
as a dedicated option.

A hash-free `importBunLock` is left for a follow-up. The intended approach is to
parse the text lockfile, fetch individual tarballs with their recorded integrity
hashes, and assemble the cache without network access. That also needs explicit
handling for JSONC, custom registries, Git sources, and Bun's cache naming rules
(including prerelease versions). The fixed-output cache helper does not rely on
those internal naming rules.

The new commands are described in the
[Bun 1.4.4 release notes](https://bun.com/blog/bun-v1.4.4#bun-pm-fetch).
