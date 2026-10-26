# buildBunPackage review

Reviewed against the repository's pinned Nixpkgs revision
`3ec636362e1816bc2f0888fa0fa2c69f1bc9e504` and Bun 1.4.4.

The main gaps were default workspace installation, the missing native build
toolchain, unfrozen fetching, and handling of structured flag arrays. Workspace
bundling alone did not exercise installation, and esbuild's optional binary did
not exercise node-gyp. Both now have additional integration checks.

## Answers and decisions

| Question | Finding and resulting behavior |
| --- | --- |
| Does every hook need `bunRoot`? | It is optional: an unset value means the current source root. Always entering that directory is harmless and gives all three hooks consistent behavior. Upstream only conditionally enters `npmRoot` in its config hook; its build and install hooks do not enter it. Each Bun hook restores the directory afterward. |
| How does that relate to workspaces? | `bunRoot` identifies the directory containing the shared lockfile. New `bunWorkspace` identifies a member directory relative to it. Fetching, installation and pruning use the root; the build runs in the selected member, whose bins and manuals are exposed. |
| Should there be `bunFlags`? | Added for common options such as `--silent` and `--no-env-file`, across fetch/install/run/pack/prune. Command-specific options still use the corresponding attributes; putting an option in `bunFlags` requires all those commands to accept it. |
| Were the old flags unwired? | Most already reached the hooks because `extendMkDerivation` retains caller attributes. Explicit defaults now document the interface. Hooks use stdenv's `concatTo` to support strings, structured arrays and shell `*FlagsArray` variables. The old expansion lost structured array elements. |
| Is `bunRunFlags` necessary? | Removed. Bun options go before the script through `bunFlags`; `bunBuildFlags` remain arguments to the script. `bunWorkspace` handles selecting one workspace. Use a custom build phase for other run-only options or filter patterns. |
| Why use `bun pm pack`? | It implements package publication rules, including `files` and ignore files. It does not transfer `node_modules`. Unlike npm's JSON dry-run output, Bun does not provide a machine-readable list here, so extracting an archive remains useful. Copying the source directory would change the installed file selection. Dependencies are excluded from extraction and copied separately after pruning. |
| Are more hook dependencies needed? | The config hook now propagates Node.js, Python and Darwin cctools, and supplies matching Node sources and Nixpkgs' patched node-gyp. The install hook already propagates its wrapper/manual helpers. Absolute jq paths need no PATH propagation. npm's cache mapper and npm-specific Node patches have no corresponding role here. The custom bin/manual helpers retain the fixes for the pinned upstream hooks' scoped-string-bin and array-man handling. |
| Can the Bun version be customized? | Already supported through `bun = myBun`, including `overrideAttrs`. The chosen derivation supplies fetching, hooks and wrappers. Bun >= 1.4.4 is required for these package-manager commands. Checks now also verify the selected install hook, and verify that overriding `nodejs` selects matching config tooling. Recalculate dependency hashes when a Bun change changes the cache. |
| Is the preparation selection necessary? | An allowlist is necessary: forwarding the entire derivation could run package phases in the fetcher or create a dependency cycle through the hooks. Replaced the generated attribute intersection with `lib.filterAttrs`, retaining selection from `finalAttrs` so source/preparation overrides still apply. |

## Lifecycle scripts and native modules

The [upstream config hook](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/build-support/node/build-npm-package/hooks/npm-config-hook.sh)
installs without scripts, patches shebangs, rebuilds, and patches again. That is
a useful ordering, but Bun 1.4.4 cannot reproduce it with its current commands:
`bun rebuild` is not a package-manager command, and a second install after
`--ignore-scripts` leaves previously skipped trusted dependency scripts unrun.
This was checked with the trusted-dependency fixture. `bun pm trust` targets
untrusted packages and edits trust configuration. A blanket npm rebuild would
also run scripts Bun's trust rules block.

The config hook therefore retains Bun's normal lifecycle execution and patches
installed shebangs afterward. This is an intentional limitation, not equivalent
to npm's ordering. A dependency executable with an unusable interpreter can
still need fixing before lifecycle execution. New `preBunInstall` and
`postBunInstall` hooks allow such preparation. For example:

```nix
makeCacheWritable = true;
preBunInstall = ''
  patchShebangs "$BUN_INSTALL_CACHE_DIR"
'';
```

The `lifecycle-shebangs` check installs and executes a dependency script with a
deliberately invalid interpreter, fixed through this hook. Cache edits should
be package-specific when Bun dependency patches depend on the original bytes.
Patching the fixed-output cache during fetching would introduce build-platform
interpreter paths into an otherwise portable cache.

The native toolchain sets `npm_config_node_gyp` and `npm_config_nodedir` before
installation. Bun's [node-gyp shim](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/PackageManager.rs#L1396-L1481)
otherwise falls back to downloading node-gyp through `bun x`. Local headers
prevent node-gyp from downloading Node sources. The native fixture builds a C
Node-API addon through both implicit `binding.gyp` handling and an explicit
install script. Its installed addon returns `42` from Bun and Node. A separate
check removes trust and verifies compilation does not occur.

This establishes support for the tested Node-API build path. It does not imply
that every native package works: V8-specific addons, packages shipping their own
node-gyp, or scripts downloading extra binaries may require package-specific
inputs or patches. Bun's [lifecycle rules](https://bun.com/docs/pm/lifecycle)
continue to determine which scripts run.

## Workspace installation

The installer preserves the project-relative layout and packs linked local
packages separately, including workspace-local `node_modules`. It normalizes
dependency links into that installed layout. Checks cover hoisted and isolated
linkers; an unbundled CLI still runs after its source tree is removed. A root
without a version serves as a manifest/dependency container, since it cannot be
passed to `bun pm pack`.

This retains all installed workspaces and their production dependencies, rather
than computing a minimal closure for the selected member. Local dependency
links outside `bunRoot` are rejected. Workspace bins/local packages can require
`makeCacheWritable = true`. These constraints are documented in the README.

## Dependency fetching

Compared with the pinned [npm fetcher](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/build-support/node/prefetch-npm-deps/default.nix),
[Yarn fetcher](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/build-support/node/fetch-yarn-deps/default.nix),
and [pnpm fetcher](https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/build-support/node/fetch-pnpm-deps/default.nix),
the short implementation is reasonable because Bun's own
[`pm fetch`](https://bun.com/docs/pm/cli/pm#fetch) produces the cache without
installing packages or running lifecycle scripts. We do not need an additional
lockfile parser, npm cache mapper, or pnpm's SQLite/timestamp normalization.

Added frozen-lockfile enforcement, retained caller-supplied impure environment
variable names, and allowed the SRI hash to select its algorithm. Standalone
fetcher root/flag overrides now affect the executed command; escaped Nix flag
lists preserve arguments containing spaces. The output still fetches all
platform variants, removes temporary state, normalizes internal absolute links,
and records the cache format and exact lockfile. An empty cache is legitimate
for a project with only local dependencies, so npm's empty-cache opt-out is
unnecessary here.

## Validation and remaining limits

Validation on `aarch64-darwin` includes the flake checks, real native compilation
and loading, source-independent workspace execution, and dependency-cache
rebuilds. The registry cache and the Git/tarball/custom-registry cache reproduced
their existing hashes. A fresh native-addon build also passed with
`--option sandbox true` and an unusable Node-header download URL. Linux systems
were evaluated, not built on this machine; cross compilation remains unsupported.

During some native builds, the pinned Nixpkgs `audit-tmpdir` classifier subprocess
printed segmentation-fault diagnostics without failing the derivation. Native
runtime checks passed, as did the separate sandboxed build. Those checks do not
establish that the upstream audit classifier completed successfully.
