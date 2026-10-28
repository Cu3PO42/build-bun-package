# Importing Bun sources

This implementation targets Bun 1.4.4. The source inventory comes from Bun's
[text-lockfile parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/bun.lock.rs),
[resolution parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/resolution.rs),
and [dependency specifier parser](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/dependency.rs).
The importer consumes normalized `bun.lock` resolutions, rather than parsing
every specifier accepted by `package.json`.

## Source inventory

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

## Pinning and fetchers

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

## Why a config hook instead of a complete cache

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

## Verification

The `import-lock-*` checks cover registry/scoped URLs, aliases, prereleases,
direct and legacy HTTP archives, pinned and legacy GitHub archives, real Git
checkouts, Git fetcher selection, executable bits, checkout symlinks, native Git
tags, local archive formats, root references, workspaces, catalogs, patches,
trusted and disabled lifecycle scripts, and source deletion after installation.
Linux checks also exercise ELF preparation and a foreign optional binary with
both hoisted and isolated linkers. All checks run with sandboxing enabled and
import from derivation disabled.

Binary `bun.lockb` remains supported by `fetchBunDeps`, or can be converted using
Bun's [documented text-lockfile migration](https://bun.com/docs/pm/lockfile).
