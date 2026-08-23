#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temporary_root=${TMPDIR:-/tmp}
fixture=$(mktemp -d "$temporary_root/paddr-release-identity.XXXXXX")

cleanup() {
    case "$fixture" in
        "$temporary_root"/paddr-release-identity.*) rm -rf -- "$fixture" ;;
        *) echo "Refusing to remove unexpected fixture: $fixture" >&2 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

assert_clean() {
    source_state=$("$script_dir/source-dirty.sh" "$fixture")
    if test "$source_state" != false; then
        echo "Source state was not clean: $source_state" >&2
        exit 1
    fi
}

assert_dirty_and_rejected() {
    description=$1
    source_state=$("$script_dir/source-dirty.sh" "$fixture")
    if test "$source_state" != true; then
        echo "Source state was not dirty for $description: $source_state" >&2
        exit 1
    fi
    if "$script_dir/release-identity.sh" "$fixture" "$release_ref" >/dev/null 2>&1; then
        echo "Release identity accepted $description." >&2
        exit 1
    fi
}

mkdir -p "$fixture/Packaging" "$fixture/Sources/PaddrMenu"
cp "$script_dir/../Packaging/Info.plist" "$fixture/Packaging/Info.plist"
cp "$script_dir/../.gitignore" "$fixture/.gitignore"
git -C "$fixture" init -q
git -C "$fixture" config user.name "Paddr release identity test"
git -C "$fixture" config user.email "paddr-release-test@example.invalid"
git -C "$fixture" add .gitignore Packaging/Info.plist
git -C "$fixture" commit -qm "Release fixture"
fixture_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$fixture/Packaging/Info.plist")
fixture_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$fixture/Packaging/Info.plist")
release_ref="v$fixture_version"
git -C "$fixture" tag -a "$release_ref" -m "Release fixture"

assert_clean
test "$("$script_dir/source-dirty.sh" "$fixture/missing")" = true

identity=$("$script_dir/release-identity.sh" "$fixture" "$release_ref")
test "$(printf '%s\n' "$identity" | sed -n '1p')" = "$fixture_version"
test "$(printf '%s\n' "$identity" | sed -n '2p')" = "$fixture_build"
test "$(printf '%s\n' "$identity" | sed -n '3p')" = "$(git -C "$fixture" rev-parse HEAD)"

mkdir -p \
    "$fixture/.build/artifacts" \
    "$fixture/.swiftpm/configuration" \
    "$fixture/dist/Paddr.app" \
    "$fixture/.codex-worktrees/fixture" \
    "$fixture/docs/audits" \
    "$fixture/docs/kickoffs" \
    "$fixture/Sources/PaddrMenu/Artifacts"
printf '%s\n' artifact > "$fixture/.build/artifacts/output"
printf '%s\n' artifact > "$fixture/.swiftpm/configuration/state"
printf '%s\n' artifact > "$fixture/dist/Paddr.app/output"
printf '%s\n' artifact > "$fixture/.codex-worktrees/fixture/output"
printf '%s\n' artifact > "$fixture/docs/audits/report.md"
printf '%s\n' artifact > "$fixture/docs/kickoffs/prompt.md"
printf '%s\n' artifact > "$fixture/.DS_Store"
printf '%s\n' artifact > "$fixture/Sources/PaddrMenu/Artifacts/.DS_Store"
printf '%s\n' artifact > "$fixture/Window.xcuserstate"
printf '%s\n' artifact > "$fixture/Sources/PaddrMenu/Artifacts/Window.xcuserstate"
assert_clean
"$script_dir/release-identity.sh" "$fixture" "$release_ref" >/dev/null

printf '%s\n' "# unstaged tracked change" >> "$fixture/.gitignore"
assert_dirty_and_rejected "an unstaged tracked change"
git -C "$fixture" restore .gitignore

printf '%s\n' "# staged tracked change" >> "$fixture/.gitignore"
git -C "$fixture" add .gitignore
assert_dirty_and_rejected "a staged tracked change"
git -C "$fixture" restore --staged --worktree .gitignore

printf '%s\n' 'struct Extra {}' > "$fixture/Sources/PaddrMenu/Extra.swift"
assert_dirty_and_rejected "an ordinary untracked Swift source"
rm -f -- "$fixture/Sources/PaddrMenu/Extra.swift"

mkdir -p "$fixture/Sources/PaddrMenu/dist"
printf '%s\n' 'struct IgnoredExtra {}' > "$fixture/Sources/PaddrMenu/dist/IgnoredExtra.swift"
git -C "$fixture" check-ignore -q Sources/PaddrMenu/dist/IgnoredExtra.swift
assert_dirty_and_rejected "a repository-ignored nested dist Swift source"
rm -f -- "$fixture/Sources/PaddrMenu/dist/IgnoredExtra.swift"

mkdir -p "$fixture/Sources/PaddrMenu/.build"
printf '%s\n' 'struct IgnoredBuildExtra {}' > "$fixture/Sources/PaddrMenu/.build/IgnoredBuildExtra.swift"
git -C "$fixture" check-ignore -q Sources/PaddrMenu/.build/IgnoredBuildExtra.swift
assert_dirty_and_rejected "a repository-ignored nested .build Swift source"
rm -f -- "$fixture/Sources/PaddrMenu/.build/IgnoredBuildExtra.swift"

printf '%s\n' 'Sources/PaddrMenu/LocallyExcluded.swift' >> "$fixture/.git/info/exclude"
printf '%s\n' 'struct LocallyExcluded {}' > "$fixture/Sources/PaddrMenu/LocallyExcluded.swift"
git -C "$fixture" check-ignore -q Sources/PaddrMenu/LocallyExcluded.swift
assert_dirty_and_rejected "a .git/info/exclude-hidden Swift source"
rm -f -- "$fixture/Sources/PaddrMenu/LocallyExcluded.swift"

global_excludes="$fixture/.git/test-global-excludes"
printf '%s\n' 'Sources/PaddrMenu/GloballyExcluded.swift' > "$global_excludes"
git -C "$fixture" config core.excludesFile "$global_excludes"
printf '%s\n' 'struct GloballyExcluded {}' > "$fixture/Sources/PaddrMenu/GloballyExcluded.swift"
git -C "$fixture" check-ignore -q Sources/PaddrMenu/GloballyExcluded.swift
assert_dirty_and_rejected "a core.excludesFile-hidden Swift source"
rm -f -- "$fixture/Sources/PaddrMenu/GloballyExcluded.swift"
git -C "$fixture" config --unset core.excludesFile

assert_clean

git -C "$fixture" tag v999.999.997
if "$script_dir/release-identity.sh" "$fixture" v999.999.997 >/dev/null 2>&1; then
    echo "Release identity accepted a lightweight tag." >&2
    exit 1
fi

git -C "$fixture" tag -a v999.999.998 -m "Mismatched release fixture"
if "$script_dir/release-identity.sh" "$fixture" v999.999.998 >/dev/null 2>&1; then
    echo "Release identity accepted a tag/source version mismatch." >&2
    exit 1
fi

if "$script_dir/release-identity.sh" "$fixture" v999.999.999 >/dev/null 2>&1; then
    echo "Release identity accepted a missing release tag." >&2
    exit 1
fi

printf '%s\n' "next" > "$fixture/next.txt"
git -C "$fixture" add next.txt
git -C "$fixture" commit -qm "Move past release"
if "$script_dir/release-identity.sh" "$fixture" "$release_ref" >/dev/null 2>&1; then
    echo "Release identity accepted HEAD away from the release tag." >&2
    exit 1
fi

echo "Release identity rejects tracked, staged, untracked, ignored, missing, lightweight, and mismatched source."
