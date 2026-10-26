#!/usr/bin/env bash
set -euo pipefail

DIST_DIR="${1:-dist}"
if [[ ! -d "$DIST_DIR" ]]; then
    echo "distribution directory does not exist: $DIST_DIR" >&2
    exit 2
fi

DIST_DIR="$(cd "$DIST_DIR" && pwd)"
shopt -s nullglob
packages=("$DIST_DIR"/*portmaster-knulli-h700.zip)
if [[ "${#packages[@]}" -ne 1 ]]; then
    echo "expected exactly one KNULLI package, found ${#packages[@]}" >&2
    exit 1
fi

package="${packages[0]##*/}"
(
    cd "$DIST_DIR"
    sha256sum -- "$package" > SHA256SUMS
    sha256sum --check SHA256SUMS
)
cat "$DIST_DIR/SHA256SUMS"
