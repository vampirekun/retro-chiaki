#!/usr/bin/env bash
set -euo pipefail

DIST_DIR="${1:-dist}"
if [[ ! -d "$DIST_DIR" ]]; then
    echo "distribution directory does not exist: $DIST_DIR" >&2
    exit 2
fi

DIST_DIR="$(cd "$DIST_DIR" && pwd)"
manifest="$DIST_DIR/SHA256SUMS"

# This script owns the generated manifest. Invalidate stale output before
# validating the package set so a failed run cannot leave misleading checksums.
rm -f -- "$manifest"
tmp_manifest="$(mktemp "$DIST_DIR/.SHA256SUMS.XXXXXX")"
cleanup() {
    rm -f -- "$tmp_manifest"
}
trap cleanup EXIT

shopt -s nullglob
packages=("$DIST_DIR"/*portmaster-knulli-h700.zip)
if [[ "${#packages[@]}" -ne 1 ]]; then
    echo "expected exactly one KNULLI package, found ${#packages[@]}" >&2
    exit 1
fi

package="${packages[0]##*/}"
(
    cd "$DIST_DIR"
    sha256sum -- "$package" > "$tmp_manifest"
    sha256sum --check "$tmp_manifest"
)

mv -- "$tmp_manifest" "$manifest"
trap - EXIT
cat "$manifest"
