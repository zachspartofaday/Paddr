#!/bin/sh
set -eu

if test "$#" -ne 2; then
    echo "Usage: $0 REPOSITORY_PATH RELEASE_REF" >&2
    exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$1
release_ref=$2

case "$release_ref" in
    refs/tags/v*) tag_name=${release_ref#refs/tags/} ;;
    v*) tag_name=$release_ref ;;
    *) echo "RELEASE_REF must name a vX.Y.Z tag; got: $release_ref" >&2; exit 2 ;;
esac

version=${tag_name#v}
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Release tag must use vX.Y.Z; got: $tag_name" >&2
    exit 2
fi

object_type=$(git -C "$repo_dir" cat-file -t "$release_ref" 2>/dev/null || true)
if test "$object_type" != "tag"; then
    echo "Release ref must be an existing annotated tag: $release_ref" >&2
    exit 1
fi

revision=$(git -C "$repo_dir" rev-parse "$release_ref^{}")
head_revision=$(git -C "$repo_dir" rev-parse HEAD)
if test "$head_revision" != "$revision"; then
    echo "HEAD $head_revision does not match $release_ref at $revision." >&2
    exit 1
fi

if ! source_dirty=$("$script_dir/source-dirty.sh" "$repo_dir"); then
    source_dirty=true
fi
if test "$source_dirty" != false; then
    echo "Release source has tracked, staged, or untracked changes; package a clean annotated tag." >&2
    exit 1
fi

plist="$repo_dir/Packaging/Info.plist"
source_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
if test "$source_version" != "$version"; then
    echo "Tag version $version does not match source plist version $source_version." >&2
    exit 1
fi
if ! printf '%s\n' "$build" | grep -Eq '^[1-9][0-9]*$'; then
    echo "Source plist build must be a positive integer; got: $build" >&2
    exit 1
fi

printf '%s\n%s\n%s\n' "$version" "$build" "$revision"
