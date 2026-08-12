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

echo "Verified strict loading and mouse acceleration CLI configuration."
