#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
output_dir=${OUTPUT_DIR:-"$repo_dir/dist"}
app_path="$output_dir/PuckPads.app"
contents_path="$app_path/Contents"
binary_path="$contents_path/MacOS/PuckPads"
sign_identity=${SIGN_IDENTITY:--}
asset_info_path="$contents_path/assetcatalog-info.plist"
build_scratch_path=${BUILD_SCRATCH_PATH:-}

cd "$repo_dir"
if [ -n "$build_scratch_path" ]; then
    swift build -c release --scratch-path "$build_scratch_path" --product PuckPadsMenu
    build_dir=$(swift build -c release --scratch-path "$build_scratch_path" --show-bin-path)
else
    swift build -c release --product PuckPadsMenu
    build_dir=$(swift build -c release --show-bin-path)
fi

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$repo_dir/Packaging/Info.plist" "$contents_path/Info.plist"
cp "$build_dir/PuckPadsMenu" "$binary_path"
chmod 755 "$binary_path"

xcrun actool \
    --compile "$contents_path/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$asset_info_path" \
    "$repo_dir/Assets/Assets.xcassets"
/usr/libexec/PlistBuddy -c "Merge $asset_info_path" "$contents_path/Info.plist"
rm "$asset_info_path"

if [ "$sign_identity" = "-" ]; then
    codesign --force --sign - "$app_path"
else
    codesign --force --options runtime --timestamp --sign "$sign_identity" "$app_path"
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
echo "Built $app_path"
if [ "$sign_identity" = "-" ]; then
    echo "Signing: ad hoc (local testing only)"
else
    echo "Signing: $sign_identity"
fi
