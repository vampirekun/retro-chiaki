#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/write-release-checksum-manifest.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/retro-chiaki-checksum.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

empty_dir="$TMP_ROOT/empty"
mkdir -p "$empty_dir"
if bash "$HELPER" "$empty_dir" >"$TMP_ROOT/empty.log" 2>&1; then
    echo "checksum helper accepted a directory without a KNULLI package" >&2
    exit 1
fi
if [[ -e "$empty_dir/SHA256SUMS" ]]; then
    echo "checksum helper created a manifest without a package" >&2
    exit 1
fi

multiple_dir="$TMP_ROOT/multiple"
mkdir -p "$multiple_dir"
printf 'first package\n' > "$multiple_dir/first-portmaster-knulli-h700.zip"
printf 'second package\n' > "$multiple_dir/second-portmaster-knulli-h700.zip"
if bash "$HELPER" "$multiple_dir" >"$TMP_ROOT/multiple.log" 2>&1; then
    echo "checksum helper accepted multiple KNULLI packages" >&2
    exit 1
fi
if [[ -e "$multiple_dir/SHA256SUMS" ]]; then
    echo "checksum helper created a manifest for an ambiguous package set" >&2
    exit 1
fi

single_dir="$TMP_ROOT/single package with spaces"
mkdir -p "$single_dir"
package="retro-chiaki-v0.3.2-portmaster-knulli-h700.zip"
printf 'synthetic release package\n' > "$single_dir/$package"
bash "$HELPER" "$single_dir" >"$TMP_ROOT/single.log"
grep -Fq "  $package" "$single_dir/SHA256SUMS"
(
    cd "$single_dir"
    sha256sum --check SHA256SUMS >/dev/null
)

echo "Release checksum manifest tests passed (synthetic files only)."
