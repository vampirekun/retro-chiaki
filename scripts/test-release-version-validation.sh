#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-release-version.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/retro-chiaki-version.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

for version in v0.3.0 v1.2.3-rc1 v1.2.3+build.4; do
    actual="$(bash "$VALIDATOR" "$version")"
    if [[ "$actual" != "$version" ]]; then
        echo "validator changed valid version: $version" >&2
        exit 1
    fi
done

for version in "" 0.3.0 v0.3.0/../../tmp "v0.3.0;touch" $'v0.3.0\nnext'; do
    if bash "$VALIDATOR" "$version" >"$TMP_ROOT/invalid.out" 2>&1; then
        echo "validator accepted invalid version: $version" >&2
        exit 1
    fi
done

marker="$TMP_ROOT/injected"
payload="v0.3.0\$(touch $marker)"
if bash "$VALIDATOR" "$payload" >"$TMP_ROOT/payload.out" 2>&1; then
    echo "validator accepted shell syntax in release version" >&2
    exit 1
fi
if [[ -e "$marker" ]]; then
    echo "release version input was evaluated as shell code" >&2
    exit 1
fi

echo "Release version validation tests passed (synthetic inputs only)."
