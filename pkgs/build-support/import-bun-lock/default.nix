{
  lib,
  runCommand,
  fetchurl,
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
              workspace = lib.hasPrefix "workspace:" version;
              local = builtins.match "(link:|file:).*" version != null;
              localTarball = builtins.match "file:.*\\.(tgz|tar\\.gz|tar)$" version != null;
              scope = builtins.head (lib.splitString "/" packageName);
              packageRegistry = lib.removeSuffix "/" (scopedRegistries.${scope} or registry);
              integrity = if npm then builtins.elemAt entry 3 else builtins.elemAt entry 2;
            in
            if resolved == null then
              fail "malformed package entry '${key}'"
            else if
              (workspace && (length == 1 || (length == 2 && builtins.isAttrs (builtins.elemAt entry 1))))
              || (local && !localTarball && length == 2 && builtins.isAttrs (builtins.elemAt entry 1))
            then
              null
            else if
              (npm && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+.*" version != null)
              || (tarball && length == 3 && builtins.isAttrs (builtins.elemAt entry 1))
            then
              if
                !builtins.isString integrity
                || builtins.match "(sha1|sha256|sha384|sha512)-[A-Za-z0-9+/]+=*" integrity == null
              then
                fail "package '${key}' needs a supported integrity hash in bun.lock"
              else
                {
                  inherit key packageName;
                  kind = if npm then "npm" else "tarball";
                  url =
                    if tarball then
                      version
                    else if builtins.elemAt entry 1 != "" then
                      builtins.elemAt entry 1
                    else
                      "${packageRegistry}/${packageName}/-/${lib.last (lib.splitString "/" packageName)}-${version}.tgz";
                  hash = integrity;
                }
            else
              fail "unsupported source for package '${key}' (${version}); use fetchBunDeps for Git or local tarball dependencies"
          )
          (
            if validLock then
              lock.packages
            else
              fail "expected a bun.lock with lockfileVersion 0–3, workspaces, and packages"
          );
      entries = lib.imap0 (index: entry: {
        inherit (entry) key kind packageName;
        id = toString index;
        path = fetchurl ({ inherit (entry) url hash; } // (fetcherOpts.${entry.key} or { }));
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
          mkdir -p "$out/.nix-bun" "$out/tarballs"
          printf '2\n' > "$out/.nix-bun/format-version"
          cp ${lockFile} "$out/.nix-bun/bun.lock"
          cp ${manifest} "$out/sources.json"
          ${lib.concatMapStringsSep "\n" (
            entry: ''ln -s ${entry.path} "$out/tarballs/${entry.id}.tgz"''
          ) entries}
        ''
    );
in
{
  __functor = _: importBunLock;
  bunConfigHook = bunHooks.bunImportConfigHook;
}
