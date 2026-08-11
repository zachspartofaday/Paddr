#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
source_path="$repo_dir/Assets/PaddrIcon.png"
catalog_dir="$repo_dir/Assets/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$source_path" ]; then
    echo "Missing canonical icon source: $source_path" >&2
    exit 2
fi

pixel_width=$(sips -g pixelWidth "$source_path" | awk '/pixelWidth:/ { print $2 }')
pixel_height=$(sips -g pixelHeight "$source_path" | awk '/pixelHeight:/ { print $2 }')
if [ "$pixel_width" != "$pixel_height" ] || [ "$pixel_width" -lt 1024 ]; then
    echo "PaddrIcon.png must be square and at least 1024 pixels wide." >&2
    exit 2
fi

stage_dir=$(mktemp -d)
cleanup() { rm -rf "$stage_dir"; }
trap cleanup EXIT HUP INT TERM

render() {
    size=$1
    filename=$2
    sips -z "$size" "$size" "$source_path" --out "$stage_dir/$filename" >/dev/null
    actual_width=$(sips -g pixelWidth "$stage_dir/$filename" | awk '/pixelWidth:/ { print $2 }')
    actual_height=$(sips -g pixelHeight "$stage_dir/$filename" | awk '/pixelHeight:/ { print $2 }')
    if [ "$actual_width" != "$size" ] || [ "$actual_height" != "$size" ]; then
        echo "Generated unexpected dimensions for $filename." >&2
        exit 1
    fi
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

for generated in "$stage_dir"/*.png; do
    mv "$generated" "$catalog_dir/$(basename "$generated")"
done

echo "Regenerated Paddr AppIcon renditions from Assets/PaddrIcon.png."
