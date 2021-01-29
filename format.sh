#!/usr/bin/env bash

# --- Command Interpreter Configuration ----------------------------------------

# Command Interpreter Configuration
set -e # exit immediate if an error occurs in a pipeline
set -u # don't allow not set variables to be utilized
set -o pipefail # trace ERR through pipes
set -o errtrace # trace ERR through 'time command' and other functions
# set -x # Debug this shell script
# set -n # Check script syntax, without execution.

# ----- Read only properties ---------------------------------------------------
readonly __pwd="$(pwd)"
readonly __dir=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
readonly __file="${__dir}/$(basename -- "$0")"

command -v realpath >/dev/null 2>&1 || realpath() { python -c "import os; print(os.path.realpath('$1'))"; }

# From https://stackoverflow.com/q/11027679#answer-41069638
catch() {
    eval "$({
        __2="$(
            { __1="$("${@:3}")"; } 2>&1
            ret=$?
            printf '%q=%q\n' "$1" "$__1" >&2
            exit $ret
        )"
        ret="$?"
        printf '%s=%q\n' "$2" "$__2" >&2
        printf '( exit %q )' "$ret" >&2
    } 2>&1)"
}

# Modified from http://stackoverflow.com/a/12498485
relativePath() {
    # both $1 and $2 are absolute paths beginning with /
    # returns relative path to $2 from $1
    local source="$1"
    local target="$2"

    local commonPart="$source"
    local result=""

    while [ "${target#$commonPart}" == "${target}" ]; do
        # no match, means that candidate common part is not correct
        # go up one level (reduce common part)
        commonPart="$(dirname "$commonPart")"
        # and record that we went back, with correct / handling
        if [[ -z "$result" ]]; then
            result=".."
        else
            result="../$result"
        fi
    done

    if [ "$commonPart" == "/" ]; then
        # special case for root (no common path)
        result="$result/"
    fi

    # since we now have identified the common part,
    # compute the non-common part
    local forwardPart="${target#$commonPart}"

    # and now stick all parts together
    if [ -n "$forwardPart" ]; then
        if [ -n "$result" ]; then
            result="$result$forwardPart"
        else
            # extra slash removal
            result="${forwardPart#?}"
        fi
    fi

    echo "$result"
}

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

    if [ -f '.venv/bin/activate' ]; then
        source .venv/bin/activate
    fi

    if ! { hash isort && hash black; } 2>/dev/null; then
        echo "Python: isort or black is not installed" >&2
        return 1
    fi

    imported_clean="$(sed -r '/^# (Internal|Standard|External|Indirect|Project)$/d' "$1")"
    import_sorted="$(echo "$imported_clean" | isort -d --quiet --atomic -)"
    if [ -z "$import_sorted" ]; then
        import_sorted="$imported_clean"
    else
        if echo "$import_sorted" | grep -q "^ERROR:"; then
            echo "$import_sorted" >&2
            return 1
        fi
    fi

    black_config="$(read_config "**.py" black_file)"
    if [ -f "$black_config" ]; then
        black_config="--config $black_config"
    fi

    echo "$import_sorted" | black $black_config - 2>/dev/null
}

process_pyi() {
    process_py "$@"
}

process_sh() {
    local minify
    local ident_case
    local indent_size
    local binary_start
    local keep_padding
    local space_redirect
    local language_variant

    if ! hash shfmt 2>/dev/null; then
        echo "Bash: shfmt is not installed" >&2
        return 1
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

    shfmt $language_variant $indent_size $binary_start $ident_case $space_redirect $keep_padding $minify "$1"
}

main_loop() {
    local file=$1

    if ! [ -f "$file" ]; then
        cat <<EOF  >&2
${file}:
  Doesn't exist
EOF
        return 1
    fi

    file="$(relativePath "$__pwd" "$(realpath "$file")")"
    filename="$(basename -- "$file")"
    file_ext="${filename##*.}"

    process="process_${file_ext}"
    if ! type "$process" 1>/dev/null 2>&1; then
        cat <<EOF  >&2
${file}:
  Doesn't have a recognizable extension
EOF
        return 1
    fi

    if ! [ -s "$file" ]; then
        cat <<EOF  >&2
${file}:
  Is empty
EOF
    elif catch content error "$process" "$file" && [ -n "$content" ] && [ -z "$error" ]; then
        echo "$content" >"$file"
            cat <<EOF  >&2
${file}:
  Formatted
EOF
    else
        cat <<EOF  >&2
${file}:
  Failed to format -> ${error:-Unknown error}
EOF
        return 1
    fi

    return 0
}

if [ "$#" -lt "1" ]; then
    echo >&2 "Missing argument"
    exit 1
fi

i=0
pids=()
cores=$(nproc)
status=0
for file in "$@"; do
    if [ "$i" -ge "$cores" ]; then
        for pid in ${pids[*]}; do
            if ! wait $pid; then
                status=1
            fi
        done
        i=0
        pids=()
    fi
    main_loop "$file" &
    pids[${i}]=$!
    i=$((i + 1))
done

for pid in ${pids[*]}; do
    if ! wait $pid; then
        status=1
    fi
done

exit $status
