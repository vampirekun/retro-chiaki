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

1. runs the synthetic checksum-manifest regression guard;
2. cross-compiles Chiaki and the Mali shim;
3. assembles the complete dependency archive;
4. converts it to the KNULLI package;
5. verifies the package layout and that bundled SDL and ALSA are absent;
6. generates `dist/SHA256SUMS` for the single KNULLI ZIP;
7. creates a GitHub Release containing both the KNULLI ZIP and `SHA256SUMS`.

A manual `workflow_dispatch` run performs the build and package checks but
does **not** create a GitHub Release. Instead, it uploads the ZIP files and
`SHA256SUMS` as a downloadable Actions artifact for validation.

The release workflow is intentionally limited to `v*` tag pushes and manual
dispatches; pull requests do not publish packages or releases. The checksum
guard runs immediately after checkout, before the ARM64 toolchain and
cross-compilation dependencies are installed.

## Package verification

Before publishing, inspect the archive:

```bash
unzip -l dist/*knulli-h700.zip | grep -E 'Chiaki.sh|chiaki$|libSDL2|libasound'
```

The archive must contain `roms/ports/Chiaki.sh` and
`roms/ports/chiaki/chiaki`. It must not contain active copies of
`libSDL2-2.0.so.0` or `libasound.so.2` because KNULLI supplies both.

Verify the generated checksum manifest from the distribution directory:

```bash
(cd dist && sha256sum --check SHA256SUMS)
```

The manifest contains exactly the generated KNULLI ZIP, not itself. It is
removed before validation begins and is only replaced after a successful
checksum calculation and self-check. A failed run must not leave a stale
manifest that could be mistaken for evidence about a new package.

## Package converter smoke test

On Linux, the native CTest suite also runs `packaging/knulli/test-build.sh`.
Before extraction, the Bash converter validates the source ZIP and rejects
absolute or parent-directory paths, backslashes, duplicate/case-colliding
entries, symlinks, special files, and encrypted entries. The smoke test creates
temporary valid and hostile fixture archives, exercises the converter, checks
the output layout and executable bits, verifies that host SDL/ALSA libraries
are removed, and confirms that unsafe archives and missing required inputs
fail before an output directory is created. This does not replace the full
AArch64 cross-compile or hardware testing.

Run it directly with:

```bash
bash packaging/knulli/test-build.sh
```

For reproducible releases, record the source commit and ZIP checksum in the
release notes.
