#!/bin/sh
set -eu

if test "$#" -ne 5; then
    echo "Usage: $0 APP_PATH ZIP_PATH DIGEST_PATH EXPECTED_VERSION EXPECTED_BUILD" >&2
    exit 2
fi

app_path=$1
zip_path=$2
digest_path=$3
expected_version=$4
expected_build=$5
expected_architectures=arm64
temporary_root=${TMPDIR:-/tmp}
extract_dir=$(mktemp -d "$temporary_root/paddr-verify.XXXXXX")

cleanup() {
    case "$extract_dir" in
        "$temporary_root"/paddr-verify.*) rm -rf -- "$extract_dir" ;;
        *) echo "Refusing to remove unexpected verification directory: $extract_dir" >&2 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

verify_app() {
    verified_app=$1
    test -d "$verified_app"
    if find "$verified_app" -type l -print -quit | grep -q .; then
        echo "Bundle contains a symbolic link: $verified_app" >&2
        return 1
    fi

    plist="$verified_app/Contents/Info.plist"
    binary="$verified_app/Contents/MacOS/Paddr"
    if ! test -x "$binary"; then
        echo "App binary is not executable: $binary" >&2
        return 1
    fi
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$expected_version"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$expected_build"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "com.partofaday.Paddr"
    test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" = "26.0"

    actual_architectures=$(lipo -archs "$binary")
    set -- $actual_architectures
    actual_architecture_count=$#
    set -- $expected_architectures
    expected_architecture_count=$#
    test "$actual_architecture_count" -eq "$expected_architecture_count"
    for architecture in $expected_architectures; do
        printf '%s\n' "$actual_architectures" | tr ' ' '\n' | grep -qx "$architecture"
    done

    test -f "$verified_app/Contents/Resources/en.lproj/Localizable.strings"
    codesign --verify --deep --strict --verbose=2 "$verified_app"

    find "$verified_app/Contents" -mindepth 1 -print | while IFS= read -r item; do
        relative=${item#"$verified_app"/}
        case "$relative" in
            Contents/Info.plist|Contents/MacOS|Contents/MacOS/Paddr|Contents/Resources|\
            Contents/Resources/AppIcon.icns|Contents/Resources/Assets.car|\
            Contents/Resources/en.lproj|Contents/Resources/en.lproj/Localizable.strings|\
            Contents/_CodeSignature|Contents/_CodeSignature/CodeResources) ;;
            *) echo "Unexpected bundle content: $relative" >&2; exit 1 ;;
        esac
    done
}

test -f "$zip_path"
test -f "$digest_path"
test "$(basename -- "$zip_path")" = "Paddr.zip"
test "$(basename -- "$digest_path")" = "Paddr.zip.sha256"

digest_line=$(sed -n '1p' "$digest_path")
test "$(wc -l < "$digest_path" | tr -d ' ')" -eq 1
digest_hash=$(printf '%s\n' "$digest_line" | awk '{print $1}')
digest_name=$(printf '%s\n' "$digest_line" | awk '{print $2}')
printf '%s\n' "$digest_hash" | grep -Eq '^[0-9a-fA-F]{64}$'
test "$digest_name" = "Paddr.zip"
(
    cd "$(dirname -- "$digest_path")"
    shasum -a 256 -c "$(basename -- "$digest_path")"
)

archive_listing=$(unzip -Z1 "$zip_path")
test -n "$archive_listing"
if printf '%s\n' "$archive_listing" | grep -Eq '(^/)|(^|/)\.\.(/|$)|(^|/)__MACOSX(/|$)|(^|/)\._'; then
    echo "Archive contains an unsafe or forbidden path." >&2
    exit 1
fi
if test "$(printf '%s\n' "$archive_listing" | awk -F/ 'NF {print $1}' | sort -u)" != "Paddr.app"; then
    echo "Archive must contain only the Paddr.app top-level bundle." >&2
    exit 1
fi
printf '%s\n' "$archive_listing" | grep -qx 'Paddr.app/Contents/MacOS/Paddr'

ditto -x -k --norsrc "$zip_path" "$extract_dir"
extracted_app="$extract_dir/Paddr.app"
verify_app "$app_path"
verify_app "$extracted_app"
if ! diff -qr "$app_path" "$extracted_app" >/dev/null; then
    echo "Archived app does not exactly match the staged app." >&2
    exit 1
fi

echo "Verified Paddr $expected_version ($expected_build)."
