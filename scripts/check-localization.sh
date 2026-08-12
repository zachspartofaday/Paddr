#!/bin/bash
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
temporary_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "$temporary_root/paddr-localization.XXXXXX")

cleanup() {
    case "$work_dir" in
        "$temporary_root"/paddr-localization.*) rm -rf -- "$work_dir" ;;
        *) echo "Refusing to remove unexpected localization directory: $work_dir" >&2 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

source_files=()
while IFS= read -r -d '' source_file; do
    source_files+=("$source_file")
done < <(find \
    "$repo_dir/Sources/TrackIsBackCore" \
    "$repo_dir/Sources/PaddrAppSupport" \
    "$repo_dir/Sources/TrackIsBackMenu" \
    -type f -name '*.swift' -print0)

xcrun xcstringstool extract \
    --modern-localizable-strings \
    --SwiftUI \
    --output-format xcstrings \
    --output-directory "$work_dir" \
    "${source_files[@]}"

xcrun xcstringstool print "$work_dir/Localizable.xcstrings" | sort -u > "$work_dir/extracted-keys"
xcrun xcstringstool print "$repo_dir/Resources/Localizable.xcstrings" | sort -u > "$work_dir/catalog-keys"
comm -23 "$work_dir/extracted-keys" "$work_dir/catalog-keys" > "$work_dir/missing-keys"

if test -s "$work_dir/missing-keys"; then
    echo "Localizable.xcstrings is missing extracted keys:" >&2
    sed 's/^/  /' "$work_dir/missing-keys" >&2
    exit 1
fi

mkdir "$work_dir/compiled"
xcrun xcstringstool compile \
    "$repo_dir/Resources/Localizable.xcstrings" \
    --output-directory "$work_dir/compiled"
test -f "$work_dir/compiled/en.lproj/Localizable.strings"

echo "Localization catalog covers every extracted Paddr key."
