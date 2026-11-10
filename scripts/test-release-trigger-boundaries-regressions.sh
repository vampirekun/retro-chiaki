#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/test-release-trigger-boundaries.sh"
WORKFLOW="${1:-$SCRIPT_DIR/../.github/workflows/release.yml}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/retro-chiaki-triggers.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

[[ -f "$WORKFLOW" ]] || { echo "workflow file not found: $WORKFLOW" >&2; exit 1; }

bash "$VALIDATOR" "$WORKFLOW"

expect_rejected() {
    local name="$1"
    local fixture="$TMP_ROOT/$name.yml"
    shift
    "$@" > "$fixture"
    if bash "$VALIDATOR" "$fixture" >"$TMP_ROOT/$name.log" 2>&1; then
        echo "release trigger validator accepted unsafe fixture: $name" >&2
        cat "$TMP_ROOT/$name.log" >&2
        exit 1
    fi
    printf 'Rejected unsafe release-trigger fixture: %s\n' "$name"
}

expect_rejected pull-request-event awk '1; /^  workflow_dispatch:$/ { print "  pull_request:" }' "$WORKFLOW"
expect_rejected branch-push-filter awk '1; /^  push:$/ { print "    branches: [main]" }' "$WORKFLOW"
expect_rejected non-version-tag sed "s/      - 'v\\*'/      - '*'/ " "$WORKFLOW"
expect_rejected unguarded-release sed "s/if: github.event_name == 'push'/if: always()/" "$WORKFLOW"
expect_rejected unguarded-manual-artifact sed "s/if: github.event_name == 'workflow_dispatch'/if: always()/" "$WORKFLOW"

echo "Release trigger boundary regression tests passed (5 unsafe fixtures rejected)."
