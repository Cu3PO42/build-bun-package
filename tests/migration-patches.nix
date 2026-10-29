{ pkgs }:
{
  migration-manifest-patches =
    pkgs.runCommand "bun-migration-manifest-patches"
      {
        nativeBuildInputs = [
          pkgs.jd-diff-patch
          pkgs.jq
        ];
      }
      ''
        helper=${../pkgs/build-support/migrate-lock.sh}
        mkdir -p source/workspace source/node_modules source/.git cache/.nix-bun
        cd source
        echo '{"dependencies":{"escaped/name~":"portal:./local"},"trustedDependencies":["a","b"],"obsolete":true}' > package.json
        echo '{"name":"workspace","dependencies":{"local":"portal:../local"}}' > workspace/package.json
        # These are deliberately invalid JSON and must not be inspected.
        echo ignored > node_modules/package.json
        echo ignored > .git/package.json
        echo foreign-lock > yarn.lock
        cp -R . ../original
        bash "$helper" snapshot "$TMPDIR/snapshot"
        jq 'del(.obsolete) | .trustedDependencies = ["b","c"] | .dependencies["escaped/name~"] = "file:./local"' package.json > updated
        mv updated package.json
        jq '.dependencies.local = "file:../local"' workspace/package.json > updated
        mv updated workspace/package.json
        echo generated-lock > ../cache/.nix-bun/bun.lock
        bash "$helper" record "$TMPDIR/snapshot" "$TMPDIR/cache/.nix-bun/migration"
        cp -R . ../expected
        cd ..

        cp -R original build
        cd build
        jq '.description = "build-only"' package.json > updated
        mv updated package.json
        jq '.scripts.build = "echo build-only"' workspace/package.json > updated
        mv updated workspace/package.json
        bash "$helper" apply "$TMPDIR/cache"
        jq -e '.description == "build-only"' package.json
        jq -e '.scripts.build == "echo build-only"' workspace/package.json
        jd <(jq 'del(.description)' package.json) ../expected/package.json
        jd <(jq 'del(.scripts)' workspace/package.json) ../expected/workspace/package.json
        cmp bun.lock ../cache/.nix-bun/bun.lock
        cd ..

        cp -R original conflict
        cd conflict
        jq '.dependencies.local = "file:../different"' workspace/package.json > updated
        mv updated workspace/package.json
        cp -R . ../before-conflict
        if bash "$helper" apply "$TMPDIR/cache" > log 2>&1; then
          echo "Expected a workspace conflict" >&2
          exit 1
        fi
        grep -F 'conflicting migration and patch edits in workspace/package.json' log
        cmp package.json ../before-conflict/package.json
        cmp workspace/package.json ../before-conflict/workspace/package.json
        test ! -e bun.lock
        touch "$out"
      '';
}
