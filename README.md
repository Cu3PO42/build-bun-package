<h1 align="center">bunflake</h1>
<p align="center">
  <code>buildNpmPackage</code>, but for Bun!
</p>
<p align="center">
  <img src="./logo.png" alt="bunflake: a smiling bun shaped like a snowflake with blue crystal accents." width="280">
</p>
<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="./docs/packaging.md">Packaging guide</a> ·
  <a href="./docs/reference.md">Reference</a> ·
  <a href="./CONTRIBUTING.md">Contributing</a>
</p>

bunflake packages Bun applications and scripts for Nix through `buildBunPackage`,
with an interface modeled on Nixpkgs' `buildNpmPackage`. It fetches locked
dependencies separately and installs them offline during the package build.

## Status

`buildBunPackage` is feature-complete and has been used to package real-world
applications with Bun's native lockfiles. `importBunLock` and migration from
other package managers' lockfiles are experimental and have more limited validation.

The project is young and its public interface may change between updates.
It is designed with possible upstreaming to Nixpkgs in mind, but there is
currently no commitment to long-term maintenance.

Bun 1.4.4 or newer is required. Supported systems are `aarch64-darwin`,
`aarch64-linux`, and `x86_64-linux`; cross compilation is not supported.
Bun updates may change the dependency cache format and require a new hash.

## AI disclosure

This code was written primarily by LLMs (mostly GPT-6.1 Sol) under my direction.
The end goal is to have all code (except possibly tests) reviewed by me (a human).
This is already true for the core logic and as of a prior state it was true for all code, but additional work has introduced new, not fully reviewed code.
I aim to review and clean this up soon.

The documentation is also at least partially written by AI.

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

The [packaging guide](./docs/packaging.md) explains workflows with examples.
The [reference](./docs/reference.md) defines public interfaces, defaults, and hook
contracts. Start with the topic you need:

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

Real-world packages live in [`integration/`](./integration). The
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
