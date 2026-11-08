#!/usr/bin/env python3
"""Reject unsafe ZIP entries before the KNULLI converter extracts a source archive."""

from __future__ import annotations

import re
import stat
import sys
import zipfile


def reject(message: str) -> int:
    print(f"unsafe source archive: {message}", file=sys.stderr)
    return 2


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} SOURCE_ZIP", file=sys.stderr)
        return 2

    archive_path = sys.argv[1]
    try:
        with zipfile.ZipFile(archive_path) as archive:
            entries = archive.infolist()
            if not entries:
                return reject("archive is empty")

            seen_paths: set[str] = set()
            seen_files: set[str] = set()
            for entry in entries:
                # ZipInfo.filename is truncated at the first NUL by Python.
                # Inspect orig_filename so malformed raw ZIP names cannot bypass
                # this preflight through parser normalization.
                raw_name = entry.orig_filename
                if not raw_name or "\x00" in raw_name:
                    return reject("entry has an empty or NUL-containing name")

                name = entry.filename
                if not name:
                    return reject("entry has an empty or NUL-containing name")
                if "\\" in name or name.startswith("/") or re.match(r"^[A-Za-z]:", name):
                    return reject(f"entry uses an absolute or platform-specific path: {name!r}")

                is_directory = entry.is_dir()
                normalized_name = name[:-1] if is_directory and name.endswith("/") else name
                parts = normalized_name.split("/")
                if not normalized_name or any(part in ("", ".", "..") for part in parts):
                    return reject(f"entry contains an unsafe path component: {name!r}")

                normalized_path = "/".join(parts).casefold()
                if normalized_path in seen_paths:
                    return reject(f"duplicate or case-colliding entry: {name!r}")

                parent_paths = ["/".join(parts[:index]).casefold() for index in range(1, len(parts))]
                if any(parent in seen_files for parent in parent_paths):
                    return reject(f"entry is nested beneath a regular file: {name!r}")
                if not is_directory and any(existing.startswith(normalized_path + "/") for existing in seen_paths):
                    return reject(f"regular file conflicts with nested entries: {name!r}")

                seen_paths.add(normalized_path)
                if not is_directory:
                    seen_files.add(normalized_path)

                unix_mode = (entry.external_attr >> 16) & 0xFFFF
                file_type = stat.S_IFMT(unix_mode)
                expected_type = stat.S_IFDIR if is_directory else stat.S_IFREG
                if file_type not in (0, expected_type):
                    return reject(f"entry is a symlink or special file: {name!r}")
                if entry.flag_bits & 0x1:
                    return reject(f"encrypted entry is not supported: {name!r}")

    except (OSError, zipfile.BadZipFile, zipfile.LargeZipFile) as error:
        return reject(f"cannot read ZIP archive: {error}")

    print(f"Source ZIP passed path/type validation ({len(entries)} entries).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
