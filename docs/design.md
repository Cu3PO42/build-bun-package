# Design notes

[README](../README.md) · [Packaging guide](./packaging.md) · [Reference](./reference.md) · [Design](./design.md) · [Contributing](../CONTRIBUTING.md)

These notes explain the implementation choices behind bunflake. For packaging
instructions, use the [guide](./packaging.md); for supported interfaces, use the
[reference](./reference.md).

The guiding principle is to provide an equivalent to `buildNpmPackage`, keeping
its API where possible while accounting for Bun's differences. The central
constraint is the same: fetch dependencies with network access first, then
build the application offline. The sections below follow those dependencies
from fetching through preparation to the installed output.

- [Design notes](#design-notes)
  - [Dependency cache design](#dependency-cache-design)
    - [Foreign-lockfile migration](#foreign-lockfile-migration)
  - [Installation stages](#installation-stages)
  - [Installed package layout](#installed-package-layout)
  - [Native toolchain implementation](#native-toolchain-implementation)
  - [Imported source types](#imported-source-types)
    - [Pinning and fetchers](#pinning-and-fetchers)
  - [Imported source installation](#imported-source-installation)
  - [Upstream context](#upstream-context)

## Dependency cache design

`fetchBunDeps` uses `bun pm fetch` to populate Bun's install cache without
installing `node_modules`. The cache is the output of a fixed-output derivation
(FOD), so Nix verifies its contents against the caller's hash. Bun handles
lockfile parsing, downloads, and cache naming; the fetcher does not need to
reimplement them.

We keep the cache as a directory. Bun also offers an archive form, but we found
that the archive depends on the current filesystem and is not deterministic.
A recursively hashed directory avoids that problem and an extra compression
and extraction pass.

The offline consumer needs to know whether a cache belongs to its project.
We therefore record the exact lockfile and a cache-format marker under
`.nix-bun`. Before installing, the config hook checks the format and compares
the lockfile byte for byte. This rejects a stale cache before Bun attempts to
use it. The marker versions our format.

A fixed-output store path depends on its name and content hash. Consequently,
a Bun upgrade can reuse the same cache if its contents are unchanged. If a Bun upgrade
changes the cache contents, the hash must be recalculated. Changes to our own
cache format also require updating its version marker and expected hashes.

Fetching includes all platforms in the lockfile, while offline installation
selects the build host's dependencies. This lets workspace packages and
platforms share a cache, at the cost of downloading variants they do not use.
Workspace selection and install filters therefore do not reduce fetching, a
tradeoff also made by Nixpkgs' `buildNpmPackage`.

### Foreign-lockfile migration

Bun can migrate npm (`package-lock.json`, `npm-shrinkwrap.json`), Yarn
(`yarn.lock`), and pnpm (`pnpm-lock.yaml`) lockfiles.
This generates a `bun.lock` as well as changes to `package.json` files.
Migration may consult the registry for missing metadata, so it must happen in the network-enabled fetcher.
Repeating it in the offline application build would not work.

Instead, `bunFetchMigrateHook` runs migration after source patching and saves its
result alongside the cache. This includes the generated Bun lockfile, snapshots
of the foreign lockfiles and workspace/Yarn configuration, and a JSON patch for
each changed manifest.

`bunMigrateHook` then validates those input snapshots and replays the result
after project patching, before `bunConfigHook` installs dependencies. Manifest
patches preserve unrelated build-side edits, such as changed scripts or
descriptions. They are generated and applied by `jd-diff-patch` using its
RFC 6902 subset, which checks old values and rejects additions that would
overwrite existing fields. All patched manifests are staged before any are
written, so a conflict does not leave a partially migrated project.

Once replay is complete, the ordinary config hook validates the generated Bun
lockfile against the cache. This keeps the same frozen-install contract as a
project with a committed Bun lockfile. `buildBunPackage` pairs the fetch and
replay hooks when `bunMigrateLockfile = true`; callers composing their own
fetcher and build must enable both.

## Installation stages

Dependency preparation must make packages usable in a Nix build before their
scripts execute. Their shebangs may reference unavailable interpreters, and
prebuilt Linux binaries may need loader and library paths adjusted. At the
same time, Bun's `patchedDependencies` must see original package contents so
its patches still apply. This ordering motivates the installation stages.

The config hook first validates the cache and runs `preBunInstall`. It patches
executable project files, including workspace and local `file:` helpers that
may be used during installation.

With scripts disabled, the hook can install offline directly from the store
cache, then patch the installed dependencies before build and check phases.
`makeCacheWritable` gives Bun a private temporary copy when it needs to modify
the cache. A writable temporary
home is supplied through Nixpkgs' `writableTmpDirAsHomeHook` when needed.

With `bunRunScripts`, the cache is always copied. Two installation passes
surround the preparation step:

1. An offline, script-free install uses the hoisted linker and symlink backend.
   Bun applies dependency patches against pristine contents. Symlinked
   manifests then identify the cache packages actually selected for this build.
2. The hook patches those packages' shebangs and, when `autoPatchelfHook` is
   present, ELF binaries. Foreign platform packages are left untouched.
   `preBunInstallScripts` can make further edits to the prepared cache packages.
3. A forced offline install copies the prepared packages and runs trusted
   scripts.

The final install must be forced because an ordinary second install skips
dependency scripts. The separation is inspired by
[bun2nix's lifecycle phases](https://github.com/nix-community/bun2nix/blob/0f2a1f0b6f42cebe3b149bf62d38754c5e0e9729/nix/mk-derivation/hook.sh)
and Nixpkgs' `npm ci --ignore-scripts` followed by `npm rebuild`. Bun has no
equivalent rebuild command, so both passes remain Bun installs.

After the final install, shebang and optional ELF preparation also cover newly
generated binaries. `postBunInstall` then runs before control returns to the
normal build phases. The [dependency preparation contract](./reference.md#dependency-preparation-hooks)
specifies where custom edits belong; changing pristine cache files in
`preBunInstall` can invalidate dependency patches.

## Installed package layout

The default installer aims to preserve the runnable package while following
upstream's choice of publishable files. It uses `bun pm pack` for file selection
because Bun has no equivalent of npm's machine-readable `pack --json` file list.
Dependencies are copied from the pruned installed tree rather than the archive,
so unbundled dependencies and lifecycle-script changes are retained too.

For a single package, this produces the familiar
`$out/lib/node_modules/<root-package-name>` layout. Workspaces and local packages
need more care: copying only the selected member could leave its links pointing
back into the discarded source tree. The installer therefore preserves the
surrounding directory structure, including hoisted dependencies and the isolated
linker's shared `.bun` store. Local package links outside `bunRoot` are rejected
because that layout cannot preserve them safely.

Preserving the tree means other installed workspaces can remain in the output;
it is not a minimal dependency closure. Packages that only need a bundle or
selected artifacts should use a custom `installPhase` instead.

Packages selected for packing need a name and version. A workspace root without
a version acts as a container: only its manifest and dependencies are installed
at that level.

## Native toolchain implementation

Native addons introduce three separate choices: the package manager, the
interpreter running build tools, and the runtime loading the compiled addon.
Bun remains the package manager. If `node` is available
on `PATH`, it is used. Otherwise Bun is implicitly symlinked as `node`. node-gyp's launcher
uses that command, while `nodeGypTarget` independently selects its headers.

The optional toolchain supplies pinned node-gyp, Python, and local headers to
avoid automatic downloads. It sets `npm_config_node_gyp`, `npm_config_nodedir`,
`npm_config_target`, and `npm_config_python`. On Darwin it also supplies cctools
and uses Nixpkgs' deterministic Xcode-version fallback. Bun's lifecycle trust
rules still determine which dependency scripts execute.

Standalone node-gyp is itself built with `buildBunPackage` and a committed
lockfile, keeping dependency resolution in Bun. Our Bun package exposes headers
matching its reported `process.versions.node`, and a flake check verifies that
pairing. Consumer builds warn about differing header versions rather than
rejecting them: Node-API addons may remain compatible across versions, while
V8-specific addons may need changes regardless of matching version numbers.

Interpreter selection also needs a final output step. Early shebang patching
uses build interpreters; the runtime hook later runs
`patchShebangs --host --update` so installed Node shebangs use `runtime`.
Development outputs use `--build --update`. A helper handles absolute commands
after `env -S`, which the pinned Nixpkgs `patchShebangs` cannot repatch. This is
why custom installation must retain the standard fixup phase or implement its
own interpreter rewriting.

## Imported source types

`importBunLock` takes a different approach to fetching: Nix reads the text
lockfile and fetches each remote source separately. It therefore needs to
recognize Bun's serialized source types. The implementation targets the Bun
1.4.4 format, using Bun's
[text-lockfile parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/bun.lock.rs),
[resolution parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/resolution.rs),
and [dependency specifier parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/dependency.rs).
The importer consumes these normalized `bun.lock` resolutions; it does not
need to parse every specifier accepted by `package.json`.

`INFO` below is Bun's dependency, platform, script, and bin metadata object.
Optional integrity fields are shown in parentheses.

| Lockfile resolution | Typical tuple | Import strategy |
| --- | --- | --- |
| npm registry | `["name@1.2.3", "tarball URL or empty", INFO, integrity]` | `fetchurl`, then a local-archive resolution |
| HTTP(S) archive | `["name@https://host/archive", INFO, (integrity)]` | `fetchurl`, then a local-archive resolution |
| GitHub | `["name@github:owner/repo#commit", INFO, bun-tag, (integrity)]` | `fetchurl` from GitHub's `legacy.tar.gz` codeload endpoint, then a local-archive resolution |
| Git | `["name@git+URL#commit", INFO, bun-tag, (integrity)]` | Fetch the pinned checkout and seed its native Git cache entry |
| Local archive | `["name@./archive.tgz", INFO, (integrity)]` | Leave the resolution in place; Bun reads the source archive directly |
| Directory | `["name@file:path", INFO]` | Leave in place |
| Link | `["name@link:path", INFO]` | Leave in place |
| Workspace | `["name@workspace:path"]` | Leave in place; old version-0 rows may also contain `INFO` |
| Root/self-reference | `["name@root:", INFO]` | Leave in place |

Local archive extensions `.tgz`, `.tar.gz`, and `.tar` are case-insensitive.
Bun strips the manifest's `file:` prefix when serializing a local archive;
`file:` in a **lockfile resolution** denotes a directory. Relative archives
resolve against the Bun project root. Absolute paths must exist in the Nix
sandbox. Project-local directories, links, and workspaces must be supplied by
the package source; user-global `bun link` registrations are not imported.

Aliases, scoped registries, version ranges/tags, GitHub URL/shorthand forms,
hosted Git shortcuts, catalogs, and overrides resolve to the source types above.
For example, Bun serializes the existing GitHub `git+https` fixtures as
`github:` rows. GitLab, Bitbucket, Gist, and SourceHut shortcuts use ordinary Git resolutions;
they do not need separate archive fetchers. `catalog:` is a constraint, not a
possible locked source resolution.

### Pinning and fetchers

HTTP and GitHub archives require a supported integrity hash from the lockfile
or a caller-supplied `fetcherOpts.<lock-key>.hash`. A short GitHub commit suffix
is safe to fetch only because the archive hash pins its bytes. The exact codeload
URL matters: the `legacy.tar.gz` endpoint reproduces the hashes in the fixtures.
Missing hashes in older lockfiles are not replaced with unverified downloads.

Generic Git uses the full commit in the `.bun-tag` tuple field, rather than a
branch or tag from the manifest. A legacy row can be pinned explicitly with
`fetcherOpts.<lock-key>.rev`. Without a `hash`, the importer uses
`builtins.fetchGit` with `allRefs = true`, allowing commits outside the default
branch. This is a locked evaluation-time fetch.
With a `hash`, the importer uses Nixpkgs' `fetchgit`, keeping the download in a
normal fetcher build. Options follow the chosen fetcher's interface, including
its own submodule and authentication options.

Bun serializes SCP-style Git URLs as `git+ssh://user@host:path`. The importer
restores Git's SCP syntax and preserves standard SSH URLs, numeric ports, and
IPv6 authorities. HTTP, SSH, and Git transports are delegated to Nix. Tests use
a real local Git transport and check other URL forms at evaluation; they do not
claim coverage of private hosted SSH authentication.

Local files and directories need no separate fetch hash: they already come
from the Nix package source. A separately available `lockFile` can describe a
generated `src` without reading that derivation during evaluation. The ELF
fixtures exercise this case with locally compiled tarballs.

## Imported source installation

Fetching archives individually leaves an installation problem: Bun normally
expects its own extracted cache, with names derived from package resolutions.
Reimplementing all that naming would duplicate Bun internals. Instead, the
importer uses Bun's support for local archive paths in text lockfiles under
`--offline --frozen-lockfile`.

The source bundle contains links to fetched archives and checkouts, plus the
original lockfile metadata. It needs no Bun executable to assemble and contains
no extracted package tree. During installation, `bunImportConfigHook` redirects
remote archive resolutions to those local paths. Bun then extracts only the
packages selected for the current platform and install flags, although fetching
still covers the complete lockfile.

Both dependency providers record their format in `.nix-bun/format` and version
in `.nix-bun/format-version`. `fetchBunDeps` uses `extracted-cache` and
`importBunLock` uses `source-bundle`, each currently at version 1. These formats
can evolve independently. `buildBunPackage` selects the import hook from the
bundle's passthru metadata; the ordinary cache hook rejects a source bundle
supplied without that hook.

The import hook extends the shared configuration flow. It first validates the
original lockfile byte for byte, then rewrites archive locations and the
corresponding dependency-patch keys in the lockfile and root manifest. Dependency
edges, manifest version constraints, platform metadata, and trust lists remain
intact. The ordinary install flow still handles frozen manifest validation,
shebangs, ELF preparation, lifecycle scripts, and both linkers.

The tradeoff is that rewritten resolutions remain in the build tree through
pruning. A build that publishes the rewritten lockfile or patch metadata may
retain archive store references. `fetchBunDeps` is the appropriate provider
when original resolution identities must be preserved throughout the build.

Git requires a separate path because a checkout is not an archive. The import
hook copies each fetched checkout into the private cache as
`@G@<locked-commit>` with a matching `.bun-tag`, following Bun 1.4.4's
[Git cache lookup](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/PackageManager/PackageManagerDirectories.rs).
This retains the Git resolution without inventing an archive integrity hash.
These native Git cache names are an internal interface covered by integration
tests. Fetched checkouts retain symlinks, but Bun's `copyfile` installation
backend omits package symlinks, as it does with the ordinary cache provider.

Because extraction and Git cache seeding happen during the build, the import
hook always creates a private writable cache. The source bundle stays unchanged
by preparation and scripts. This also means `preBunInstall` cannot assume archive
packages have already been extracted; edits that need those packages belong in
`preBunInstallScripts` or `postBunInstall`.

## Upstream context

For upstream context, see the
[Bun 1.4.4 release notes](https://bun.com/blog/bun-v1.4.4#bun-pm-fetch) and
[Nixpkgs JavaScript documentation](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md).
