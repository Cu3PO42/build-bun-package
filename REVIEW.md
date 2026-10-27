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
| Why use `bun pm pack`? | It implements package publication rules, including `files` and ignore files. It can include `bundledDependencies`, but does not pack the full dependency graph. Unlike npm's JSON dry-run output, Bun does not provide a machine-readable list here, so extracting an archive remains useful. Copying the source directory would change the installed file selection. Dependencies are excluded from extraction and copied separately after pruning. |
| Are more hook dependencies needed? | The default hooks propagate Bun and a persistent fallback `node` shim. Optional `bunNodeGypHook` supplies standalone node-gyp running with Bun, Python, local headers and Darwin cctools; ordinary projects do not acquire that toolchain. The install hook already propagates its wrapper/manual helpers. Absolute jq paths need no PATH propagation. npm's cache mapper and npm-specific Node patches have no corresponding role here. The custom bin/manual helpers retain the fixes for the pinned upstream hooks' scoped-string-bin and array-man handling. |
| Can the Bun version be customized? | Already supported through `bun = myBun`, including `overrideAttrs`. The chosen derivation supplies fetching, hooks and wrappers. Bun >= 1.4.4 is required for these package-manager commands. Checks now also verify the selected install hook, and verify that an explicitly selected `nodejs` is supplied as an optional compatibility runtime. Recalculate dependency hashes when a Bun change changes the cache. |
| Is the preparation selection necessary? | An allowlist is necessary: forwarding the entire derivation could run package phases in the fetcher or create a dependency cycle through the hooks. Source fields are now spelled out explicitly from `finalAttrs`, so source/preparation overrides still apply. Fetcher tools use `bunDepsNativeBuildInputs`; package inputs and environment are not forwarded. |

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

The optional `bunNodeGypHook` sets `npm_config_node_gyp` and `npm_config_nodedir` before
installation. Bun's [node-gyp shim](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/PackageManager.rs#L1396-L1481)
otherwise falls back to downloading node-gyp through `bun x`. The selected
wrapper executes standalone node-gyp with Bun. Local headers and an explicit
target version prevent node-gyp from downloading Node sources. The native
fixture builds a C Node-API addon through both implicit `binding.gyp` handling and an explicit
install script. Its installed addon returns `42` from Bun; a separate consumer test loads it in
genuine Node.js without adding Node.js to the addon build. A separate
check removes trust and verifies compilation does not occur.

This establishes support for the tested Node-API build path. It does not imply
that every native package works: V8-specific addons, packages shipping their own
node-gyp, or scripts downloading extra binaries may require package-specific
inputs or patches. Bun's [lifecycle rules](https://bun.com/docs/pm/lifecycle)
continue to determine which scripts run.

## Follow-up: Bun as `node` and standalone node-gyp

The initial automatic Node.js toolchain was too broad. It has been replaced:
`nodejs` defaults to `null`, and ordinary Bun builds do not acquire Node.js,
npm, or node-gyp. Native dependencies with prebuilt Node-API binaries continue
to work. Compilation through node-gyp opts into `bunNodeGypHook`.

Bun already creates a temporary `node` symlink for child scripts when Node.js is
absent. This is explicit in its pinned
[lifecycle environment setup](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/PackageManager.rs#L1357-L1383)
and [run-command PATH setup](https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/runtime/cli/run_command.rs#L2001-L2073).
Those temporary paths cannot serve as permanent installed shebangs and do not
modify the parent Nix builder's PATH. A small shared setup hook therefore adds a
store-path `node` symlink after stdenv finishes assembling PATH, only when no
`node` is available. It uses Bun's own CLI compatibility mode; it does not
implement a separate Node emulator. Tests verify real Node.js takes precedence
and patched executable shebangs refer to the persistent shim.

Nixpkgs' existing standalone node-gyp package still runs with Node.js, so it would
retain the dependency. Instead, [node-gyp.nix](./node-gyp.nix) packages upstream
node-gyp 13.1.0 from its npm tarball using the ordinary Bun builder and a committed
lockfile containing only runtime dependencies. Its executable wrapper invokes
Bun directly. A small gyp patch retains Nixpkgs' Darwin Xcode/CLT fallback.
[The headers package](./node-headers.nix) downloads the official header archive;
it does not build or reference a Node.js runtime. The native hook supplies these
packages and Python, with compiler tools coming from stdenv.

The existing C addon builds through both implicit `binding.gyp` and explicit
`node-gyp rebuild` paths using this toolchain. Its build-phase `node` command
identifies itself as Bun. A fresh sandboxed build also verifies its generated
Makefile uses the local header directory, with the header-download URL set to
an unusable localhost endpoint. A separate genuine-Node consumer loads the
resulting addon, and the untrusted-dependency test still prevents compilation.

Inspection of both build and runtime closures found no Node.js or npm package
in the example, standalone node-gyp, or native-addon build. Automated closure
checks guard the runtime closures and additionally reject node-gyp in the
ordinary example's closure. These checks are separate from the explicit Node.js
compatibility tests, which intentionally request a genuine Node.js runtime.

The native hook is also self-contained in `mkShell`: it propagates the shared
Bun/`node` fallback setup without registering package build/install phases. An
actual `nix develop` session containing only `bunNodeGypHook` successfully built
and loaded the C addon, including a `.gyp` command invoking `node`. The automated
`standalone-node-gyp-hook` check reproduces that case with `runCommandCC`, without
the config/build/install hooks. This catches the gap where Bun's temporary
child-script shim does not cover direct `node-gyp` use from a shell.

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

The follow-up review passed all 50 checks on each of `aarch64-darwin`,
`aarch64-linux`, and `x86_64-linux` (150 total). Local checks ran first; both
Linux suites used the configured `ssh://nix-builder`. Coverage now includes
explicit fetcher inputs, cache-path reuse across Bun changes, duplicate identical
Git URLs, a Windows-only optional dependency, and bearer-token registry fetching
followed by credential-free offline installation. The new Git and optional
fixtures also have independently fetched, same-hash caches on each system.
Overlay and standalone-scope examples/fetchers evaluated to identical derivations.
Nix formatting and shell syntax checks passed. The opt-in opencode build was
not repeated for this review.

Nix-update 1.16.0 successfully replaced an intentionally wrong `bunDepsHash`
using `--version=skip --custom-dep bunDeps` in a temporary package. The registry
test supplies public test credentials internally. A separate attempt to inject
a public token through client `impure-env` was rejected by this host's daemon
configuration because `configurable-impure-env` is not enabled there; no daemon
configuration was changed. Real credentials must be provisioned on the builder.

Earlier validation included builds on `aarch64-darwin`, `aarch64-linux`, and
`x86_64-linux`: 43 checks per system, 129 total. Both Linux suites ran through
the configured `ssh://nix-builder`,
whose sandbox setting is `relaxed`; these ordinary derivations do not request a
sandbox exemption. Native compilation/loading, source-independent workspace
execution, catalogs, JSONC, and dependency-cache checks run on all three systems.
The registry and Git/tarball/custom-registry caches reproduced their existing
hashes. The registry and Git/tarball caches also passed forced `nix-store
--realise --check` rebuilds directly on the Linux builder for both architectures
(four additional rebuild checks). A fresh Darwin native-addon build also passed
with `--option sandbox true`
and an unusable Node-header download URL. Cross compilation remains unsupported.

`nix flake check --all-systems` evaluates other systems but does not build their
checks on this host. To build every supported system's checks, including through
configured remote builders, use:

```sh
nix build --no-link --keep-going --impure --expr '
  let flake = builtins.getFlake (toString ./.);
  in builtins.concatLists (map
    (system: builtins.attrValues flake.checks.${system})
    (builtins.attrNames flake.checks))
'
```

During some native builds, the pinned Nixpkgs `audit-tmpdir` classifier subprocess
printed segmentation-fault diagnostics without failing the derivation. Native
runtime checks passed, as did the separate sandboxed build. Those checks do not
establish that the upstream audit classifier completed successfully.

## Follow-up: Nixpkgs PR #376299

Read [PR #376299](https://github.com/NixOS/nixpkgs/pull/376299) at head
`e920ea0f21805093691a9262a3ce8c0950cd6e05`, including all 52 available inline
threads (112 comments, including resolved/outdated threads), the 37 conversation
comments, and the submitted review summaries.

The PR has evolved beyond its original `bun install` cache fetcher. Its current
[Rust implementation](https://github.com/eveeifyeve/nixpkgs/blob/e920ea0f21805093691a9262a3ce8c0950cd6e05/pkgs/by-name/bu/bun/hooks/src/main.rs)
parses lockfiles, verifies tarballs, synthesizes registry metadata, and contains
HTTP-serving helpers. That is a different approach from fetching Bun's native
cache with `bun pm fetch`. The draft is not a demonstrated replacement for the
tested implementation here; in particular, its config hook still has archive
extraction/cache-copying code from the earlier approach. The review concerns
are useful independently of which fetching approach is chosen.

| Review concern | Resolution here |
| --- | --- |
| [Bun changes can be hidden by substituted FODs](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2754501190) | Revised after review: production cache paths stay stable across Bun version/derivation changes when name and content hash are unchanged. Evaluation checks cover both cases. Fresh-fetch test derivations still use `invalidateFetcherByDrvHash` to verify compatibility without forcing users to refetch. |
| [Changes to fetching must actually be tested](https://github.com/NixOS/nixpkgs/pull/376299#issuecomment-3941692200) | The cache checks now use `testers.invalidateFetcherByDrvHash`, so changed derivation inputs cannot pass merely by reusing a substituted output with the expected hash. Changing the serialized cache format still requires updating the format marker and expected hashes. |
| [Absolute symlinks](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2613671110) and [timestamped `.npm` manifests](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2751745200) | Internal absolute cache aliases are normalized. Fresh cache checks on every platform reject absolute links, top-level `.npm` manifests, and a materialized `node_modules`. The exercised locked fetches do not produce the timestamped manifests, so binary-offset timestamp edits are unnecessary. This establishes the fixture coverage, not every possible project/flag combination. |
| [Nondeterministic peer `.bin` links](https://github.com/NixOS/nixpkgs/pull/376299#issuecomment-4369911188) | `bun pm fetch` does not create `node_modules`, so those installation artifacts cannot enter the FOD. This avoids the reported source of dependency-cache hash variation. It does not establish that all ordinary Bun installations are reproducible; the reported browserslist dependency graph is not one of our fixtures. |
| [Fetch every platform](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2836378720) | Already done with `--os '*' --cpu '*' --libc '*'`, including optional packages for other operating systems. No maintained list of preferred platforms or extra platform-selection API is needed. Independent Linux/Darwin fetches validate the same recorded content hashes. |
| [JSONC parsing](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r1929315960) and [catalog resolution](https://github.com/NixOS/nixpkgs/pull/376299#issuecomment-3637361575) | Bun parses its lockfile; jq only reads ordinary package manifests. Added a fixture with explicit JSONC comments, trailing commas, default and named catalogs, and a workspace CLI that runs after source removal. Binary lockfile coverage also remains. |
| [Workspace installation](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2752943080) and [shared desktop/CLI dependencies](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2836138230) | Fetching covers the complete workspace lockfile. Selecting a build member does not restrict that cache or drop other workspace layouts during installation. Consumers can share `bunDeps` and perform separate installs; there is no need to share mutable, platform-specific `node_modules` between derivations. The opt-in opencode CLI integration below now exercises its shared dependency graph and web UI; the desktop executable remains untested. |
| [Hash mapping, naming, and flag API mismatches](https://github.com/NixOS/nixpkgs/pull/376299#issuecomment-4463917655) | `hash` maps to an actual recursive fixed-output hash, including after `overrideAttrs`. Added an evaluation regression for the override. Fetch and install flags have distinct documented names. `name` is used unchanged, without a Bun identity suffix; neither fetching nor consumption depends on an archive basename. |
| [Overridable inputs](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r1929994310) and [derivation extension](https://github.com/NixOS/nixpkgs/pull/376299#issuecomment-3939220032) | `buildBunPackage` already uses `lib.extendMkDerivation`. The smaller standalone fetcher retains `mkDerivation` with `finalAttrs`, as the pinned npm fetcher does, and now honors public hash/root/flag overrides. No additional constructor layer is needed for the tested API. |
| [Structured flags](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2838503828) | Hooks use stdenv `concatTo` and have a structured-array regression with spaces and literal glob characters. The fetcher preserves its Nix flag lists through explicit escaping of `finalAttrs`; its regression now actually uses a config filename containing spaces. This also supports unstructured callers. |
| [Hook placement](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r1929315598), [duplicate hook execution](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2838503397), and [commands versus arguments](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2655604648) | Config registration stays in `postPatchHooks`, matching the pinned npm hook and working with overridden configure phases. Shell hooks are invoked through `runHook`, not inlined as well. The fetcher regression asserts its `preInstall` runs once. Documentation uses an executable cache-patching command for `preBunInstall`, with flags in flag attributes. |
| [Required hook dependencies](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2793130104) | Each setup hook now propagates its selected Bun. The standalone-hook test omits an explicit Bun input. The installer retains `installShellFiles` and `makeWrapper`, with pinned absolute jq references. Native compilation tools are now an optional hook. |
| [Cache compression](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r1929997815), [archive tradeoffs](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2837704284), and [duplicate unpack/copy work](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2838978045) | Retain a recursively hashed directory. This avoids an additional compression/extraction pass, allows store deduplication, and uses the cache directly unless one writable copy is requested. Nix binary-cache transfers can compress NARs separately. The package-file archive used by the installer serves publication-file selection and is unrelated to dependency-cache serialization. |
| [Keep the public API small](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2838504530) | No separate OS/CPU lists, hash-algorithm switches, or legacy hash aliases were added. SHA-256 is the default, and an explicit SRI hash carries its own algorithm. `strictDeps` defaults to true. Standard derivation phase overrides remain available; configurable command flags are shared with the hooks rather than invented as fetcher-only aliases. |
| [Updater integration](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r2793137442), [helper placement](https://github.com/NixOS/nixpkgs/pull/376299#discussion_r3825776266), and [separate commits](https://github.com/NixOS/nixpkgs/pull/376299#issuecomment-2611626393) | Verified nix-update 1.16.0 with `--custom-dep bunDeps`: it rebuilt the dependency FOD with a blank hash and replaced an intentionally wrong literal `bunDepsHash`. A package can provide `nix-update-script { extraArgs = [ "--custom-dep" "bunDeps" ]; }`. Detection without this flag needs upstream nix-update support. An upstream submission should place these helpers under `pkgs/build-support/node`; the standalone overlay does not need that directory reshuffle. Follow-up changes have separate commits. |

The remaining resolved spelling, formatting, and unrelated package-conversion
threads do not require functional changes here. Native lifecycle execution
intentionally differs from the draft hook's unconditional `--ignore-scripts`:
the trusted/untrusted and node-gyp checks above verify the behavior we retain.

## Opt-in opencode integration

[tests/opencode.nix](./tests/opencode.nix) packages opencode 2.1.1 using
`buildBunPackage`, following the pinned nixpkgs derivation. It retains the
source hash, version/schema patches, workspace filters, disabled lifecycle
scripts, dependency-link normalization, build commands, wrappers, schemas,
shell completions, and installed version check. `wrapProgramBinary` explicitly
selects nixpkgs' binary wrapper alongside the builder's shell-wrapper helper.
The custom `node_modules` FOD and copy-based configure phase are replaced by
`bunDepsHash`, an offline install, and `postBunInstall` normalization.

No changes to the builder or fetcher were needed. Bun 1.4.4 rejected the final
hunk of upstream's Photon dependency patch: its context lines have an extra
space. The cached JavaScript matched the original npm tarball byte for byte,
and the original patch also failed `git apply --check`. Correcting only those
context lines made the patch apply and the sandboxed offline install succeed.

Validation completed on `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`.
All three independently fetched caches produced
`sha256-UwD/nWCZFMLP1QFTzJcpyFNjVu6WQYceEnvB9ys9W6g=`. All package builds passed,
including the embedded web UI, JSON schemas, shell completions, and installed
version checks. Darwin ran with `--option sandbox true`; Linux used the
configured sandboxed remote builder. The Darwin schemas were additionally
parsed as JSON and all three completion files checked for nonempty contents.
The Darwin executable was launched interactively with an isolated temporary
home and project, an empty credential environment, and `--standalone`: the
start screen rendered, Ctrl+P opened the command palette, and Ctrl+C exited
with status 0. No model request was submitted.

This is a large, explicit integration target: `nix build .#opencode`. It is
excluded from the default flake checks on every system. The all-platform cache
contains 2,554 fetched packages and occupies about 8.2 GB on Darwin, because
`bun pm fetch` fetches the full lockfile even though installation filters the
workspaces. A writable cache copy adds temporary storage use. Simultaneous
Linux builds exhausted the builder's 19 GB temporary filesystem; retrying the
x86 build by itself passed. Prefer sequential builds on constrained builders.

## Smaller real-world integration: swagger-typescript-api

[tests/swagger-typescript-api.nix](./tests/swagger-typescript-api.nix) builds
13.13.0 from the pinned nixpkgs source with no custom configure, build, or
install phase. The default hooks perform the offline install, `bun run build`,
production pruning, package-file selection, and executable wrapping. This
replaces the bespoke `node_modules` FOD, manual dependency copying, and Node.js
wrapper in nixpkgs. `makeWrapperArgs` retains its production `NODE_ENV`.
Neither Node.js nor npm occurs in the build or runtime dependency closure.
No changes to the hooks were needed, and a writable cache was unnecessary.

The Darwin package passed with `--option sandbox true`, including the installed
version check and smoke checks for `--help` and `generate --help`. The help
output showed the expected commands and OpenAPI input options. Templates were
present in the installed package and the `tsdown` development dependency was
pruned. Upstream's build tool rewrites the manifest to expose only the
`swagger-typescript-api` bin, which matches the executable installed by nixpkgs.
No API client generation or full upstream test suite was run. Flake evaluation
passed for all three supported systems; Linux builds were not run for this test.

This package is available as `nix build .#swagger-typescript-api` and included in
the default flake checks. Its all-platform cache contains 405 fetched packages
and has a NAR size of approximately 1.54 GiB; fetching took about 75 seconds in
this run. The cache hash is
`sha256-eqt/OddO/yJvexnR6wesc1EZtvbOxXKp+xmpZgF79kQ=`. Opencode remains excluded
from the default checks.
