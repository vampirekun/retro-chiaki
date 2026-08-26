#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 SOURCE_ZIP VERSION [OUTPUT_DIRECTORY]" >&2
    exit 2
fi

SOURCE_ZIP="$(realpath "$1")"
VERSION="$2"
OUTPUT_DIRECTORY="${3:-dist}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_ROOT="$(mkdir -p "$OUTPUT_DIRECTORY" && cd "$OUTPUT_DIRECTORY" && pwd)"
WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "$WORK_ROOT"' EXIT

SOURCE_ROOT="$WORK_ROOT/source"
STAGE_ROOT="$WORK_ROOT/stage"
SOURCE_GAME_DIR="$SOURCE_ROOT/ports/chiaki"
STAGE_PORTS="$STAGE_ROOT/roms/ports"
STAGE_GAME_DIR="$STAGE_PORTS/chiaki"
OUTPUT_ZIP="$OUTPUT_ROOT/retro-chiaki-${VERSION}-portmaster-knulli-h700.zip"

unzip -q "$SOURCE_ZIP" -d "$SOURCE_ROOT"

for required in \
    "$SOURCE_GAME_DIR/chiaki" \
    "$SOURCE_GAME_DIR/chiaki-cli" \
    "$SOURCE_GAME_DIR/chiaki.gptk" \
    "$SOURCE_GAME_DIR/libs/libmaliegl.so" \
    "$REPO_ROOT/packaging/knulli/roms/ports/Chiaki.sh" \
    "$REPO_ROOT/packaging/knulli/roms/ports/chiaki/chiaki.gptk" \
    "$REPO_ROOT/packaging/knulli/README.txt"
do
    if [ ! -e "$required" ]; then
        echo "required package input is missing: $required" >&2
        exit 1
    fi
done

mkdir -p "$STAGE_PORTS"
cp -a "$SOURCE_GAME_DIR" "$STAGE_GAME_DIR"
cp "$REPO_ROOT/packaging/knulli/roms/ports/Chiaki.sh" "$STAGE_PORTS/Chiaki.sh"
cp "$REPO_ROOT/packaging/knulli/roms/ports/chiaki/chiaki.gptk" \
    "$STAGE_GAME_DIR/chiaki.gptk"
cp "$REPO_ROOT/packaging/knulli/README.txt" \
    "$STAGE_GAME_DIR/KNULLI-README.txt"
chmod +x "$STAGE_PORTS/Chiaki.sh" "$STAGE_GAME_DIR/chiaki" \
    "$STAGE_GAME_DIR/chiaki-cli"

rm -f "$STAGE_GAME_DIR/libs/libSDL2-2.0.so.0" \
    "$STAGE_GAME_DIR/libs/libasound.so.2"

rm -f "$OUTPUT_ZIP"
(cd "$STAGE_ROOT" && zip -qr "$OUTPUT_ZIP" roms -x '*.DS_Store')

echo "$OUTPUT_ZIP"
sha256sum "$OUTPUT_ZIP"
