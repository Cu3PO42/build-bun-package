{
  lib,
  runCommand,
  fetchurl,
  fetchgit,
  fetchGit ? builtins.fetchGit,
  bun,
  bunHooks,
  writeText,
}:

let
  importBunLock =
    {
      src,
      bunRoot ? ".",
      lockFile ? src + "/${bunRoot}/bun.lock",
      name ? "imported-bun-deps",
      registry ? "https://registry.npmjs.org",
      scopedRegistries ? { },
      fetcherOpts ? { },
    }:

    assert lib.assertMsg (lib.versionAtLeast bun.version "1.4.4") "importBunLock requires Bun >= 1.4.4";
    let
      fail = message: throw "importBunLock: ${message}";
      validIntegrity =
        hash:
        builtins.isString hash
        && builtins.match "(sha1|sha256|sha384|sha512)-[A-Za-z0-9+/]+=*" hash != null;
      lock =
        if builtins.pathExists lockFile then
          import ./jsonc.nix (builtins.readFile lockFile)
        else
          fail "a text bun.lock is required at ${toString lockFile}; convert bun.lockb with Bun first";
      validLock =
        builtins.isAttrs lock
        && builtins.elem (lock.lockfileVersion or null) [
          0
          1
          2
          3
        ]
        && builtins.isAttrs (lock.packages or null)
        && builtins.isAttrs (lock.workspaces or null);
      packages =
        lib.mapAttrsToList
          (
            key: entry:
            let
              validEntry = builtins.isList entry && entry != [ ] && builtins.isString (builtins.head entry);
              resolved =
                if validEntry then builtins.match "(@[^/]+/[^@]+|[^@]+)@(.+)" (builtins.head entry) else null;
              packageName = builtins.elemAt resolved 0;
              version = builtins.elemAt resolved 1;
              length = builtins.length entry;
              npm =
                length == 4
                && builtins.isString (builtins.elemAt entry 1)
                && builtins.isAttrs (builtins.elemAt entry 2);
              tarball = builtins.match "https?://.+" version != null;
              github = builtins.match "github:([^/]+)/([^#]+)#(.+)" version;
              git = builtins.match "git\\+(.+)(#.*)?" version;
              workspace = lib.hasPrefix "workspace:" version;
              local = builtins.match "(link:|file:|root:).*" version != null;
              # Text locks serialize tarballs as paths, without the manifest's
              # file: prefix. A file: resolution always denotes a directory.
              localTarball =
                !tarball
                && !local
                && git == null
                && github == null
                && builtins.match ".*\\.(tgz|tar\\.gz|tar)$" (lib.toLower version) != null;
              scope = builtins.head (lib.splitString "/" packageName);
              packageRegistry = lib.removeSuffix "/" (scopedRegistries.${scope} or registry);
              opts = fetcherOpts.${key} or { };
              integrity =
                if npm then
                  builtins.elemAt entry 3
                else if github != null && length == 4 then
                  builtins.elemAt entry 3
                else if tarball && length == 3 then
                  builtins.elemAt entry 2
                else
                  "";
              hash =
                if validIntegrity integrity then
                  integrity
                else if integrity == "" then
                  opts.hash or (fail "package '${key}' has no integrity; supply fetcherOpts.${key}.hash")
                else
                  fail "package '${key}' needs a supported integrity hash in bun.lock";
              gitRev = opts.rev or (builtins.elemAt entry 2);
            in
            if resolved == null then
              fail "malformed package entry '${key}'"
            else if
              (workspace && (length == 1 || (length == 2 && builtins.isAttrs (builtins.elemAt entry 1))))
              || (local && length == 2 && builtins.isAttrs (builtins.elemAt entry 1))
              || (localTarball && (length == 2 || length == 3) && builtins.isAttrs (builtins.elemAt entry 1))
            then
              null
            else if
              git != null && (length == 3 || length == 4) && builtins.isAttrs (builtins.elemAt entry 1)
            then
              if
                !builtins.isString gitRev || builtins.match "([0-9a-fA-F]{40}|[0-9a-fA-F]{64})" gitRev == null
              then
                fail "Git package '${key}' needs a full locked commit or fetcherOpts.${key}.rev"
              else
                {
                  inherit key packageName;
                  kind = "git";
                  url = import ./normalize-git-url.nix (
                    builtins.head (lib.splitString "#" (lib.removePrefix "git+" version))
                  );
                  rev = gitRev;
                  integrity = null;
                }
            else if
              (npm && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+.*" version != null)
              || (tarball && (length == 2 || length == 3) && builtins.isAttrs (builtins.elemAt entry 1))
              || (github != null && (length == 3 || length == 4) && builtins.isAttrs (builtins.elemAt entry 1))
            then
              {
                inherit key packageName;
                kind = if npm then "npm" else "tarball";
                url =
                  if github != null then
                    "https://codeload.github.com/${builtins.elemAt github 0}/${builtins.elemAt github 1}/legacy.tar.gz/${builtins.elemAt github 2}"
                  else if tarball then
                    version
                  else if builtins.elemAt entry 1 != "" then
                    builtins.elemAt entry 1
                  else
                    "${packageRegistry}/${packageName}/-/${lib.last (lib.splitString "/" packageName)}-${version}.tgz";
                inherit hash;
                integrity = if validIntegrity hash then hash else null;
              }
            else
              fail "unsupported or malformed source for package '${key}' (${version})"
          )
          (
            if validLock then
              lock.packages
            else
              fail "expected a bun.lock with lockfileVersion 0–3, workspaces, and packages"
          );
      entries = lib.imap0 (index: entry: {
        inherit (entry)
          key
          kind
          packageName
          integrity
          ;
        rev = entry.rev or null;
        id = toString index;
        path =
          if entry.kind != "git" then
            fetchurl ({ inherit (entry) url hash; } // (fetcherOpts.${entry.key} or { }))
          else
            let
              opts = {
                inherit (entry) url rev;
              }
              // (fetcherOpts.${entry.key} or { });
              checkout = if opts ? hash then fetchgit opts else fetchGit ({ allRefs = true; } // opts);
            in
            checkout;
      }) (builtins.filter (entry: entry != null) packages);
      manifest = writeText "bun-sources.json" (builtins.toJSON entries);
    in
    builtins.deepSeq packages (
      runCommand name
        {
          strictDeps = true;
          dontFixup = true;
          passthru.isBunSourceBundle = true;
        }
        ''
          mkdir -p "$out/.nix-bun" "$out/tarballs" "$out/checkouts"
          printf 'source-bundle\n' > "$out/.nix-bun/format"
          printf '1\n' > "$out/.nix-bun/format-version"
          cp ${lockFile} "$out/.nix-bun/bun.lock"
          cp ${manifest} "$out/sources.json"
          ${lib.concatMapStringsSep "\n" (
            entry:
            if entry.kind == "git" then
              ''ln -s ${entry.path} "$out/checkouts/${entry.id}"''
            else
              ''ln -s ${entry.path} "$out/tarballs/${entry.id}.tgz"''
          ) entries}
        ''
    );
in
{
  __functor = _: importBunLock;
  bunConfigHook = bunHooks.bunImportConfigHook;
}
