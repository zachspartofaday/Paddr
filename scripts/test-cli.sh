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

echo "Verified strict explicit CLI configuration loading."
