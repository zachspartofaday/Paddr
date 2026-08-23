#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
output_dir=${OUTPUT_DIR:-"$repo_dir/dist"}
app_path="$output_dir/Paddr.app"
zip_path="$output_dir/Paddr.zip"
digest_path="$zip_path.sha256"
: "${RELEASE_REF:?Set RELEASE_REF to the annotated vX.Y.Z tag being packaged.}"
release_identity=$("$script_dir/release-identity.sh" "$repo_dir" "$RELEASE_REF")
expected_version=$(printf '%s\n' "$release_identity" | sed -n '1p')
expected_build=$(printf '%s\n' "$release_identity" | sed -n '2p')
expected_revision=$(printf '%s\n' "$release_identity" | sed -n '3p')
architectures=${ARCHITECTURES:-arm64}
if test "$architectures" != "arm64"; then
    echo "Release packages must be arm64-only; got ARCHITECTURES=$architectures" >&2
    exit 2
fi
export ARCHITECTURES="$architectures"

mkdir -p "$output_dir"
package_stage=$(mktemp -d "$output_dir/.paddr-package.XXXXXX")
stage_output_dir="$package_stage/output"
stage_scratch_path="$package_stage/swiftpm"
stage_temporary_root="$package_stage/tmp"
staged_app_path="$stage_output_dir/Paddr.app"
staged_zip_path="$stage_output_dir/Paddr.zip"
staged_digest_path="$staged_zip_path.sha256"
archive_stage="$package_stage/archive"
backup_dir="$package_stage/previous"
smoke_pid=
transaction_active=false
transaction_interrupted=false
backed_up_app=false
backed_up_zip=false
backed_up_digest=false
promoted_app=false
promoted_zip=false
promoted_digest=false

rollback_outputs() {
    rollback_failed=false

    if test "$promoted_digest" = true && ! rm -f -- "$digest_path"; then
        rollback_failed=true
    fi
    if test "$promoted_zip" = true && ! rm -f -- "$zip_path"; then
        rollback_failed=true
    fi
    if test "$promoted_app" = true && ! rm -rf -- "$app_path"; then
        rollback_failed=true
    fi

    if test "$backed_up_app" = true && ! mv "$backup_dir/Paddr.app" "$app_path"; then
        rollback_failed=true
    fi
    if test "$backed_up_zip" = true && ! mv "$backup_dir/Paddr.zip" "$zip_path"; then
        rollback_failed=true
    fi
    if test "$backed_up_digest" = true &&
       ! mv "$backup_dir/Paddr.zip.sha256" "$digest_path"; then
        rollback_failed=true
    fi

    if test "$rollback_failed" = true; then
        echo "Release promotion failed and the previous outputs could not be fully restored." >&2
        return 1
    fi
    transaction_active=false
    return 0
}

cleanup() {
    if test -n "$smoke_pid" && kill -0 "$smoke_pid" 2>/dev/null; then
        kill "$smoke_pid" 2>/dev/null || true
        wait "$smoke_pid" 2>/dev/null || true
    fi
    if test "$transaction_active" = true; then
        if ! rollback_outputs; then
            echo "Preserving the release stage for manual recovery: $package_stage" >&2
            return
        fi
    fi
    rm -rf -- "$package_stage"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir -p \
    "$stage_output_dir" \
    "$stage_scratch_path" \
    "$stage_temporary_root" \
    "$archive_stage" \
    "$backup_dir"

OUTPUT_DIR="$stage_output_dir" \
BUILD_SCRATCH_PATH="$stage_scratch_path" \
TMPDIR="$stage_temporary_root" \
    "$script_dir/build-app.sh"

binary="$staged_app_path/Contents/MacOS/Paddr"

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
smoke_pid=

cp -R "$staged_app_path" "$archive_stage/Paddr.app"
ditto -c -k --keepParent --norsrc "$archive_stage/Paddr.app" "$staged_zip_path"

archive_listing=$(unzip -Z1 "$staged_zip_path")
if printf '%s\n' "$archive_listing" | grep -Eq '(^|/)__MACOSX(/|$)|(^|/)\._'; then
    echo "Archive contains forbidden metadata." >&2
    exit 1
fi
printf '%s\n' "$archive_listing" | grep -qx 'Paddr.app/Contents/MacOS/Paddr'
(
    cd "$stage_output_dir"
    shasum -a 256 Paddr.zip > Paddr.zip.sha256
)

TMPDIR="$stage_temporary_root" "$script_dir/verify-release.sh" \
    "$staged_app_path" "$staged_zip_path" "$staged_digest_path" \
    "$expected_version" "$expected_build" "$expected_revision"
BUILD_SCRATCH_PATH="$stage_scratch_path" \
TMPDIR="$stage_temporary_root" \
    "$script_dir/test-release-package.sh" \
    "$stage_output_dir" "$expected_version" "$expected_build" "$expected_revision"

if ! final_release_identity=$("$script_dir/release-identity.sh" "$repo_dir" "$RELEASE_REF"); then
    echo "Release source identity changed while the package was being produced." >&2
    exit 1
fi
if test "$final_release_identity" != "$release_identity"; then
    echo "Release source identity changed while the package was being produced." >&2
    exit 1
fi

actual_digest=$(awk '{print $1}' "$staged_digest_path")

transaction_active=true
transaction_interrupted=false
trap 'transaction_interrupted=true' HUP INT TERM
if test -e "$app_path" || test -L "$app_path"; then
    if mv "$app_path" "$backup_dir/Paddr.app"; then
        backed_up_app=true
    else
        echo "Unable to preserve the previous app before release promotion." >&2
        exit 1
    fi
fi
if test -e "$zip_path" || test -L "$zip_path"; then
    if mv "$zip_path" "$backup_dir/Paddr.zip"; then
        backed_up_zip=true
    else
        echo "Unable to preserve the previous archive before release promotion." >&2
        exit 1
    fi
fi
if test -e "$digest_path" || test -L "$digest_path"; then
    if mv "$digest_path" "$backup_dir/Paddr.zip.sha256"; then
        backed_up_digest=true
    else
        echo "Unable to preserve the previous digest before release promotion." >&2
        exit 1
    fi
fi

if mv "$staged_app_path" "$app_path"; then
    promoted_app=true
else
    echo "Unable to promote the staged app." >&2
    exit 1
fi
if mv "$staged_zip_path" "$zip_path"; then
    promoted_zip=true
else
    echo "Unable to promote the staged archive." >&2
    exit 1
fi
if mv "$staged_digest_path" "$digest_path"; then
    promoted_digest=true
else
    echo "Unable to promote the staged digest." >&2
    exit 1
fi

if test "$transaction_interrupted" = true; then
    echo "Release promotion interrupted; restoring previous outputs." >&2
    exit 1
fi
transaction_active=false
trap 'exit 1' HUP INT TERM

echo "Packaged Paddr $expected_version ($expected_build), revision $expected_revision: $zip_path"
echo "SHA-256: $actual_digest"
