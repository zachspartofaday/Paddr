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

mkdir -p "$fixture/Packaging"
cp "$script_dir/../Packaging/Info.plist" "$fixture/Packaging/Info.plist"
git -C "$fixture" init -q
git -C "$fixture" config user.name "Paddr release identity test"
git -C "$fixture" config user.email "paddr-release-test@example.invalid"
git -C "$fixture" add Packaging/Info.plist
git -C "$fixture" commit -qm "Release fixture"
git -C "$fixture" tag -a v0.11.0 -m "Release fixture"

identity=$("$script_dir/release-identity.sh" "$fixture" v0.11.0)
test "$(printf '%s\n' "$identity" | sed -n '1p')" = "0.11.0"
test "$(printf '%s\n' "$identity" | sed -n '2p')" = "16"
test "$(printf '%s\n' "$identity" | sed -n '3p')" = "$(git -C "$fixture" rev-parse HEAD)"

printf '%s\n' "tracked change" >> "$fixture/Packaging/Info.plist"
if "$script_dir/release-identity.sh" "$fixture" v0.11.0 >/dev/null 2>&1; then
    echo "Release identity accepted tracked dirty source." >&2
    exit 1
fi
git -C "$fixture" restore Packaging/Info.plist

git -C "$fixture" tag v0.11.1
if "$script_dir/release-identity.sh" "$fixture" v0.11.1 >/dev/null 2>&1; then
    echo "Release identity accepted a lightweight tag." >&2
    exit 1
fi

git -C "$fixture" tag -a v0.11.2 -m "Mismatched release fixture"
if "$script_dir/release-identity.sh" "$fixture" v0.11.2 >/dev/null 2>&1; then
    echo "Release identity accepted a tag/source version mismatch." >&2
    exit 1
fi

if "$script_dir/release-identity.sh" "$fixture" v9.9.9 >/dev/null 2>&1; then
    echo "Release identity accepted a missing release tag." >&2
    exit 1
fi

printf '%s\n' "next" > "$fixture/next.txt"
git -C "$fixture" add next.txt
git -C "$fixture" commit -qm "Move past release"
if "$script_dir/release-identity.sh" "$fixture" v0.11.0 >/dev/null 2>&1; then
    echo "Release identity accepted HEAD away from the release tag." >&2
    exit 1
fi

echo "Release identity rejects dirty, missing, lightweight, and mismatched source."
