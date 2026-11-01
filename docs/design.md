# Design notes

[README](../README.md) · [Packaging guide](./packaging.md) · [Reference](./reference.md) · [Design](./design.md) · [Contributing](../CONTRIBUTING.md)

These notes explain implementation choices and internal formats. For packaging
instructions, use the [guide](./packaging.md); for supported interfaces, use the
[reference](./reference.md).

- [Dependency cache design](#dependency-cache-design)
- [Installation stages](#installation-stages)
- [Installed package layout](#installed-package-layout)
- [Native toolchain implementation](#native-toolchain-implementation)
- [Imported source types](#imported-source-types)
- [Imported source installation](#imported-source-installation)
- [Upstream context](#upstream-context)

## Dependency cache design

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
workspace/Yarn migration configuration, and one JSON patch per changed manifest.
`jd-diff-patch` generates and applies the patches using its RFC 6902 subset,
checking old values and rejecting additions that would overwrite existing fields.
The migration hook validates those inputs and stages all patched manifests before
writing any of them. The config hook then checks the generated Bun lockfile as usual.

Fetching covers all platforms in the lockfile, while offline installation
selects the build host's dependencies. This lets workspaces and platforms share
a cache, but can be expensive: workspace selection and install filters do not
reduce downloads.

See [imported source installation](#imported-source-installation) for the
alternative source-bundle format and resolution rewriting.

The fetcher's source-preparation allowlist prevents package phases and setup
hooks from running during fetching or introducing dependency cycles.

### Foreign-lockfile migration

The cache contains the generated Bun lockfile and any manifest edits made by
migration. Migration can consult the registry for missing metadata; its temporary
registry cache is excluded from the fixed-output result. The separate
`bunHooks.bunMigrateHook`, added when `bunMigrateLockfile = true`, applies the saved
result after project patches and before offline installation. Upstream does not need to
commit a generated Bun lockfile. Manifest edits are saved as JSON patches, preserving
unrelated build-side changes such as scripts and descriptions. Conflicting edits
fail with the affected manifest; dependency changes still require a matching cache
and must pass Bun's frozen-lockfile validation.

In the fetcher, `bunMigrateLockfile = true` adds `bunHooks.bunFetchMigrateHook`,
which runs migration after project patching, before installation. The install
phase only fetches from the resulting Bun lockfile. `writableTmpDirAsHomeHook`
provides a writable home throughout source preparation and fetching.

## Installation stages

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

The [hook contract](./reference.md#dependency-preparation-hooks) defines where custom
dependency edits belong during this preparation.

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

## Installed package layout

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

## Native toolchain implementation

The optional node-gyp toolchain uses pinned tools and local headers to avoid
automatic downloads. It sets `npm_config_node_gyp`, `npm_config_nodedir`,
`npm_config_target`, and `npm_config_python`; Bun's lifecycle trust rules still
apply. Its launcher uses `node` from `PATH`, independently of `nodeGypTarget`.
Darwin uses cctools and Nixpkgs' deterministic Xcode-version fallback.
Bun supports Node-API addons; V8-specific addons may require changes.

Standalone node-gyp is itself built with `buildBunPackage` and a committed
lockfile, keeping dependency resolution in Bun instead of maintaining a custom
archive list and installer. Our Bun package exposes pinned headers matching its
reported `process.versions.node`; a flake check verifies this default pairing.
Consumer builds warn about differing versions rather than rejecting potentially
compatible Node-API addons.

## Imported source types

This implementation targets Bun 1.4.4. The source inventory comes from Bun's
[text-lockfile parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/bun.lock.rs),
[resolution parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/resolution.rs),
and [dependency specifier parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/dependency.rs).
The importer consumes normalized `bun.lock` resolutions, rather than parsing
every specifier accepted by `package.json`.

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
branch. This is a locked evaluation-time fetch, not import from derivation.
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

The original importer used one integrity-pinned `fetchurl` per archive, served
the files over loopback, and called `bun pm fetch` in a copied source tree.
That delegated cache naming to Bun, but required all-platform extraction, a
server, and Darwin's local-network sandbox allowance.

Bun also accepts local archive paths in text lockfiles under
`--offline --frozen-lockfile`. The new source bundle contains fetched archive
and checkout links plus original-lockfile metadata. It contains no extracted
package tree and needs no Bun executable to assemble. Installation extracts
only the packages selected for the current platform and caller's install flags.
Fetching still covers the complete lockfile, so platform variants remain shared
Nix fetcher inputs.

`buildBunPackage` selects the import config hook automatically. Standalone users
add `importBunLock.bunConfigHook` to `nativeBuildInputs`. The metadata identifies
the format as `source-bundle` for `importBunLock` and `extracted-cache` for
`fetchBunDeps`. Both start at format version 1 and can evolve
independently. The format and version are stored in `.nix-bun/format` and
`.nix-bun/format-version`, respectively.
The ordinary cache hook rejects source bundles supplied without the import hook.

The shared config hook still validates the original lockfile byte for byte,
checks frozen manifest consistency, and handles shebangs, ELF libraries,
trusted lifecycle scripts, both linkers, and dependency patches. The importer
changes archive resolution locations and the corresponding patch keys in the
lockfile/root manifest. It retains dependency edges, version constraints,
platform metadata, and trust lists. The rewritten resolutions stay in place
through build and prune; explicitly publishing a rewritten lockfile or patch
metadata can retain archive store references. Use `fetchBunDeps` when original
resolution identities are required throughout the build.

Git is a small exception to direct archive installation. Its fetched checkout
is copied into the private cache as `@G@<locked-commit>` with a matching
`.bun-tag`, following Bun 1.4.4's
[Git cache lookup](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/PackageManager/PackageManagerDirectories.rs).
It retains the Git resolution and checkout metadata without inventing an archive
integrity hash or implementing registry/prerelease cache naming. These native
Git names are an internal interface, covered by integration tests. The fetched
checkout retains its symlinks; Bun's `copyfile` installation backend omits package
symlinks, matching the existing builder's native Git behavior.

The private cache is always writable. `makeCacheWritable` is unnecessary for
this provider, and `preBunInstall` cannot assume archive packages have already
been extracted. The source-bundle output itself stays unchanged by preparation,
patching, and lifecycle scripts.

## Upstream context

For upstream context, see the
[Bun 1.4.4 release notes](https://bun.com/blog/bun-v1.4.4#bun-pm-fetch) and
[Nixpkgs JavaScript documentation](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md).
