#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
output_dir=${OUTPUT_DIR:-"$repo_dir/dist"}
app_path="$output_dir/Paddr.app"
zip_path="$output_dir/Paddr.zip"
digest_path="$zip_path.sha256"
: "${EXPECTED_VERSION:?Set EXPECTED_VERSION to the intended release version.}"
: "${EXPECTED_BUILD:?Set EXPECTED_BUILD to the intended release build.}"
architectures=${ARCHITECTURES:-arm64}
if test "$architectures" != "arm64"; then
    echo "Release packages must be arm64-only; got ARCHITECTURES=$architectures" >&2
    exit 2
fi
export ARCHITECTURES="$architectures"

"$script_dir/build-app.sh"

binary="$app_path/Contents/MacOS/Paddr"

"$binary" >/dev/null 2>&1 &
smoke_pid=$!
sleep 2
if ! kill -0 "$smoke_pid" 2>/dev/null; then
    wait "$smoke_pid"
    echo "App smoke test exited unexpectedly." >&2
    exit 1
fi
kill "$smoke_pid"
wait "$smoke_pid" 2>/dev/null || true

rm -f "$zip_path" "$digest_path"
archive_stage=$(mktemp -d "$output_dir/.paddr-archive.XXXXXX")
trap 'rm -rf "$archive_stage"' EXIT HUP INT TERM
cp -R "$app_path" "$archive_stage/Paddr.app"
ditto -c -k --keepParent --norsrc "$archive_stage/Paddr.app" "$zip_path"

archive_listing=$(unzip -Z1 "$zip_path")
if printf '%s\n' "$archive_listing" | grep -Eq '(^|/)__MACOSX(/|$)|(^|/)\._'; then
    echo "Archive contains forbidden metadata." >&2
    exit 1
fi
printf '%s\n' "$archive_listing" | grep -qx 'Paddr.app/Contents/MacOS/Paddr'
(
    cd "$output_dir"
    shasum -a 256 Paddr.zip > Paddr.zip.sha256
)

"$script_dir/verify-release.sh" \
    "$app_path" "$zip_path" "$digest_path" "$EXPECTED_VERSION" "$EXPECTED_BUILD"
"$script_dir/test-release-package.sh" "$output_dir" "$EXPECTED_VERSION" "$EXPECTED_BUILD"

actual_digest=$(awk '{print $1}' "$digest_path")

echo "Packaged Paddr $EXPECTED_VERSION ($EXPECTED_BUILD): $zip_path"
echo "SHA-256: $actual_digest"
