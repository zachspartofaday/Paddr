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

echo "Verified strict loading, canonical profiles, list/select, and CLI mapping configuration."
