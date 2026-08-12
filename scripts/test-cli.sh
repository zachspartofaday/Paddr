#!/bin/sh
set -eu

cli_path=${1:?Usage: scripts/test-cli.sh /path/to/PaddrCLI}
if [ ! -x "$cli_path" ]; then
    echo "PaddrCLI is not executable: $cli_path" >&2
    exit 2
fi

test_dir=$(mktemp -d)
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT HUP INT TERM

missing_path="$test_dir/missing.json"
stdout_path="$test_dir/stdout"
stderr_path="$test_dir/stderr"

set +e
"$cli_path" --config "$missing_path" --show-config >"$stdout_path" 2>"$stderr_path"
status=$?
set -e

if [ "$status" -ne 2 ]; then
    echo "Expected missing --config to exit 2; got $status." >&2
    exit 1
fi
if [ -s "$stdout_path" ]; then
    echo "Missing --config unexpectedly wrote an effective configuration." >&2
    exit 1
fi
if ! grep -Fq "Configuration file does not exist at $missing_path." "$stderr_path"; then
    echo "Missing --config diagnostic did not include the requested path." >&2
    exit 1
fi

input_path="$test_dir/input.json"
printf '%s\n' '{"left":{"mode":"scroll"},"right":{"mode":"mouse"}}' >"$input_path"
"$cli_path" --config "$input_path" \
    --left-mouse-acceleration 0.25 \
    --right-mouse-acceleration 0.75 \
    --show-config >"$stdout_path" 2>"$stderr_path"
if ! grep -Fq '"mouseAcceleration" : 0.25' "$stdout_path" \
    || ! grep -Fq '"mouseAcceleration" : 0.75' "$stdout_path"; then
    echo "Mouse acceleration flags did not persist independent values." >&2
    exit 1
fi

"$cli_path" --help >"$stdout_path"
if ! grep -Fq -- '--left-mouse-acceleration' "$stdout_path" \
    || ! grep -Fq -- '--right-mouse-acceleration' "$stdout_path"; then
    echo "Mouse acceleration flags are missing from CLI help." >&2
    exit 1
fi

set +e
"$cli_path" --config "$input_path" --left-mouse-acceleration 1.01 --show-config \
    >"$stdout_path" 2>"$stderr_path"
status=$?
set -e
if [ "$status" -ne 2 ] \
    || ! grep -Fq 'left mouseAcceleration must be between 0 and 1.' "$stderr_path"; then
    echo "Invalid mouse acceleration did not use central configuration validation." >&2
    exit 1
fi

profile_store="$test_dir/profiles.json"
input_before="$test_dir/input-before.json"
cp "$input_path" "$input_before"
"$cli_path" --config "$input_path" --left-sensitivity 3 --write-config "$profile_store" \
    >"$stdout_path" 2>"$stderr_path"
if ! cmp -s "$input_path" "$input_before"; then
    echo "Canonical conversion modified the legacy compatibility input." >&2
    exit 1
fi
if ! grep -Fq '"schemaVersion" : 1' "$profile_store" \
    || ! grep -Fq '"userProfiles"' "$profile_store"; then
    echo "--write-config did not emit the canonical profile document." >&2
    exit 1
fi

"$cli_path" --profile-store "$profile_store" --list-profiles >"$stdout_path" 2>"$stderr_path"
if ! grep -Fq 'Default' "$stdout_path" || ! grep -Fq 'CLI configuration' "$stdout_path"; then
    echo "Profile listing omitted the built-in or converted profile." >&2
    exit 1
fi
profile_id=$(grep -F 'CLI configuration' "$stdout_path" | cut -f 3)
if [ -z "$profile_id" ]; then
    echo "Profile listing omitted the stable ID." >&2
    exit 1
fi

"$cli_path" --profile-store "$profile_store" --select-profile Default >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$profile_store" --list-profiles >"$stdout_path" 2>"$stderr_path"
if ! grep -Fq "*$(printf '\t')Default$(printf '\t')" "$stdout_path"; then
    echo "Profile name selection did not persist Default as active." >&2
    exit 1
fi
"$cli_path" --profile-store "$profile_store" --select-profile "$profile_id" \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$profile_store" --list-profiles >"$stdout_path" 2>"$stderr_path"
if ! grep -Fq "*$(printf '\t')CLI configuration$(printf '\t')$profile_id" "$stdout_path"; then
    echo "Stable-ID profile selection did not persist the requested profile." >&2
    exit 1
fi

"$cli_path" --profile-store "$profile_store" --select-profile Default \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$profile_store" --left-sensitivity 4 \
    --write-config "$profile_store" >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$profile_store" --list-profiles >"$stdout_path" 2>"$stderr_path"
second_profile_id=$(grep -F 'CLI configuration 2' "$stdout_path" | cut -f 3)
if [ -z "$second_profile_id" ]; then
    echo "Second inactive-profile fixture omitted its stable ID." >&2
    exit 1
fi
"$cli_path" --profile-store "$profile_store" --select-profile Default \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$profile_store" --left-sensitivity 5 \
    --write-config "$profile_store" >"$stdout_path" 2>"$stderr_path"
canonical_profiles_before="$test_dir/canonical-profiles-before"
canonical_profiles_after="$test_dir/canonical-profiles-after"
"$cli_path" --profile-store "$profile_store" --list-profiles \
    >"$canonical_profiles_before" 2>"$stderr_path"
inactive_before_store="$test_dir/inactive-before.json"
inactive_after_store="$test_dir/inactive-after.json"
inactive_first_before="$test_dir/inactive-first-before"
inactive_first_after="$test_dir/inactive-first-after"
inactive_second_before="$test_dir/inactive-second-before"
inactive_second_after="$test_dir/inactive-second-after"
cp "$profile_store" "$inactive_before_store"
"$cli_path" --profile-store "$inactive_before_store" --select-profile "$profile_id" \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --config "$inactive_before_store" --show-config \
    >"$inactive_first_before" 2>"$stderr_path"
"$cli_path" --profile-store "$inactive_before_store" --select-profile "$second_profile_id" \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --config "$inactive_before_store" --show-config \
    >"$inactive_second_before" 2>"$stderr_path"
"$cli_path" --config "$profile_store" --left-sensitivity 6 \
    --write-config "$profile_store" >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$profile_store" --list-profiles \
    >"$canonical_profiles_after" 2>"$stderr_path"
if ! cmp -s "$canonical_profiles_before" "$canonical_profiles_after"; then
    echo "In-place canonical --config write did not preserve inactive profiles and the active ID." >&2
    exit 1
fi
cp "$profile_store" "$inactive_after_store"
"$cli_path" --profile-store "$inactive_after_store" --select-profile "$profile_id" \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --config "$inactive_after_store" --show-config \
    >"$inactive_first_after" 2>"$stderr_path"
"$cli_path" --profile-store "$inactive_after_store" --select-profile "$second_profile_id" \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --config "$inactive_after_store" --show-config \
    >"$inactive_second_after" 2>"$stderr_path"
if ! cmp -s "$inactive_first_before" "$inactive_first_after" \
    || ! cmp -s "$inactive_second_before" "$inactive_second_after"; then
    echo "In-place canonical --config write modified an inactive profile configuration." >&2
    exit 1
fi
"$cli_path" --config "$profile_store" --show-config >"$stdout_path" 2>"$stderr_path"
if ! grep -Fq '"sensitivity" : 6' "$stdout_path"; then
    echo "In-place canonical --config write did not persist the active configuration edit." >&2
    exit 1
fi

preserved_profiles="$test_dir/preserved-profiles"
cp "$canonical_profiles_after" "$preserved_profiles"

assert_preserved_profiles() {
    store=$1
    label=$2
    actual="$test_dir/$label-profiles"
    "$cli_path" --profile-store "$store" --list-profiles >"$actual" 2>"$stderr_path"
    if ! cmp -s "$preserved_profiles" "$actual"; then
        echo "$label did not preserve every profile, stable ID, and the active ID." >&2
        exit 1
    fi
}

assert_preserved_inactive_configurations() {
    store=$1
    label=$2
    inspect="$test_dir/$label-inspect.json"
    first="$test_dir/$label-first"
    second="$test_dir/$label-second"
    cp "$store" "$inspect"
    "$cli_path" --profile-store "$inspect" --select-profile "$profile_id" \
        >"$stdout_path" 2>"$stderr_path"
    "$cli_path" --config "$inspect" --show-config >"$first" 2>"$stderr_path"
    "$cli_path" --profile-store "$inspect" --select-profile "$second_profile_id" \
        >"$stdout_path" 2>"$stderr_path"
    "$cli_path" --config "$inspect" --show-config >"$second" 2>"$stderr_path"
    if ! cmp -s "$inactive_first_after" "$first" \
        || ! cmp -s "$inactive_second_after" "$second"; then
        echo "$label modified an inactive profile configuration." >&2
        exit 1
    fi
}

assert_active_sensitivity() {
    store=$1
    expected=$2
    label=$3
    "$cli_path" --config "$store" --show-config >"$stdout_path" 2>"$stderr_path"
    if ! grep -Fq "\"sensitivity\" : $expected" "$stdout_path"; then
        echo "$label did not persist active sensitivity $expected." >&2
        exit 1
    fi
}

case_probe="$test_dir/case-probe"
case_probe_variant="$test_dir/CASE-PROBE"
printf '%s\n' probe >"$case_probe"
if [ -e "$case_probe_variant" ]; then
    case_variant_store="$test_dir/PROFILES.JSON"
    "$cli_path" --config "$case_variant_store" --left-sensitivity 6.5 \
        --write-config "$profile_store" >"$stdout_path" 2>"$stderr_path"
    assert_preserved_profiles "$profile_store" "case-equivalent alias"
    assert_preserved_inactive_configurations "$profile_store" "case-equivalent-alias"
    assert_active_sensitivity "$profile_store" 6.5 "Case-equivalent alias"
else
    printf '%s\n' "Skipped case-equivalent alias test: test volume demonstrated case-sensitive names."
fi
rm -f "$case_probe"

unicode_store="$test_dir/ᾀ.json"
unicode_variant="$test_dir/ἈΙ.json"
cp "$profile_store" "$unicode_store"
if [ -e "$unicode_variant" ]; then
    "$cli_path" --config "$unicode_variant" --left-sensitivity 6.75 \
        --write-config "$unicode_store" >"$stdout_path" 2>"$stderr_path"
    assert_preserved_profiles "$unicode_store" "unicode-equivalent alias"
    assert_preserved_inactive_configurations "$unicode_store" "unicode-equivalent-alias"
    assert_active_sensitivity "$unicode_store" 6.75 "Unicode-equivalent alias"
else
    printf '%s\n' "Skipped Unicode-equivalent alias test: test volume did not alias the probe names."
fi

parent_alias="$test_dir/parent-alias"
ln -s "$test_dir" "$parent_alias"
"$cli_path" --config "$parent_alias/profiles.json" --left-sensitivity 6.875 \
    --write-config "$profile_store" >"$stdout_path" 2>"$stderr_path"
assert_preserved_profiles "$profile_store" "parent-directory alias"
assert_preserved_inactive_configurations "$profile_store" "parent-directory-alias"
assert_active_sensitivity "$profile_store" 6.875 "Parent-directory alias"

source_before_export="$test_dir/source-before-export.json"
cp "$profile_store" "$source_before_export"

symlink_export="$test_dir/symlink-export.json"
ln -s "$profile_store" "$symlink_export"
"$cli_path" --config "$profile_store" --left-sensitivity 7 \
    --write-config "$symlink_export" >"$stdout_path" 2>"$stderr_path"
if ! cmp -s "$profile_store" "$source_before_export"; then
    echo "Final-symlink export modified the canonical source." >&2
    exit 1
fi
if [ -L "$symlink_export" ]; then
    echo "Atomic canonical export did not replace the destination symlink." >&2
    exit 1
fi
assert_preserved_profiles "$symlink_export" "final-symlink export"
assert_preserved_inactive_configurations "$symlink_export" "final-symlink-export"
assert_active_sensitivity "$symlink_export" 7 "Final-symlink export"

hardlink_export="$test_dir/hardlink-export.json"
ln "$profile_store" "$hardlink_export"
"$cli_path" --config "$profile_store" --left-sensitivity 7.5 \
    --write-config "$hardlink_export" >"$stdout_path" 2>"$stderr_path"
if ! cmp -s "$profile_store" "$source_before_export"; then
    echo "Hard-link export modified the canonical source." >&2
    exit 1
fi
assert_preserved_profiles "$hardlink_export" "hard-link export"
assert_preserved_inactive_configurations "$hardlink_export" "hard-link-export"
assert_active_sensitivity "$hardlink_export" 7.5 "Hard-link export"

distinct_export="$test_dir/distinct-export.json"
"$cli_path" --config "$profile_store" --left-sensitivity 8 \
    --write-config "$distinct_export" >"$stdout_path" 2>"$stderr_path"
if ! cmp -s "$profile_store" "$source_before_export"; then
    echo "Distinct canonical export modified the canonical source." >&2
    exit 1
fi
assert_preserved_profiles "$distinct_export" "distinct canonical export"
assert_preserved_inactive_configurations "$distinct_export" "distinct-canonical-export"
assert_active_sensitivity "$distinct_export" 8 "Distinct canonical export"

legacy_in_place="$test_dir/legacy-in-place.json"
printf '%s\n' '{"left":{"mode":"mouse"},"right":{"mode":"scroll"}}' >"$legacy_in_place"
"$cli_path" --config "$legacy_in_place" --left-sensitivity 9 \
    --write-config "$legacy_in_place" >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$legacy_in_place" --list-profiles >"$stdout_path" 2>"$stderr_path"
if [ "$(wc -l < "$stdout_path" | tr -d ' ')" -ne 2 ] \
    || ! grep -Fq 'CLI configuration' "$stdout_path"; then
    echo "In-place legacy conversion did not create the expected canonical document." >&2
    exit 1
fi
"$cli_path" --config "$legacy_in_place" --show-config >"$stdout_path" 2>"$stderr_path"
if ! grep -Fq '"sensitivity" : 9' "$stdout_path"; then
    echo "In-place legacy conversion did not persist the effective configuration." >&2
    exit 1
fi

uuid_name_store="$test_dir/uuid-name-store.json"
sed 's/"name" : "CLI configuration"/"name" : "00000000-0000-0000-0000-000000000001"/' \
    "$profile_store" >"$uuid_name_store"
if ! grep -Fq '"name" : "00000000-0000-0000-0000-000000000001"' "$uuid_name_store"; then
    echo "UUID-shaped name fixture was not created." >&2
    exit 1
fi
cp "$uuid_name_store" "$uuid_name_store.before"
set +e
"$cli_path" --profile-store "$uuid_name_store" --list-profiles \
    >"$stdout_path" 2>"$stderr_path"
uuid_name_status=$?
set -e
if [ "$uuid_name_status" -ne 2 ] \
    || ! grep -Fq 'Profile names cannot be UUIDs' "$stderr_path"; then
    echo "UUID-shaped imported profile name was not rejected clearly." >&2
    exit 1
fi
if ! cmp -s "$uuid_name_store" "$uuid_name_store.before"; then
    echo "UUID-shaped imported profile rejection modified the source document." >&2
    exit 1
fi

profile_id_upper=$(printf '%s' "$profile_id" | tr '[:lower:]' '[:upper:]')
"$cli_path" --profile-store "$profile_store" --select-profile Default \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$profile_store" --select-profile "$profile_id_upper" \
    >"$stdout_path" 2>"$stderr_path"
"$cli_path" --profile-store "$profile_store" --list-profiles >"$stdout_path" 2>"$stderr_path"
if ! grep -Fq "*$(printf '\t')CLI configuration$(printf '\t')$profile_id" "$stdout_path"; then
    echo "Stable-ID selection did not treat UUID text case as one identity." >&2
    exit 1
fi

selection_stderr="$test_dir/selection-stderr"
set +e
"$cli_path" --profile-store "$profile_store" --select-profile Missing \
    >"$stdout_path" 2>"$selection_stderr"
selection_status=$?
"$cli_path" --profile-store "$profile_store" --list-profiles --dry-run \
    >"$stdout_path" 2>"$stderr_path"
mutual_status=$?
set -e
if [ "$selection_status" -ne 2 ] || ! grep -Fq 'No profile matches Missing' "$selection_stderr"; then
    echo "Unknown profile selection did not return the actionable error." >&2
    exit 1
fi
if [ "$mutual_status" -ne 2 ] || ! grep -Fq 'cannot be combined' "$stderr_path"; then
    echo "Profile operation mutual exclusion did not exit 2." >&2
    exit 1
fi

repeated_store_a="$test_dir/repeated-store-a.json"
repeated_store_b="$test_dir/repeated-store-b.json"
cp "$profile_store" "$repeated_store_a"
printf '%s\n' '{"sentinel":"second store must remain unchanged"}' >"$repeated_store_b"
cp "$repeated_store_a" "$repeated_store_a.before"
cp "$repeated_store_b" "$repeated_store_b.before"
set +e
"$cli_path" --profile-store "$repeated_store_a" --profile-store "$repeated_store_b" \
    --select-profile Default >"$stdout_path" 2>"$stderr_path"
repeated_store_status=$?
set -e
if [ "$repeated_store_status" -ne 2 ] \
    || ! grep -Fq -- '--profile-store may only be specified once.' "$stderr_path"; then
    echo "Repeated --profile-store did not fail with the duplicate-option diagnostic." >&2
    exit 1
fi
if ! cmp -s "$repeated_store_a" "$repeated_store_a.before" \
    || ! cmp -s "$repeated_store_b" "$repeated_store_b.before"; then
    echo "Repeated --profile-store modified an input or output target." >&2
    exit 1
fi

set +e
"$cli_path" --config "$input_path" --config "$missing_path" --show-config \
    >"$stdout_path" 2>"$stderr_path"
repeated_config_status=$?
set -e
if [ "$repeated_config_status" -ne 2 ] \
    || ! grep -Fq -- '--config may only be specified once.' "$stderr_path"; then
    echo "Repeated --config did not fail before selecting a load source." >&2
    exit 1
fi

printf '%s\n' "Verified strict loading, canonical profiles, UUID-name rejection, list/select, duplicate path rejection, and CLI mapping configuration."
