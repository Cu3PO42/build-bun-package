# shellcheck shell=bash

# Work around patchShebangs leaving an absolute command after env -S untouched,
# even with --update. Resolve the command by basename, as patchShebangs does for
# ordinary shebangs. Remove this helper when upstream supports this case.
bunFixupEnvSplitShebangs() {
    local searchPath=$1 prefix=$2
    local file line timestamp interpreter split command args newCommand newInterpreter newLine
    while IFS= read -r -d "" file; do
        isScript "$file" || continue
        IFS= read -r line <"$file" || [[ -n $line ]]
        read -r interpreter split command args <<<"${line:2}"
        [[ $interpreter == */bin/env && $split == -S && $command == /* ]] || continue
        newCommand=$(PATH="$searchPath" type -P "${command##*/}" || true)
        [[ -n $newCommand ]] || continue
        newInterpreter=$(PATH="$searchPath" type -P env || true)
        newLine="#!${newInterpreter:-$interpreter} -S $newCommand${args:+ $args}"
        [[ $newLine != "$line" ]] || continue
        timestamp=$(stat --printf '%y' "$file")
        newLine=${newLine//\\/\\\\}
        sed -i "1c\\$newLine" "$file"
        touch --date "$timestamp" "$file"
    done < <(find "$prefix" -type f -perm -0100 ! -name bun.lockb -print0)
}
