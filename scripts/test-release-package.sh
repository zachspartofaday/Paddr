#!/bin/sh
set -eu

if test "$#" -ne 3; then
    echo "Usage: $0 OUTPUT_DIR EXPECTED_VERSION EXPECTED_BUILD" >&2
    exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir=$1
expected_version=$2
expected_build=$3
app_path="$output_dir/Paddr.app"
zip_path="$output_dir/Paddr.zip"
digest_path="$output_dir/Paddr.zip.sha256"
temporary_root=${TMPDIR:-/tmp}
recipient_dir=$(mktemp -d "$temporary_root/paddr-recipient.XXXXXX")

cleanup() {
    case "$recipient_dir" in
        "$temporary_root"/paddr-recipient.*) rm -rf -- "$recipient_dir" ;;
        *) echo "Refusing to remove unexpected recipient directory: $recipient_dir" >&2 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

"$script_dir/verify-release.sh" \
    "$app_path" "$zip_path" "$digest_path" "$expected_version" "$expected_build"

if "$script_dir/verify-release.sh" \
    "$app_path" "$zip_path" "$digest_path" "wrong-$expected_version" "$expected_build" \
    >/dev/null 2>&1; then
    echo "Release verification accepted an incorrect version." >&2
    exit 1
fi

if "$script_dir/verify-release.sh" \
    "$app_path" "$zip_path" "$digest_path" "$expected_version" "wrong-$expected_build" \
    >/dev/null 2>&1; then
    echo "Release verification accepted an incorrect build." >&2
    exit 1
fi

cp "$zip_path" "$digest_path" "$recipient_dir/"
(
    cd "$recipient_dir"
    shasum -a 256 -c Paddr.zip.sha256
)

"$script_dir/verify-release.sh" \
    "$app_path" "$recipient_dir/Paddr.zip" "$recipient_dir/Paddr.zip.sha256" \
    "$expected_version" "$expected_build"

tampered_dir="$recipient_dir/tampered"
tampered_stage="$recipient_dir/tampered-stage/Paddr.app/Contents/MacOS"
mkdir -p "$tampered_dir" "$tampered_stage"
cp /bin/echo "$tampered_stage/Paddr"
ditto -c -k --keepParent --norsrc "$recipient_dir/tampered-stage/Paddr.app" "$tampered_dir/Paddr.zip"
(
    cd "$tampered_dir"
    shasum -a 256 Paddr.zip > Paddr.zip.sha256
)
if "$script_dir/verify-release.sh" \
    "$app_path" "$tampered_dir/Paddr.zip" "$tampered_dir/Paddr.zip.sha256" \
    "$expected_version" "$expected_build" >/dev/null 2>&1; then
    echo "Release verification accepted a tampered archive." >&2
    exit 1
fi

echo "Release artifacts verify from a clean recipient directory."
