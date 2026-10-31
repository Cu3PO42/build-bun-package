# shellcheck shell=bash
# prefix, output, and outputDev are supplied by stdenv's output fixup.
# shellcheck disable=SC2154

# Work around patchShebangs leaving an absolute command after env -S untouched,
# even with --update. Ordinary shebangs are handled by stdenv itself. This helper
# can be removed when upstream supports repatching env -S commands.
bunFixupEnvSplitShebangs() {
    if [[ -n ${dontPatchShebangs-} || ! -e $prefix || -z ${bunBuildRuntimeBin-} ]]; then
        return
    fi
    local file line timestamp node=@runtimeNodeShim@/bin/node
    if [[ $output != out && $output == "$outputDev" ]]; then
        node=@buildRuntimeNodeShim@/bin/node
    fi
    while IFS= read -r -d "" file; do
        isScript "$file" || continue
        IFS= read -r line <"$file" || [[ -n $line ]]
        if [[ $line == '#!'*'/bin/env -S '"$bunBuildRuntimeBin/node"* ]]; then
            timestamp=$(stat --printf '%y' "$file")
            line=${line//"$bunBuildRuntimeBin/node"/"$node"}
            line=${line//\\/\\\\}
            sed -i "1c\\$line" "$file"
            touch --date "$timestamp" "$file"
        fi
    done < <(find "$prefix" -type f -perm -0100 ! -name bun.lockb -print0)
}

fixupOutputHooks=(bunFixupEnvSplitShebangs "${fixupOutputHooks[@]}")
