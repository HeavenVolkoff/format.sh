#!/usr/bin/env bash

# --- Command Interpreter Configuration ----------------------------------------

# Command Interpreter Configuration
set -e          # exit immediate if an error occurs in a pipeline
set -u          # don't allow not set variables to be utilized
set -o pipefail # trace ERR through pipes
set -o errtrace # trace ERR through 'time command' and other functions
# set -x # Debug this shell script
# set -n # Check script syntax, without execution.

# ----- Read only properties ---------------------------------------------------
readonly __pwd="$(pwd)"
readonly __dir=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
readonly __file="${__dir}/$(basename -- "$0")"
readonly __base="$(basename "${__file}" .sh)"
readonly __root="$(cd "$(dirname "${__dir}")" && pwd)"
__return=""

read_config() {
    if [ -f "./.editorconfig" ]; then
        # shellcheck disable=SC2005
        echo "$("$__dir/read_config.py" "./.editorconfig" "$1" "$2")"
    else
        echo ""
    fi
}

process_py() {
    local black_config
    local import_sorted

    if ! { hash isort && hash black; } 2>/dev/null; then
        echo >&2 "Python: isort or black is not installed"
        return 1
    fi

    import_sorted="$(isort -q -ac "$1" -d)"
    if [ -z "$import_sorted" ]; then
        import_sorted="$(cat "$1")"
    else
        if echo "$import_sorted" | grep -q "^ERROR:"; then
            echo "$import_sorted" >&2
            exit 1
        fi
    fi

    black_config="$(read_config "**.py" black_file)"
    if [ -n "$black_config" ]; then
        black_config="--config $black_config"
    fi

    __return="$(echo "$import_sorted" | black $black_config - 2>/dev/null)"

    return 0
}

process_sh() {
    local minify
    local ident_case
    local indent_size
    local binary_start
    local keep_padding
    local space_redirect
    local language_variant

    if ! hash shfmt; then
        echo >&2 "Bash: shfmt is not installed"
        exit 1
    fi

    language_variant="$(read_config "**.sh" language_variant)"
    if [ -n "$language_variant" ]; then
        language_variant="-ln $language_variant"
    fi

    indent_size="$(read_config "**.sh" indent_size)"
    if [ -n "$indent_size" ]; then
        indent_size="-i $indent_size"
    fi

    binary_start="$(read_config "**.sh" binary_start)"
    if [ "$binary_start" == "true" ]; then
        binary_start="-bn"
    fi

    ident_case="$(read_config "**.sh" ident_case)"
    if [ "$ident_case" == "true" ]; then
        ident_case="-ci"
    fi

    space_redirect="$(read_config "**.sh" space_redirect)"
    if [ "$space_redirect" == "true" ]; then
        space_redirect="-sr"
    fi

    keep_padding="$(read_config "**.sh" keep_padding)"
    if [ "$keep_padding" == "true" ]; then
        keep_padding="-kp"
    fi

    minify="$(read_config "**.sh" minify)"
    if [ "$minify" == "true" ]; then
        minify="-mn"
    fi

    __return="$(shfmt $language_variant $indent_size $binary_start $ident_case $space_redirect $keep_padding $minify "$1")"

    return 0
}

if [ "$#" -lt "1" ]; then
    echo >&2 "Missing argument"
    exit 1
fi

for file in "$@"; do
    if ! [ -f "$file" ]; then
        echo >&2 "$file: Doesn't exist"
        continue
    fi

    file="$(realpath --relative-to="$__pwd" "$file")"
    filename="$(basename -- "$file")"
    file_ext="${filename##*.}"

    process="process_${file_ext}"
    if ! type "$process" 1>/dev/null 2>&1; then
        echo >&2 "$file:"
        echo >&2 "  Doesn't have a recognizable extension"
        continue
    fi

    if [ -s "$file" ]; then
        if $process "$file" && [ -n "$__return" ]; then
            formatted="$__return"
        else
            echo >&2 "$file:"
            echo >&2 "  Failed to formatted"
            continue
        fi
    else
        echo >&2 "$file:"
        echo >&2 "  Is empty"
        continue
    fi

    echo "$formatted" >"$file"
    echo >&2 "$file:"
    echo >&2 "  Formatted"
done
