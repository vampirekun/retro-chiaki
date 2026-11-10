#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="${1:-$SCRIPT_DIR/../.github/workflows/release.yml}"

fail() {
    echo "release trigger boundary check failed: $*" >&2
    exit 1
}

[[ -f "$WORKFLOW" ]] || fail "workflow file not found"

checkout_block="$(awk '
    /- uses: actions\/checkout@v4/ { in_checkout = 1; print; next }
    in_checkout && /^      - / { exit }
    in_checkout { print }
' "$WORKFLOW")"
[[ -n "$checkout_block" ]] || fail "release checkout step is missing"
grep -Eq '^[[:space:]]+persist-credentials:[[:space:]]*false[[:space:]]*
events_file="$(mktemp)"
trap 'rm -f "$events_file"' EXIT

awk '
    /^on:[[:space:]]*$/ { in_on = 1; next }
    in_on && /^[^[:space:]#]/ { exit }
    in_on { print }
' "$WORKFLOW" > "$events_file"

[[ -s "$events_file" ]] || fail "missing top-level on block"

events="$(awk '/^  [[:alnum:]_-]+:[[:space:]]*$/ { name=$1; sub(/:$/, "", name); print name }' "$events_file" | sort)"
expected_events="$(printf 'push\nworkflow_dispatch')"
[[ "$events" == "$expected_events" ]] || fail "expected only push and workflow_dispatch events; found: ${events//$'\n'/, }"

grep -Eq '^    tags:[[:space:]]*$' "$events_file" || fail "tag push filter is missing"
grep -Fq "      - 'v*'" "$events_file" || fail "push tags must be restricted to v*"
if grep -Eq '^    branches([[:space:]]|:)' "$events_file"; then
    fail "release workflow must not run on branch pushes"
fi

release_guard="$(grep -A4 -F '      - name: Create GitHub Release' "$WORKFLOW" | grep -F 'if:' | sed 's/^[[:space:]]*//')"
[[ "$release_guard" == "if: github.event_name == 'push'" ]] || fail "GitHub Release step must be guarded to tag pushes"

upload_guard="$(grep -A4 -F '      - name: Upload build artifact (workflow_dispatch test runs)' "$WORKFLOW" | grep -F 'if:' | sed 's/^[[:space:]]*//')"
[[ "$upload_guard" == "if: github.event_name == 'workflow_dispatch'" ]] || fail "manual validation artifact must be guarded to workflow_dispatch"

echo "Release trigger boundaries passed (tag push publishes; manual dispatch uploads artifact; no PR/branch trigger)."
 <<< "$checkout_block" || fail "release checkout must not persist the write-capable GitHub token into the build workspace"

events_file="$(mktemp)"
trap 'rm -f "$events_file"' EXIT

awk '
    /^on:[[:space:]]*$/ { in_on = 1; next }
    in_on && /^[^[:space:]#]/ { exit }
    in_on { print }
' "$WORKFLOW" > "$events_file"

[[ -s "$events_file" ]] || fail "missing top-level on block"

events="$(awk '/^  [[:alnum:]_-]+:[[:space:]]*$/ { name=$1; sub(/:$/, "", name); print name }' "$events_file" | sort)"
expected_events="$(printf 'push\nworkflow_dispatch')"
[[ "$events" == "$expected_events" ]] || fail "expected only push and workflow_dispatch events; found: ${events//$'\n'/, }"

grep -Eq '^    tags:[[:space:]]*$' "$events_file" || fail "tag push filter is missing"
grep -Fq "      - 'v*'" "$events_file" || fail "push tags must be restricted to v*"
if grep -Eq '^    branches([[:space:]]|:)' "$events_file"; then
    fail "release workflow must not run on branch pushes"
fi

release_guard="$(grep -A4 -F '      - name: Create GitHub Release' "$WORKFLOW" | grep -F 'if:' | sed 's/^[[:space:]]*//')"
[[ "$release_guard" == "if: github.event_name == 'push'" ]] || fail "GitHub Release step must be guarded to tag pushes"

upload_guard="$(grep -A4 -F '      - name: Upload build artifact (workflow_dispatch test runs)' "$WORKFLOW" | grep -F 'if:' | sed 's/^[[:space:]]*//')"
[[ "$upload_guard" == "if: github.event_name == 'workflow_dispatch'" ]] || fail "manual validation artifact must be guarded to workflow_dispatch"

echo "Release trigger boundaries passed (tag push publishes; manual dispatch uploads artifact; no PR/branch trigger)."
