#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname -- "$script_dir")
temporary_root=${TMPDIR:-/tmp}
test_root=$(mktemp -d "$temporary_root/paddr-release-production.XXXXXX")

cleanup() {
    case "$test_root" in
        "$temporary_root"/paddr-release-production.*) rm -rf -- "$test_root" ;;
        *) echo "Refusing to remove unexpected release-production fixture: $test_root" >&2 ;;
    esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

write_fake_tool() {
    tool_path=$1
    shift
    printf '%s\n' "$@" > "$tool_path"
    chmod 755 "$tool_path"
}

assert_sentinel_outputs() {
    sentinel_output_dir=$1
    test "$(sed -n '1p' "$sentinel_output_dir/Paddr.app/sentinel.txt")" = "sentinel app"
    test "$(sed -n '1p' "$sentinel_output_dir/Paddr.zip")" = "sentinel archive"
    test "$(sed -n '1p' "$sentinel_output_dir/Paddr.zip.sha256")" = "sentinel digest"
    assert_no_package_stage "$sentinel_output_dir"
}

assert_no_package_stage() {
    checked_output_dir=$1
    if find "$checked_output_dir" -maxdepth 1 -name '.paddr-package.*' -print -quit | grep -q .; then
        echo "A failed package left its private stage behind." >&2
        exit 1
    fi
}

build_fixture="$test_root/build-mutation"
build_tools="$test_root/build-tools"
mkdir -p \
    "$build_fixture/scripts" \
    "$build_fixture/Packaging" \
    "$build_fixture/Resources" \
    "$build_fixture/Assets/Assets.xcassets" \
    "$build_fixture/Sources" \
    "$build_tools"
cp "$script_dir/build-app.sh" "$script_dir/source-dirty.sh" "$build_fixture/scripts/"
cp "$repository_root/Packaging/Info.plist" "$build_fixture/Packaging/Info.plist"
cp "$repository_root/Resources/Localizable.xcstrings" \
    "$build_fixture/Resources/Localizable.xcstrings"
cp "$repository_root/THIRD_PARTY_NOTICES.md" "$build_fixture/THIRD_PARTY_NOTICES.md"
cp "$repository_root/.gitignore" "$build_fixture/.gitignore"
printf '%s\n' 'tracked build input' > "$build_fixture/Sources/TrackedInput.swift"
git -C "$build_fixture" init -q
git -C "$build_fixture" config user.name "Paddr build mutation test"
git -C "$build_fixture" config user.email "paddr-build-mutation@example.invalid"
git -C "$build_fixture" add .
git -C "$build_fixture" commit -qm "Build mutation fixture"

mkdir -p "$build_fixture/dist/Paddr.app"
printf '%s\n' 'sentinel app' > "$build_fixture/dist/Paddr.app/sentinel.txt"

write_fake_tool "$build_tools/swift" \
    '#!/bin/sh' \
    'set -eu' \
    'case " $* " in' \
    '    *" --show-bin-path "*) printf "%s\n" "$PADDR_TEST_BUILD_DIR"; exit 0 ;;' \
    'esac' \
    'printf "%s\n" "// mutated during compilation" >> "$PADDR_TEST_BUILD_FIXTURE/Sources/TrackedInput.swift"' \
    'mkdir -p "$PADDR_TEST_BUILD_DIR"' \
    'printf "%s\n" "#!/bin/sh" "exit 0" > "$PADDR_TEST_BUILD_DIR/Paddr"' \
    'chmod 755 "$PADDR_TEST_BUILD_DIR/Paddr"'

write_fake_tool "$build_tools/xcrun" \
    '#!/bin/sh' \
    'set -eu' \
    'tool=$1' \
    'shift' \
    'case "$tool" in' \
    '    xcstringstool)' \
    '        output=' \
    '        while test "$#" -gt 0; do' \
    '            if test "$1" = "--output-directory"; then output=$2; shift 2; else shift; fi' \
    '        done' \
    '        mkdir -p "$output/en.lproj"' \
    '        printf "%s\n" "fixture" > "$output/en.lproj/Localizable.strings"' \
    '        ;;' \
    '    actool)' \
    '        output=' \
    '        plist=' \
    '        while test "$#" -gt 0; do' \
    '            case "$1" in' \
    '                --compile) output=$2; shift 2 ;;' \
    '                --output-partial-info-plist) plist=$2; shift 2 ;;' \
    '                *) shift ;;' \
    '            esac' \
    '        done' \
    '        mkdir -p "$output"' \
    '        printf "%s\n" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">" "<plist version=\"1.0\"><dict/></plist>" > "$plist"' \
    '        ;;' \
    '    *) exit 2 ;;' \
    'esac'

write_fake_tool "$build_tools/lipo" \
    '#!/bin/sh' \
    'printf "%s\n" arm64'
write_fake_tool "$build_tools/strip" \
    '#!/bin/sh' \
    'exit 0'
write_fake_tool "$build_tools/codesign" \
    '#!/bin/sh' \
    'printf "%s\n" invoked > "$PADDR_TEST_CODESIGN_MARKER"'

build_log="$test_root/build-mutation.log"
if PATH="$build_tools:$PATH" \
   PADDR_TEST_BUILD_FIXTURE="$build_fixture" \
   PADDR_TEST_BUILD_DIR="$build_fixture/.build/fake" \
   PADDR_TEST_CODESIGN_MARKER="$test_root/codesign-invoked" \
   "$build_fixture/scripts/build-app.sh" >"$build_log" 2>&1; then
    echo "build-app.sh accepted a tracked input mutation during compilation." >&2
    exit 1
fi
grep -q 'Source checkout changed while the app was being built' "$build_log"
test "$(sed -n '1p' "$build_fixture/dist/Paddr.app/sentinel.txt")" = "sentinel app"
test ! -e "$test_root/codesign-invoked"
if find "$build_fixture/dist" -maxdepth 1 -name '.paddr-stage.*' -print -quit | grep -q .; then
    echo "The rejected app build left its private stage behind." >&2
    exit 1
fi

package_tools="$test_root/package-tools"
mkdir -p "$package_tools"
write_fake_tool "$package_tools/mv" \
    '#!/bin/sh' \
    'set -eu' \
    'if test "${PADDR_TEST_FAIL_PROMOTION:-false}" = true && test "$#" -eq 2 &&' \
    '   test "$2" = "$PADDR_TEST_CANONICAL_OUTPUT/Paddr.zip"; then' \
    '    case "$1" in' \
    '        "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/output/Paddr.zip)' \
    '            exit 1' \
    '            ;;' \
    '    esac' \
    'fi' \
    'if /bin/mv "$@"; then' \
    '    :' \
    'else' \
    '    move_status=$?' \
    '    exit "$move_status"' \
    'fi' \
    'case "${PADDR_TEST_PACKAGE_MODE:-}" in' \
    '    signal-backup)' \
    '        if test "$1" = "$PADDR_TEST_CANONICAL_OUTPUT/Paddr.app"; then' \
    '            case "$2" in' \
    '                "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/previous/Paddr.app)' \
    '                    kill -TERM "$PPID"' \
    '                    ;;' \
    '            esac' \
    '        fi' \
    '        ;;' \
    '    signal-promotion)' \
    '        if test "$2" = "$PADDR_TEST_CANONICAL_OUTPUT/Paddr.app"; then' \
    '            case "$1" in' \
    '                "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/output/Paddr.app)' \
    '                    kill -TERM "$PPID"' \
    '                    ;;' \
    '            esac' \
    '        fi' \
    '        ;;' \
    'esac'

create_package_fixture() {
    package_mode=$1
    package_fixture="$test_root/package-$package_mode"
    mkdir -p "$package_fixture/scripts" "$package_fixture/Packaging"
    cp \
        "$script_dir/package-release.sh" \
        "$script_dir/release-identity.sh" \
        "$script_dir/source-dirty.sh" \
        "$package_fixture/scripts/"
    cp "$repository_root/Packaging/Info.plist" "$package_fixture/Packaging/Info.plist"
    cp "$repository_root/.gitignore" "$package_fixture/.gitignore"
    printf '%s\n' 'tracked package input' > "$package_fixture/TrackedInput.txt"

    write_fake_tool "$package_fixture/scripts/build-app.sh" \
        '#!/bin/sh' \
        'set -eu' \
        'case "$OUTPUT_DIR" in' \
        '    "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/output) ;;' \
        '    *) echo "Build did not use the private package output stage: $OUTPUT_DIR" >&2; exit 1 ;;' \
        'esac' \
        'case "$BUILD_SCRATCH_PATH" in' \
        '    "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/swiftpm) ;;' \
        '    *) echo "Build did not use a private SwiftPM scratch path: $BUILD_SCRATCH_PATH" >&2; exit 1 ;;' \
        'esac' \
        'case "$TMPDIR" in' \
        '    "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/tmp) ;;' \
        '    *) echo "Build did not use the private temporary root: $TMPDIR" >&2; exit 1 ;;' \
        'esac' \
        'printf "build-output=%s\nbuild-scratch=%s\nbuild-tmp=%s\n" "$OUTPUT_DIR" "$BUILD_SCRATCH_PATH" "$TMPDIR" >> "$PADDR_TEST_RECORD"' \
        'mkdir -p "$OUTPUT_DIR/Paddr.app/Contents/MacOS" "$BUILD_SCRATCH_PATH"' \
        'printf "%s\n" "#!/bin/sh" "exec /bin/sleep 30" > "$OUTPUT_DIR/Paddr.app/Contents/MacOS/Paddr"' \
        'chmod 755 "$OUTPUT_DIR/Paddr.app/Contents/MacOS/Paddr"'

    write_fake_tool "$package_fixture/scripts/verify-release.sh" \
        '#!/bin/sh' \
        'set -eu' \
        'case "$1" in "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/output/Paddr.app) ;; *) exit 1 ;; esac' \
        'case "$2" in "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/output/Paddr.zip) ;; *) exit 1 ;; esac' \
        'case "$3" in "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/output/Paddr.zip.sha256) ;; *) exit 1 ;; esac' \
        'case "$TMPDIR" in "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/tmp) ;; *) exit 1 ;; esac' \
        'printf "verified=%s\n" "$1" >> "$PADDR_TEST_RECORD"'

    write_fake_tool "$package_fixture/scripts/test-release-package.sh" \
        '#!/bin/sh' \
        'set -eu' \
        'case "$1" in "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/output) ;; *) exit 1 ;; esac' \
        'case "$BUILD_SCRATCH_PATH" in "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/swiftpm) ;; *) exit 1 ;; esac' \
        'case "$TMPDIR" in "$PADDR_TEST_CANONICAL_OUTPUT"/.paddr-package.*/tmp) ;; *) exit 1 ;; esac' \
        'printf "package-test=%s\n" "$1" >> "$PADDR_TEST_RECORD"' \
        'if test "$PADDR_TEST_PACKAGE_MODE" = move-head; then' \
        '    printf "%s\n" "head moved during production" >> "$PADDR_TEST_REPOSITORY/TrackedInput.txt"' \
        '    git -C "$PADDR_TEST_REPOSITORY" add TrackedInput.txt' \
        '    git -C "$PADDR_TEST_REPOSITORY" commit -qm "Move HEAD during package production"' \
        'fi'

    git -C "$package_fixture" init -q
    git -C "$package_fixture" config user.name "Paddr package production test"
    git -C "$package_fixture" config user.email "paddr-package-production@example.invalid"
    git -C "$package_fixture" add .
    git -C "$package_fixture" commit -qm "Package production fixture"
    package_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$package_fixture/Packaging/Info.plist")
    package_release_ref="v$package_version"
    git -C "$package_fixture" tag -a "$package_release_ref" -m "Package production fixture"

    package_output="$package_fixture/dist"
    package_record="$package_fixture/.git/production-record"
    mkdir -p "$package_output/Paddr.app"
    printf '%s\n' 'sentinel app' > "$package_output/Paddr.app/sentinel.txt"
    printf '%s\n' 'sentinel archive' > "$package_output/Paddr.zip"
    printf '%s\n' 'sentinel digest' > "$package_output/Paddr.zip.sha256"

    package_log="$test_root/package-$package_mode.log"
    fail_promotion=false
    if test "$package_mode" = fail-promotion; then fail_promotion=true; fi
    package_succeeded=false
    if PATH="$package_tools:$PATH" \
       OUTPUT_DIR="$package_output" \
       RELEASE_REF="$package_release_ref" \
       PADDR_TEST_CANONICAL_OUTPUT="$package_output" \
       PADDR_TEST_FAIL_PROMOTION="$fail_promotion" \
       PADDR_TEST_PACKAGE_MODE="$package_mode" \
       PADDR_TEST_RECORD="$package_record" \
       PADDR_TEST_REPOSITORY="$package_fixture" \
       "$package_fixture/scripts/package-release.sh" >"$package_log" 2>&1; then
        package_succeeded=true
    fi

    if test "$package_mode" = success; then
        if test "$package_succeeded" != true; then
            echo "package-release.sh rejected the successful production fixture." >&2
            sed -n '1,200p' "$package_log" >&2
            exit 1
        fi
        test -x "$package_output/Paddr.app/Contents/MacOS/Paddr"
        test ! -e "$package_output/Paddr.app/sentinel.txt"
        (
            cd "$package_output"
            shasum -a 256 -c Paddr.zip.sha256 >/dev/null
        )
        assert_no_package_stage "$package_output"
    else
        if test "$package_succeeded" = true; then
            echo "package-release.sh accepted the $package_mode failure fixture." >&2
            exit 1
        fi
        assert_sentinel_outputs "$package_output"
    fi
    if ! grep -Eq "^build-output=$package_output/.paddr-package\.[^/]+/output$" "$package_record" ||
       ! grep -Eq "^build-scratch=$package_output/.paddr-package\.[^/]+/swiftpm$" "$package_record" ||
       ! grep -Eq "^verified=$package_output/.paddr-package\.[^/]+/output/Paddr.app$" "$package_record" ||
       ! grep -Eq "^package-test=$package_output/.paddr-package\.[^/]+/output$" "$package_record"; then
        echo "Package production did not complete every operation in its private stage." >&2
        sed -n '1,200p' "$package_log" >&2
        sed -n '1,200p' "$package_record" >&2
        exit 1
    fi
}

create_package_fixture move-head
grep -q 'Release source identity changed while the package was being produced' \
    "$test_root/package-move-head.log"

create_package_fixture fail-promotion
grep -q 'Unable to promote the staged archive' "$test_root/package-fail-promotion.log"

create_package_fixture signal-backup
grep -q 'Release promotion interrupted; restoring previous outputs' \
    "$test_root/package-signal-backup.log"

create_package_fixture signal-promotion
grep -q 'Release promotion interrupted; restoring previous outputs' \
    "$test_root/package-signal-promotion.log"

create_package_fixture success
grep -q 'Packaged Paddr' "$test_root/package-success.log"

echo "Release production rejects source movement and preserves prior outputs on failure."
