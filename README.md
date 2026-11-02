<h1 align="center">bunflake</h1>
<p align="center">
  <code>buildNpmPackage</code>, but for Bun!
</p>
<p align="center">
  <img src="./logo.png" alt="bunflake: a smiling bun, inspired by the Bun logo, shaped like a snowflake with blue crystal wrapping paper." width="280">
</p>
<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="./docs/packaging.md">Packaging guide</a> ·
  <a href="./docs/reference.md">Reference</a> ·
  <a href="./CONTRIBUTING.md">Contributing</a>
</p>

bunflake packages Bun applications and scripts for Nix through `buildBunPackage`,
with an interface modeled on Nixpkgs' `buildNpmPackage`.

## Status

`buildBunPackage` is mostly feature-complete and has been used to package
real-world applications. Its most mature workflow fetches dependencies from a
Bun lockfile in a fixed-output derivation, then installs them offline during the
application build. Migration from npm, Yarn, and pnpm lockfiles is also supported
experimentally.

The experimental `importBunLock` offers an alternative: it fetches each dependency
individually using its locked hash or commit, allowing fetcher overrides without
an aggregate dependency hash.

The project is young and its public interface may change between updates.
It is designed with possible upstreaming to Nixpkgs in mind, but there is
currently no commitment to long-term maintenance.

Bun 1.4.4 or newer is required. Supported systems are `aarch64-darwin`,
`aarch64-linux`, and `x86_64-linux`; cross compilation is not supported.

Since Bun 1.4.4 is the newest version (and bundled in this Flake) at time of writing, we do not yet know if future updates may change cache formats and invalidate hashes.

## AI disclosure

This code was written primarily by LLMs (mostly GPT-6.1 Sol) under my direction.
Most code outside of tests has been carefully reviewed by me (a human).
I strive to close the gap.

The documentation is also partially written by AI.

## Quick start

Create a `flake.nix` alongside your application's `package.json` and committed
`bun.lock` or `bun.lockb`. No overlay is required:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bunflake.url = "github:Cu3PO42/build-bun-package";
  };

  outputs =
    { nixpkgs, bunflake, ... }:
    let
      system = "x86_64-linux"; # Change to your supported system.
    in
    {
      packages.${system}.my-app = bunflake.legacyPackages.${system}.buildBunPackage {
        pname = "my-app";
        version = "1.0.0";
        src = ./.;
        bunDepsHash = nixpkgs.lib.fakeHash;
      };
    };
}
```

In a Git repository, make sure the flake, manifests, lockfile, and application
sources are tracked so Nix includes them. Then build:

```sh
nix build .#my-app
```

The first build reports a dependency hash mismatch. Replace `nixpkgs.lib.fakeHash`
with the quoted `sha256-…` hash from the `got:` line, then build again. Repeat this
when dependencies change. To fetch only dependencies, use
`nix build .#my-app.bunDeps`.

By default, the builder installs dependencies offline with lifecycle scripts
disabled, runs `bun run build`, and installs publishable files and production
dependencies. Executables declared in `package.json` receive Bun wrappers;
declared manual pages are installed too. For a package without a build script,
add `dontBunBuild = true;`.

## Documentation

The [packaging guide](./docs/packaging.md) builds on the quick start with
explanations and examples for more involved packages. The
[reference](./docs/reference.md) defines public interfaces and contracts. Start
with the topic you need:

| Task | Documentation |
| --- | --- |
| Use an overlay or individual hooks | [Package-set integration](./docs/reference.md#package-set-integration) |
| Package a workspace or nested project | [Workspaces](./docs/packaging.md#workspaces-and-nested-projects) |
| Run tests or install a bundle/static site | [Build and install customization](./docs/packaging.md#build-and-install-customization) |
| Enable scripts, use Node.js, or compile addons | [Lifecycle scripts and native dependencies](./docs/packaging.md#lifecycle-scripts-and-native-dependencies) |
| Choose a dependency fetcher or migrate a lockfile | [Dependency fetching](./docs/packaging.md#dependency-fetching) |
| Fetch private dependencies | [Private registries](./docs/packaging.md#private-registries) |
| Update a package and its dependency hash | [Updating packages](./docs/packaging.md#updating-packages) |
| Understand cache formats and installation stages | [Design](./docs/design.md) |
| Run checks or update bundled tools | [Contributing](./CONTRIBUTING.md) |

## Examples

Real-world packages live in [`integration/`](./integration). They are derived
from Nixpkgs packages and simplified using our build support. The
[swagger-typescript-api example](./integration/swagger-typescript-api.nix) uses
the default build and install hooks; [opencode](./integration/opencode.nix)
shows workspace filtering, dependency patches, and custom installation.

Build an example for your current system, or fetch just its dependencies:

```sh
nix build .#example-filen-cli
nix build .#example-opencode.bunDeps
```

See the [flake outputs](./docs/reference.md#package-set-integration) for how
examples and helpers are exposed.
