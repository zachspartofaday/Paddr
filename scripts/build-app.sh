#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
output_dir=${OUTPUT_DIR:-"$repo_dir/dist"}
app_path="$output_dir/Paddr.app"
sign_identity=${SIGN_IDENTITY:--}
architectures=${ARCHITECTURES:-arm64}
build_scratch_path=${BUILD_SCRATCH_PATH:-}

case "$app_path" in
    "$repo_dir"/dist/Paddr.app|"$output_dir"/Paddr.app) ;;
    *) echo "Refusing unexpected app destination: $app_path" >&2; exit 2 ;;
esac

mkdir -p "$output_dir"
stage_dir=$(mktemp -d "$output_dir/.paddr-stage.XXXXXX")
staged_app="$stage_dir/Paddr.app"
contents_path="$staged_app/Contents"
binary_path="$contents_path/MacOS/Paddr"
asset_info_path="$stage_dir/assetcatalog-info.plist"
backup_path="$output_dir/.Paddr.previous.app"
cleanup() { rm -rf "$stage_dir"; }
trap cleanup EXIT HUP INT TERM

set -- -c release --product Paddr -Xswiftc -warnings-as-errors
if [ -n "$build_scratch_path" ]; then
    set -- "$@" --scratch-path "$build_scratch_path"
fi
for architecture in $architectures; do
    case "$architecture" in arm64) ;; *) echo "Paddr supports arm64 builds only; got: $architecture" >&2; exit 2 ;; esac
    set -- "$@" --arch "$architecture"
done

cd "$repo_dir"
swift build "$@"
build_dir=$(swift build "$@" --show-bin-path)

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$repo_dir/Packaging/Info.plist" "$contents_path/Info.plist"
cp "$build_dir/Paddr" "$binary_path"
chmod 755 "$binary_path"

xcrun xcstringstool compile \
    "$repo_dir/Resources/Localizable.xcstrings" \
    --output-directory "$contents_path/Resources"

xcrun actool \
    --compile "$contents_path/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$asset_info_path" \
    "$repo_dir/Assets/Assets.xcassets"
/usr/libexec/PlistBuddy -c "Merge $asset_info_path" "$contents_path/Info.plist"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$contents_path/Info.plist")" = "Paddr"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$contents_path/Info.plist")" = "26.0"
for architecture in $architectures; do
    lipo -archs "$binary_path" | tr ' ' '\n' | grep -qx "$architecture"
done

if [ "$sign_identity" = "-" ]; then
    codesign --force --sign - "$staged_app"
else
    codesign --force --options runtime --timestamp --sign "$sign_identity" "$staged_app"
fi
codesign --verify --deep --strict --verbose=2 "$staged_app"

rm -rf "$backup_path"
if [ -e "$app_path" ]; then mv "$app_path" "$backup_path"; fi
if mv "$staged_app" "$app_path"; then
    rm -rf "$backup_path"
else
    if [ -e "$backup_path" ]; then mv "$backup_path" "$app_path"; fi
    exit 1
fi

echo "Built $app_path"
echo "Architectures: $(lipo -archs "$app_path/Contents/MacOS/Paddr")"
if [ "$sign_identity" = "-" ]; then
    echo "Signing: ad hoc (local testing only)"
else
    echo "Signing: $sign_identity"
fi
