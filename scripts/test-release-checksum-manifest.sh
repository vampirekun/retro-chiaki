#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/write-release-checksum-manifest.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/retro-chiaki-checksum.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_no_temporary_manifest() {
    local directory="$1"
    if find "$directory" -maxdepth 1 -type f -name '.SHA256SUMS.*' -print -quit | grep -q .; then
        echo "checksum helper left a temporary manifest in $directory" >&2
        exit 1
    fi
}

empty_dir="$TMP_ROOT/empty"
mkdir -p "$empty_dir"
printf 'stale checksum\n' > "$empty_dir/SHA256SUMS"
if bash "$HELPER" "$empty_dir" >"$TMP_ROOT/empty.log" 2>&1; then
    echo "checksum helper accepted a directory without a KNULLI package" >&2
    exit 1
fi
if [[ -e "$empty_dir/SHA256SUMS" ]]; then
    echo "checksum helper left a stale manifest without a package" >&2
    exit 1
fi
assert_no_temporary_manifest "$empty_dir"

multiple_dir="$TMP_ROOT/multiple"
mkdir -p "$multiple_dir"
printf 'first package\n' > "$multiple_dir/first-portmaster-knulli-h700.zip"
printf 'second package\n' > "$multiple_dir/second-portmaster-knulli-h700.zip"
printf 'stale checksum\n' > "$multiple_dir/SHA256SUMS"
if bash "$HELPER" "$multiple_dir" >"$TMP_ROOT/multiple.log" 2>&1; then
    echo "checksum helper accepted multiple KNULLI packages" >&2
    exit 1
fi
if [[ -e "$multiple_dir/SHA256SUMS" ]]; then
    echo "checksum helper left a stale manifest for an ambiguous package set" >&2
    exit 1
fi
assert_no_temporary_manifest "$multiple_dir"

symlink_dir="$TMP_ROOT/symlink"
mkdir -p "$symlink_dir"
printf 'external package\n' > "$TMP_ROOT/external-package.zip"
ln -s "$TMP_ROOT/external-package.zip" "$symlink_dir/external-portmaster-knulli-h700.zip"
printf 'stale checksum\n' > "$symlink_dir/SHA256SUMS"
if bash "$HELPER" "$symlink_dir" >"$TMP_ROOT/symlink.log" 2>&1; then
    echo "checksum helper accepted a symlinked KNULLI package" >&2
    exit 1
fi
if [[ -e "$symlink_dir/SHA256SUMS" ]]; then
    echo "checksum helper left a stale manifest for a symlinked package" >&2
    exit 1
fi
assert_no_temporary_manifest "$symlink_dir"

directory_dir="$TMP_ROOT/directory"
mkdir -p "$directory_dir/fake-portmaster-knulli-h700.zip"
printf 'stale checksum\n' > "$directory_dir/SHA256SUMS"
if bash "$HELPER" "$directory_dir" >"$TMP_ROOT/directory.log" 2>&1; then
    echo "checksum helper accepted a directory named like a KNULLI package" >&2
    exit 1
fi
if [[ -e "$directory_dir/SHA256SUMS" ]]; then
    echo "checksum helper left a stale manifest for a non-file package candidate" >&2
    exit 1
fi
assert_no_temporary_manifest "$directory_dir"

run_checksum_failure_case() {
    local name="$1"
    local failure_mode="$2"
    local directory="$TMP_ROOT/$name"
    local fake_bin="$TMP_ROOT/$name-bin"
    local real_sha256sum

    mkdir -p "$directory" "$fake_bin"
    printf 'synthetic release package\n' > "$directory/failure-portmaster-knulli-h700.zip"
    printf 'stale checksum\n' > "$directory/SHA256SUMS"
    real_sha256sum="$(command -v sha256sum)"

    if [[ "$failure_mode" == "hash" ]]; then
        cat > "$fake_bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "simulated checksum calculation failure" >&2
exit 42
EOF
    else
        cat > "$fake_bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--check" ]]; then
    echo "simulated checksum self-check failure" >&2
    exit 42
fi
exec "$REAL_SHA256SUM" "$@"
EOF
    fi
    chmod +x "$fake_bin/sha256sum"

    if PATH="$fake_bin:$PATH" REAL_SHA256SUM="$real_sha256sum" bash "$HELPER" "$directory" >"$TMP_ROOT/$name.log" 2>&1; then
        echo "checksum helper ignored the simulated $failure_mode failure" >&2
        exit 1
    fi
    if [[ -e "$directory/SHA256SUMS" ]]; then
        echo "checksum helper published a manifest after the simulated $failure_mode failure" >&2
        exit 1
    fi
    assert_no_temporary_manifest "$directory"
}

# A failed hash or failed self-check must leave neither stale output nor a
# temporary manifest behind.
run_checksum_failure_case hash-failure hash
run_checksum_failure_case self-check-failure verify

single_dir="$TMP_ROOT/single package with spaces"
mkdir -p "$single_dir"
package="retro-chiaki-v0.3.2-portmaster-knulli-h700.zip"
printf 'synthetic release package\n' > "$single_dir/$package"
printf 'stale checksum\n' > "$single_dir/SHA256SUMS"
bash "$HELPER" "$single_dir" >"$TMP_ROOT/single.log"
grep -Fq "  $package" "$single_dir/SHA256SUMS"
if [[ "$(grep -c . "$single_dir/SHA256SUMS")" -ne 1 ]]; then
    echo "checksum manifest should contain exactly one package entry" >&2
    exit 1
fi
if grep -q 'SHA256SUMS' "$single_dir/SHA256SUMS"; then
    echo "checksum manifest must not include itself" >&2
    exit 1
fi
assert_no_temporary_manifest "$single_dir"
(
    cd "$single_dir"
    sha256sum --check SHA256SUMS >/dev/null
)

printf 'tampered package\n' > "$single_dir/$package"
if (cd "$single_dir" && sha256sum --check SHA256SUMS >/dev/null 2>&1); then
    echo "checksum manifest failed to detect package tampering" >&2
    exit 1
fi

echo "Release checksum manifest tests passed (synthetic files and injected failures)."
