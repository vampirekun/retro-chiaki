#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^v[0-9][0-9A-Za-z._+-]*$ ]]; then
    echo "invalid release version; expected v<version> using only letters, digits, dot, underscore, plus or hyphen" >&2
    exit 2
fi

printf '%s\n' "$version"
