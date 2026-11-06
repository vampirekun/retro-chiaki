#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "$WORK_ROOT"' EXIT

SOURCE_ROOT="$WORK_ROOT/source"
GAME_DIR="$SOURCE_ROOT/ports/chiaki"
mkdir -p "$GAME_DIR/libs"

printf '%s\n' '#!/bin/sh' 'exit 0' > "$GAME_DIR/chiaki"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$GAME_DIR/chiaki-cli"
printf '%s\n' 'fixture controller mapping' > "$GAME_DIR/chiaki.gptk"
printf '%s\n' 'fixture Mali shim' > "$GAME_DIR/libs/libmaliegl.so"
printf '%s\n' 'host SDL placeholder' > "$GAME_DIR/libs/libSDL2-2.0.so.0"
printf '%s\n' 'host ALSA placeholder' > "$GAME_DIR/libs/libasound.so.2"
chmod +x "$GAME_DIR/chiaki" "$GAME_DIR/chiaki-cli"

(cd "$SOURCE_ROOT" && zip -qr "$WORK_ROOT/base.zip" ports)
OUTPUT_DIR="$WORK_ROOT/output"
"$REPO_ROOT/packaging/knulli/build.sh" "$WORK_ROOT/base.zip" "smoke-test" "$OUTPUT_DIR" > "$WORK_ROOT/build.log"

PACKAGE="$OUTPUT_DIR/retro-chiaki-smoke-test-portmaster-knulli-h700.zip"
test -s "$PACKAGE"
unzip -Z1 "$PACKAGE" > "$WORK_ROOT/package-entries.txt"

for expected in \
    "roms/ports/Chiaki.sh" \
    "roms/ports/chiaki/chiaki" \
    "roms/ports/chiaki/chiaki-cli" \
    "roms/ports/chiaki/chiaki.gptk" \
    "roms/ports/chiaki/KNULLI-README.txt"
do
    if ! grep -Fxq "$expected" "$WORK_ROOT/package-entries.txt"; then
        echo "expected package entry is missing: $expected" >&2
        exit 1
    fi
done

if grep -Eq '(^|/)libSDL2-2.0\.so\.0$|(^|/)libasound\.so\.2$' "$WORK_ROOT/package-entries.txt"; then
    echo "KNULLI package must not bundle host SDL or ALSA libraries" >&2
    exit 1
fi

unzip -q "$PACKAGE" -d "$WORK_ROOT/extracted"
test -x "$WORK_ROOT/extracted/roms/ports/Chiaki.sh"
test -x "$WORK_ROOT/extracted/roms/ports/chiaki/chiaki"
test -x "$WORK_ROOT/extracted/roms/ports/chiaki/chiaki-cli"

INCOMPLETE_ROOT="$WORK_ROOT/incomplete"
mkdir -p "$INCOMPLETE_ROOT/ports/chiaki"
printf '%s\n' 'incomplete fixture' > "$INCOMPLETE_ROOT/ports/chiaki/chiaki"
(cd "$INCOMPLETE_ROOT" && zip -qr "$WORK_ROOT/incomplete.zip" ports)

if "$REPO_ROOT/packaging/knulli/build.sh" "$WORK_ROOT/incomplete.zip" "missing-input" "$WORK_ROOT/failure-output" > "$WORK_ROOT/missing-input.log" 2>&1; then
    echo "converter unexpectedly accepted an incomplete source archive" >&2
    exit 1
fi

if ! grep -q "required package input is missing" "$WORK_ROOT/missing-input.log"; then
    echo "converter failed for an unexpected reason on the incomplete fixture" >&2
    cat "$WORK_ROOT/missing-input.log" >&2
    exit 1
fi

UNSAFE_OUTPUT="$WORK_ROOT/unsafe-version-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$WORK_ROOT/base.zip" "../escape" "$UNSAFE_OUTPUT" > "$WORK_ROOT/unsafe-version.log" 2>&1; then
    echo "converter unexpectedly accepted a path-like version" >&2
    exit 1
fi
if ! grep -q "invalid version" "$WORK_ROOT/unsafe-version.log"; then
    echo "converter rejected an unsafe version for an unexpected reason" >&2
    cat "$WORK_ROOT/unsafe-version.log" >&2
    exit 1
fi
if [ -e "$UNSAFE_OUTPUT" ]; then
    echo "converter created the output directory before rejecting the version" >&2
    exit 1
fi


PATH_TRAVERSAL_ZIP="$WORK_ROOT/path-traversal.zip"
python3 - "$PATH_TRAVERSAL_ZIP" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("ports/chiaki/../../escaped.txt", "must not be extracted")
PY
PATH_TRAVERSAL_OUTPUT="$WORK_ROOT/path-traversal-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$PATH_TRAVERSAL_ZIP" "path-traversal" "$PATH_TRAVERSAL_OUTPUT" > "$WORK_ROOT/path-traversal.log" 2>&1; then
    echo "converter unexpectedly accepted a parent-directory ZIP entry" >&2
    exit 1
fi
if ! grep -q "unsafe path component" "$WORK_ROOT/path-traversal.log"; then
    echo "converter rejected the traversal archive for an unexpected reason" >&2
    cat "$WORK_ROOT/path-traversal.log" >&2
    exit 1
fi
if [ -e "$PATH_TRAVERSAL_OUTPUT" ]; then
    echo "converter created output before rejecting the traversal archive" >&2
    exit 1
fi

SYMLINK_ZIP="$WORK_ROOT/symlink-entry.zip"
python3 - "$SYMLINK_ZIP" <<'PY'
import stat
import sys
import zipfile

entry = zipfile.ZipInfo("ports/chiaki/libs/external-link")
entry.create_system = 3
entry.external_attr = (stat.S_IFLNK | 0o777) << 16
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr(entry, "../../outside")
PY
SYMLINK_OUTPUT="$WORK_ROOT/symlink-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$SYMLINK_ZIP" "symlink-entry" "$SYMLINK_OUTPUT" > "$WORK_ROOT/symlink-entry.log" 2>&1; then
    echo "converter unexpectedly accepted a symlink ZIP entry" >&2
    exit 1
fi
if ! grep -q "symlink or special file" "$WORK_ROOT/symlink-entry.log"; then
    echo "converter rejected the symlink archive for an unexpected reason" >&2
    cat "$WORK_ROOT/symlink-entry.log" >&2
    exit 1
fi
if [ -e "$SYMLINK_OUTPUT" ]; then
    echo "converter created output before rejecting the symlink archive" >&2
    exit 1
fi

CASE_COLLISION_ZIP="$WORK_ROOT/case-collision.zip"
python3 - "$CASE_COLLISION_ZIP" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("ports/chiaki/Readme.txt", "first")
    archive.writestr("ports/chiaki/README.TXT", "second")
PY
CASE_COLLISION_OUTPUT="$WORK_ROOT/case-collision-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$CASE_COLLISION_ZIP" "case-collision" "$CASE_COLLISION_OUTPUT" > "$WORK_ROOT/case-collision.log" 2>&1; then
    echo "converter unexpectedly accepted case-colliding ZIP entries" >&2
    exit 1
fi
if ! grep -q "duplicate or case-colliding entry" "$WORK_ROOT/case-collision.log"; then
    echo "converter rejected the case-collision archive for an unexpected reason" >&2
    cat "$WORK_ROOT/case-collision.log" >&2
    exit 1
fi
if [ -e "$CASE_COLLISION_OUTPUT" ]; then
    echo "converter created output before rejecting case-colliding entries" >&2
    exit 1
fi

echo "KNULLI package converter smoke tests passed"
