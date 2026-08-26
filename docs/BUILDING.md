# Building Retro Chiaki for KNULLI

The application is cross-compiled for AArch64 with Ubuntu 22.04. KNULLI uses
the same binary as the base H700 PortMaster build, but requires a different
launcher and package contents.

## Local AArch64 build

Build the toolchain image and binaries with Docker:

```bash
docker build -t retro-chiaki-arm64 packaging/build
mkdir -p dist-build
docker run --rm \
  -v "$PWD:/chiaki-local:ro" \
  -v "$PWD/dist-build:/output" \
  retro-chiaki-arm64 bash /chiaki-local/packaging/build/build.sh
```

The GUI and CLI binaries are written to `dist-build/`.

## Create a KNULLI package on Windows

`packaging/knulli/build.ps1` converts a complete base PortMaster release ZIP
into the KNULLI layout. The source ZIP must contain `ports/chiaki/`, including
the binaries, Qt libraries, XKB data, and `libmaliegl.so`.

```powershell
pwsh -File packaging/knulli/build.ps1 `
  -SourceZip dist/retro-chiaki-v0.3.2-portmaster-muos-h700.zip `
  -Version v0.3.2-knulli1 `
  -OutputDirectory dist
```

The converter installs the KNULLI launcher and gptokeyb configuration, changes
the archive layout to `roms/ports`, and removes Ubuntu's SDL and ALSA libraries.

## Create a KNULLI package on Linux

Use the equivalent Bash converter:

```bash
packaging/knulli/build.sh \
  dist/retro-chiaki-v0.3.2-portmaster-muos-h700.zip \
  v0.3.2-knulli1 \
  dist
```

## GitHub Actions releases

Pushing a `v*` tag runs `.github/workflows/release.yml`. The workflow:

1. cross-compiles Chiaki and the Mali shim;
2. assembles the complete dependency archive;
3. converts it to the KNULLI package;
4. verifies that bundled SDL and ALSA are absent;
5. publishes only the KNULLI ZIP.

`workflow_dispatch` performs the same build without creating a release.

## Package verification

Before publishing, check the archive:

```bash
unzip -l dist/*knulli-h700.zip | grep -E 'Chiaki.sh|chiaki$|libSDL2|libasound'
sha256sum dist/*knulli-h700.zip
```

The archive must contain `roms/ports/Chiaki.sh` and
`roms/ports/chiaki/chiaki`. It must not contain active copies of
`libSDL2-2.0.so.0` or `libasound.so.2` because KNULLI supplies both.

For reproducible releases, record the source commit and ZIP checksum in the
release notes.
