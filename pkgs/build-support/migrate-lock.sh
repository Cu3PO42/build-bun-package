# shellcheck shell=bash
set -euo pipefail

# Keep both presence and contents: an added lockfile can change Bun's selection.
inputs=(npm-shrinkwrap.json package-lock.json yarn.lock pnpm-lock.yaml pnpm-workspace.yaml .yarnrc.yml)

fail() {
    echo "bunMigrateHook: $*; regenerate bunDepsHash or update bunDeps" >&2
    exit 1
}

case "$1" in
    snapshot)
        snapshot=$2
        mkdir -p "$snapshot/inputs" "$snapshot/manifests"
        for file in "${inputs[@]}"; do
            if [[ -f $file ]]; then cp "$file" "$snapshot/inputs/$file"; fi
        done
        while IFS= read -r -d '' file; do
            mkdir -p "$snapshot/manifests/$(dirname "$file")"
            cp "$file" "$snapshot/manifests/$file"
        done < <(find . -type d \( -name node_modules -o -name .git \) -prune -o -type f -name package.json -print0)
        ;;
    record)
        snapshot=$2
        migration=$3
        mkdir -p "$migration/patches"
        cp -R "$snapshot/inputs" "$migration/inputs"
        printf '1\n' >"$migration/version"
        while IFS= read -r -d '' original; do
            file=${original#"$snapshot/manifests/"}
            # jd returns 1 for differences, 0 for equality, and >1 for errors.
            status=0
            jd -f patch "$original" "$file" >"$snapshot/patch.json" || status=$?
            case "$status" in
                0) continue ;;
                1) ;;
                *) fail "cannot record migration edits for $file" ;;
            esac
            mkdir -p "$migration/patches/$(dirname "$file")"
            cp "$snapshot/patch.json" "$migration/patches/$file"
        done < <(find "$snapshot/manifests" -type f -name package.json -print0 | sort -z)
        ;;
    apply)
        metadata=$2/.nix-bun
        migration=$metadata/migration
        if [[ ! -f $migration/version ]] || [[ $(cat "$migration/version") != 1 ]]; then
            fail "unsupported migration metadata version"
        fi
        for file in "${inputs[@]}"; do
            if [[ -f $migration/inputs/$file ]]; then
                cmp -s "$migration/inputs/$file" "$file" || fail "migration input $file differs from cache"
            elif [[ -e $file ]]; then
                fail "migration input $file differs from cache"
            fi
        done
        if [[ -e bun.lockb ]] || { [[ -e bun.lock ]] && ! cmp -s "$metadata/bun.lock" bun.lock; }; then
            fail "existing Bun lockfile differs from migrated cache"
        fi
        # Use jd for both generation and application: its RFC 6902 subset checks
        # old values, including absence for additions. Other appliers may overwrite.
        # Stage every result before touching source manifests, so conflicts cannot
        # leave some workspaces migrated and others unchanged.
        updates=$(mktemp -d)
        trap 'rm -rf "$updates"' EXIT
        while IFS= read -r -d '' patch; do
            file=${patch#"$migration/patches/"}
            mkdir -p "$updates/$(dirname "$file")"
            jd -f patch -p "$patch" "$file" >"$updates/$file" || fail "conflicting migration and patch edits in $file"
        done < <(find "$migration/patches" -type f -name package.json -print0 | sort -z)
        while IFS= read -r -d '' updated; do
            file=${updated#"$updates/"}
            cp "$updated" "$file"
        done < <(find "$updates" -type f -name package.json -print0)
        cp "$metadata/bun.lock" bun.lock
        ;;
    *) fail "unknown migration operation: $1" ;;
esac
