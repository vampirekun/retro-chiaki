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

HOST_LIBRARY_PATTERN='(^|/)libSDL2-2\.0\.so\.0$|(^|/)libasound\.so\.2
    echo "KNULLI package must not bundle host SDL or ALSA libraries" >&2
    exit 1
fi

unzip -q "$PACKAGE" -d "$WORK_ROOT/extracted"
test -x "$WORK_ROOT/extracted/roms/ports/Chiaki.sh"
test -x "$WORK_ROOT/extracted/roms/ports/chiaki/chiaki"
test -x "$WORK_ROOT/extracted/roms/ports/chiaki/chiaki-cli"

SYMLINK_SOURCE="$WORK_ROOT/symlink-source.zip"
ln -s "$WORK_ROOT/base.zip" "$SYMLINK_SOURCE"
SYMLINK_SOURCE_OUTPUT="$WORK_ROOT/symlink-source-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$SYMLINK_SOURCE" "symlink-source" "$SYMLINK_SOURCE_OUTPUT" > "$WORK_ROOT/symlink-source.log" 2>&1; then
    echo "converter unexpectedly accepted a symlink source archive" >&2
    exit 1
fi
if ! grep -q "regular, non-symlink file" "$WORK_ROOT/symlink-source.log"; then
    echo "converter rejected the symlink source archive for an unexpected reason" >&2
    cat "$WORK_ROOT/symlink-source.log" >&2
    exit 1
fi
if [ -e "$SYMLINK_SOURCE_OUTPUT" ]; then
    echo "converter created output before rejecting the symlink source archive" >&2
    exit 1
fi

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

NUL_NAME_ZIP="$WORK_ROOT/nul-name.zip"
python3 - "$NUL_NAME_ZIP" <<'PY'
import struct
import sys
import zlib

name = b"ports/chiaki/harmless.txt\x00/../../escaped.txt"
data = b"must not be extracted"
crc = zlib.crc32(data) & 0xffffffff
local = struct.pack(
    "<IHHHHHIIIHH",
    0x04034b50, 20, 0, 0, 0, 0, crc, len(data), len(data), len(name), 0
) + name + data
central = struct.pack(
    "<IHHHHHHIIIHHHHHII",
    0x02014b50, 0x0314, 20, 0, 0, 0, 0, crc, len(data), len(data),
    len(name), 0, 0, 0, 0, 0o100644 << 16, 0
) + name
eocd = struct.pack(
    "<IHHHHIIH", 0x06054b50, 0, 0, 1, 1, len(central), len(local), 0
)
with open(sys.argv[1], "wb") as archive:
    archive.write(local + central + eocd)
PY
NUL_NAME_OUTPUT="$WORK_ROOT/nul-name-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$NUL_NAME_ZIP" "nul-name" "$NUL_NAME_OUTPUT" > "$WORK_ROOT/nul-name.log" 2>&1; then
    echo "converter unexpectedly accepted a ZIP entry with an embedded NUL" >&2
    exit 1
fi
if ! grep -q "NUL-containing name" "$WORK_ROOT/nul-name.log"; then
    echo "converter rejected the NUL-name archive for an unexpected reason" >&2
    cat "$WORK_ROOT/nul-name.log" >&2
    exit 1
fi
if [ -e "$NUL_NAME_OUTPUT" ]; then
    echo "converter created output before rejecting the NUL-name archive" >&2
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

FILE_PARENT_ZIP="$WORK_ROOT/file-parent-conflict.zip"
python3 - "$FILE_PARENT_ZIP" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("ports/chiaki", "regular file")
    archive.writestr("ports/chiaki/child.txt", "nested entry")
PY
FILE_PARENT_OUTPUT="$WORK_ROOT/file-parent-conflict-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$FILE_PARENT_ZIP" "file-parent-conflict" "$FILE_PARENT_OUTPUT" > "$WORK_ROOT/file-parent-conflict.log" 2>&1; then
    echo "converter unexpectedly accepted an entry nested beneath a regular file" >&2
    exit 1
fi
if ! grep -q "nested beneath a regular file" "$WORK_ROOT/file-parent-conflict.log"; then
    echo "converter rejected the file-parent archive for an unexpected reason" >&2
    cat "$WORK_ROOT/file-parent-conflict.log" >&2
    exit 1
fi
if [ -e "$FILE_PARENT_OUTPUT" ]; then
    echo "converter created output before rejecting a file-parent conflict" >&2
    exit 1
fi

CHILD_FILE_ZIP="$WORK_ROOT/child-file-conflict.zip"
python3 - "$CHILD_FILE_ZIP" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("ports/chiaki/child.txt", "nested entry")
    archive.writestr("ports/chiaki", "regular file")
PY
CHILD_FILE_OUTPUT="$WORK_ROOT/child-file-conflict-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$CHILD_FILE_ZIP" "child-file-conflict" "$CHILD_FILE_OUTPUT" > "$WORK_ROOT/child-file-conflict.log" 2>&1; then
    echo "converter unexpectedly accepted a regular file that conflicts with earlier nested entries" >&2
    exit 1
fi
if ! grep -q "regular file conflicts with nested entries" "$WORK_ROOT/child-file-conflict.log"; then
    echo "converter rejected the child-file archive for an unexpected reason" >&2
    cat "$WORK_ROOT/child-file-conflict.log" >&2
    exit 1
fi
if [ -e "$CHILD_FILE_OUTPUT" ]; then
    echo "converter created output before rejecting a child-file conflict" >&2
    exit 1
fi

echo "KNULLI package converter smoke tests passed"

for forbidden_library in \
    'roms/ports/chiaki/libs/libSDL2-2.0.so.0' \
    'roms/ports/chiaki/libs/libasound.so.2'
do
    if ! printf '%s\\n' "$forbidden_library" | grep -Eq "$HOST_LIBRARY_PATTERN"; then
        echo "host-library guard failed to recognize: $forbidden_library" >&2
        exit 1
    fi
done

if grep -Eq "$HOST_LIBRARY_PATTERN" "$WORK_ROOT/package-entries.txt"; then
    echo "KNULLI package must not bundle host SDL or ALSA libraries" >&2
    exit 1
fi
    echo "KNULLI package must not bundle host SDL or ALSA libraries" >&2
    exit 1
fi

unzip -q "$PACKAGE" -d "$WORK_ROOT/extracted"
test -x "$WORK_ROOT/extracted/roms/ports/Chiaki.sh"
test -x "$WORK_ROOT/extracted/roms/ports/chiaki/chiaki"
test -x "$WORK_ROOT/extracted/roms/ports/chiaki/chiaki-cli"

SYMLINK_SOURCE="$WORK_ROOT/symlink-source.zip"
ln -s "$WORK_ROOT/base.zip" "$SYMLINK_SOURCE"
SYMLINK_SOURCE_OUTPUT="$WORK_ROOT/symlink-source-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$SYMLINK_SOURCE" "symlink-source" "$SYMLINK_SOURCE_OUTPUT" > "$WORK_ROOT/symlink-source.log" 2>&1; then
    echo "converter unexpectedly accepted a symlink source archive" >&2
    exit 1
fi
if ! grep -q "regular, non-symlink file" "$WORK_ROOT/symlink-source.log"; then
    echo "converter rejected the symlink source archive for an unexpected reason" >&2
    cat "$WORK_ROOT/symlink-source.log" >&2
    exit 1
fi
if [ -e "$SYMLINK_SOURCE_OUTPUT" ]; then
    echo "converter created output before rejecting the symlink source archive" >&2
    exit 1
fi

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

NUL_NAME_ZIP="$WORK_ROOT/nul-name.zip"
python3 - "$NUL_NAME_ZIP" <<'PY'
import struct
import sys
import zlib

name = b"ports/chiaki/harmless.txt\x00/../../escaped.txt"
data = b"must not be extracted"
crc = zlib.crc32(data) & 0xffffffff
local = struct.pack(
    "<IHHHHHIIIHH",
    0x04034b50, 20, 0, 0, 0, 0, crc, len(data), len(data), len(name), 0
) + name + data
central = struct.pack(
    "<IHHHHHHIIIHHHHHII",
    0x02014b50, 0x0314, 20, 0, 0, 0, 0, crc, len(data), len(data),
    len(name), 0, 0, 0, 0, 0o100644 << 16, 0
) + name
eocd = struct.pack(
    "<IHHHHIIH", 0x06054b50, 0, 0, 1, 1, len(central), len(local), 0
)
with open(sys.argv[1], "wb") as archive:
    archive.write(local + central + eocd)
PY
NUL_NAME_OUTPUT="$WORK_ROOT/nul-name-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$NUL_NAME_ZIP" "nul-name" "$NUL_NAME_OUTPUT" > "$WORK_ROOT/nul-name.log" 2>&1; then
    echo "converter unexpectedly accepted a ZIP entry with an embedded NUL" >&2
    exit 1
fi
if ! grep -q "NUL-containing name" "$WORK_ROOT/nul-name.log"; then
    echo "converter rejected the NUL-name archive for an unexpected reason" >&2
    cat "$WORK_ROOT/nul-name.log" >&2
    exit 1
fi
if [ -e "$NUL_NAME_OUTPUT" ]; then
    echo "converter created output before rejecting the NUL-name archive" >&2
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

FILE_PARENT_ZIP="$WORK_ROOT/file-parent-conflict.zip"
python3 - "$FILE_PARENT_ZIP" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("ports/chiaki", "regular file")
    archive.writestr("ports/chiaki/child.txt", "nested entry")
PY
FILE_PARENT_OUTPUT="$WORK_ROOT/file-parent-conflict-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$FILE_PARENT_ZIP" "file-parent-conflict" "$FILE_PARENT_OUTPUT" > "$WORK_ROOT/file-parent-conflict.log" 2>&1; then
    echo "converter unexpectedly accepted an entry nested beneath a regular file" >&2
    exit 1
fi
if ! grep -q "nested beneath a regular file" "$WORK_ROOT/file-parent-conflict.log"; then
    echo "converter rejected the file-parent archive for an unexpected reason" >&2
    cat "$WORK_ROOT/file-parent-conflict.log" >&2
    exit 1
fi
if [ -e "$FILE_PARENT_OUTPUT" ]; then
    echo "converter created output before rejecting a file-parent conflict" >&2
    exit 1
fi

CHILD_FILE_ZIP="$WORK_ROOT/child-file-conflict.zip"
python3 - "$CHILD_FILE_ZIP" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("ports/chiaki/child.txt", "nested entry")
    archive.writestr("ports/chiaki", "regular file")
PY
CHILD_FILE_OUTPUT="$WORK_ROOT/child-file-conflict-output"
if "$REPO_ROOT/packaging/knulli/build.sh" "$CHILD_FILE_ZIP" "child-file-conflict" "$CHILD_FILE_OUTPUT" > "$WORK_ROOT/child-file-conflict.log" 2>&1; then
    echo "converter unexpectedly accepted a regular file that conflicts with earlier nested entries" >&2
    exit 1
fi
if ! grep -q "regular file conflicts with nested entries" "$WORK_ROOT/child-file-conflict.log"; then
    echo "converter rejected the child-file archive for an unexpected reason" >&2
    cat "$WORK_ROOT/child-file-conflict.log" >&2
    exit 1
fi
if [ -e "$CHILD_FILE_OUTPUT" ]; then
    echo "converter created output before rejecting a child-file conflict" >&2
    exit 1
fi

echo "KNULLI package converter smoke tests passed"
