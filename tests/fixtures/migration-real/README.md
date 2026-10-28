# Real-world migration fixtures

The npm and Yarn snapshots come from projects packaged by the pinned nixpkgs
revision, `3ec636362e1816bc2f0888fa0fa2c69f1bc9e504`; pnpm and npm shrinkwrap
snapshots come from additional small upstream projects. Each snapshot retains
its complete lockfile and matching manifest. Only manifests, lockfiles, migration
configuration, and licensing information are vendored; the checks exercise
installed dependencies without building upstream applications or running
lifecycle scripts.

| Fixture | Format | Migrated package entries | Extracted cache, approximately |
| --- | --- | ---: | ---: |
| `markdown-toc` 1.2.0 | npm v3 | 58 | 3.4 MiB |
| `localtunnel` 2.0.2 | Yarn Classic | 91 | 7.3 MiB |
| `yarn-lock-converter` v0.0.2 | Yarn Berry v6 | 57 | 2.2 MiB |
| `relative-time` 1.1.0 | pnpm v9 | 56 | 7.9 MiB |
| OPC UA schema tools 1.0.0 | npm shrinkwrap v2 | 42 | 2.5 MiB |

The caches total about 23 MiB. `tests/migration-real.nix` enforces a 12 MiB
limit per cache and a 32 MiB combined limit, including foreign-lockfile
snapshots and generated migration metadata. Fresh fetches take a few seconds
per fixture on a typical connection; offline installation takes less than a
second in local testing. The checks enforce size bounds; timings are observations
from local testing.

## Provenance

- **markdown-toc:** [`package.json` and `LICENSE` at upstream commit
  `2e4e9b77718fa479c5b717f16656eb7daf25f9c0`](https://github.com/jonschlinkert/markdown-toc/tree/2e4e9b77718fa479c5b717f16656eb7daf25f9c0).
  The manifest has nixpkgs' existing
  [`no-dev-deps.patch`](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/by-name/ma/markdown-toc/no-dev-deps.patch)
  applied, matching its unmodified, production-only
  [`package-lock.json`](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/by-name/ma/markdown-toc/package-lock.json).
  This is the same dependency graph used by the nixpkgs package. Both sources
  use the MIT license; their license texts are included.
- **localtunnel:** unmodified `package.json`, `yarn.lock`, and `LICENSE` at
  [upstream commit `c8e85f49624d606730779fc4295a38fd0e650af5`](https://github.com/localtunnel/localtunnel/tree/c8e85f49624d606730779fc4295a38fd0e650af5),
  tagged `v2.0.2`. Includes the full development graph, multiple locked versions
  of `debug` and `yargs`, and the macOS-only optional `fsevents` dependency.
- **yarn-lock-converter:** unmodified `package.json`, `yarn.lock`, and
  `.yarnrc.yml` at
  [upstream commit `92869fef54be4cc25f330d136f3052eaf06e5d7b`](https://github.com/VHT/yarn-lock-converter/tree/92869fef54be4cc25f330d136f3052eaf06e5d7b),
  tagged `v0.0.2`. The upstream manifest still reports version `0.0.1` and
  declares the MIT license. Its Yarn 3 lock uses Yarn checksums rather than
  npm integrity hashes, exercising Bun's registry metadata hydration. The
  dependency graph includes scoped packages, cache/filesystem utilities,
  executable packages, and grouped dependency descriptors.
- **relative-time:** unmodified `package.json`, `pnpm-lock.yaml`, and `LICENSE`
  at [upstream commit `2a7529e0468fd71e1fb65ebec6e1df4be3eb0e2c`](https://github.com/yairEO/relative-time/tree/2a7529e0468fd71e1fb65ebec6e1df4be3eb0e2c).
  Its complete development graph includes Terser and source-map utilities,
  filesystem/CLI tools, and npm aliases such as `string-width-cjs`. The upstream
  project and included license declare MIT.
- **opcua-schema:** unmodified `tools/schema/package.json` and
  `tools/schema/npm-shrinkwrap.json` at
  [upstream commit `fcc89d8f8b93b5a0943ec8086706e883900faa3c`](https://github.com/locka99/opcua/tree/fcc89d8f8b93b5a0943ec8086706e883900faa3c/tools/schema).
  These are the real OPC UA code-generation tools' development dependencies,
  including CSV/XML parsers, lodash, and yargs. The v2 shrinkwrap retains both
  its `packages` and legacy `dependencies` sections. The package manifest
  declares ISC; the repository's MPL-2.0 `LICENSE.md` is also included.

## Updating

Update each snapshot from a pinned upstream revision and record the new origin
here. For `markdown-toc`, copy the lockfile and apply the manifest patch from
the same nixpkgs revision. Preserve fixture bytes; do not regenerate lockfiles
with Bun. Recalculate the hashes in `tests/migration-real.nix` with
`lib.fakeHash`, update the package counts in `tests/test-migration-real.ts`, and
run all `migration-real-*` checks. Keep the size bounds when selecting updates.
