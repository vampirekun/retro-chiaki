# Retro Chiaki for KNULLI

PlayStation Remote Play for PS4 and PS5 on the Anbernic RG34XX-SP running
KNULLI.

This fork is a KNULLI-specific adaptation of
[Retro Chiaki](https://github.com/ed-fruty/retro-chiaki), which in turn is based
on [Chiaki 2.2.0](https://git.sr.ht/~thestr4ng3r/chiaki). It provides the EGLFS
video path, controller handling, audio integration, launcher, and packaging
needed to run directly from KNULLI's **Ports** menu.

> This project is not endorsed or certified by Sony Interactive Entertainment.
> You need your own PS4 or PS5, PSN account, and a network with Remote Play
> access to the console.

## Compatibility

The verified configuration is:

- Anbernic RG34XX-SP
- Allwinner H700 / Mali GPU
- 720x480 internal display
- KNULLI Scarab image dated 2026-05-11
- PS5 Remote Play at 540p, 30 FPS, H.264

This edition intentionally targets KNULLI. The original muOS package uses a
different launcher, controller stack, and audio environment. Other H700 models
may work, but their display geometry, controller identifiers, and button order
have not been verified.

## KNULLI changes

- OpenGL ES and EGLFS rendering through the H700 Mali framebuffer.
- Mali EGL compatibility shim with the RGBX8888 configuration required by the
  RG34XX-SP display.
- Runtime framebuffer detection and a UI constrained to the handheld screen.
- `Original` and `Stretch to Screen` video modes.
- Controller polling using KNULLI's raw RG34XX-SP button identifiers.
- Correct Nintendo-label-to-PlayStation face-button mapping.
- Select mapped to PlayStation Share/Create and M mapped to PS Home.
- `M+Start` exit chord in both the interface and an active stream.
- gptokeyb paused only while streaming, avoiding duplicate keyboard and mouse
  input without losing controller events.
- KNULLI system SDL and ALSA libraries, preserving its device patches and
  PipeWire audio-plugin paths.
- PipeWire and PulseAudio socket routing preserved at `/var/run` while Qt uses
  a private runtime directory.
- KNULLI-specific PortMaster layout and packaging scripts.

## Controls

The printed labels on the RG34XX-SP map as follows during Remote Play:

| RG34XX-SP | PlayStation |
|---|---|
| B | Cross |
| A | Circle |
| Y | Square |
| X | Triangle |
| D-pad | D-pad |
| L1 / R1 | L1 / R1 |
| L2 / R2 | L2 / R2 |
| L3 / R3 | L3 / R3 |
| Select | Share / Create |
| Start | Options |
| M | PS Home |
| M + Start | Exit Retro Chiaki |

Before streaming, B confirms, A goes back, and the left stick controls the
mouse pointer.

## Installation

1. Install or update PortMaster in KNULLI.
2. Download `retro-chiaki-v0.3.2-knulli1-portmaster-knulli-h700.zip` from this
   fork's [Releases](https://github.com/vampirekun/retro-chiaki/releases).
3. Extract the archive to the root of KNULLI's userdata/ROM partition. On a
   Windows PC this is the root of the drive containing `roms`, `saves`, and
   `system`.
4. Confirm these files exist:

   ```text
   roms/ports/Chiaki.sh
   roms/ports/chiaki/chiaki
   roms/ports/chiaki/chiaki.gptk
   ```

5. Safely eject the card, start KNULLI, and open **Ports > Chiaki**.

Existing console registrations are stored under KNULLI's `system` directory
and are preserved when replacing the port. See [the installation and setup
guide](docs/INSTALL.md) for registration and troubleshooting.

## Recommended settings

| Setting | Value |
|---|---|
| Resolution | 540p |
| FPS | 30 |
| Codec | H.264 |
| Display Mode | Original or Stretch to Screen |

`Original` preserves the 16:9 stream with letterboxing. `Stretch to Screen`
fills the RG34XX-SP's 3:2 panel.

## Registration

Console registration can be completed without a physical keyboard. Use the
on-screen keyboard for the PSN Account ID and the console PIN. On PS5, obtain
the PIN from **Settings > System > Remote Play > Link Device**.

Never publish the contents of your Chiaki configuration, registration keys,
PSN Account ID, or unredacted session logs.

## Runtime integration

The release includes Qt 5, its EGLFS plugins, XKB data, FFmpeg dependencies,
and the Mali EGL shim. It deliberately does **not** bundle
`libSDL2-2.0.so.0` or `libasound.so.2`: KNULLI's versions are required for the
correct controller numbering and PipeWire-routed audio.

PortMaster supplies gptokeyb and device discovery. KNULLI supplies SDL, ALSA,
PipeWire, and the active audio sink.

## Logs

Useful diagnostics are written to:

```text
/userdata/roms/ports/chiaki/log.txt
/userdata/roms/ports/chiaki/input.log
/userdata/roms/ports/chiaki/temperature.log
/userdata/system/.local/share/Chiaki/Chiaki/log/
```

For working audio, the session log contains `SDL stream audio opened`. Remove
IP addresses, account identifiers, and registration data before attaching logs
to an issue.

Report KNULLI/RG34XX-SP problems in this fork's
[issue tracker](https://github.com/vampirekun/retro-chiaki/issues).

## Building

The ARM64 cross-build and Mali shim live under [`packaging/build`](packaging/build).
The KNULLI launchers and package converters live under
[`packaging/knulli`](packaging/knulli). See [BUILDING.md](docs/BUILDING.md) for
local and GitHub Actions instructions.

## Credits and license

Retro Chiaki for KNULLI builds on the work of:

- Florian Markl and all upstream Chiaki contributors.
- [ed-fruty/retro-chiaki](https://github.com/ed-fruty/retro-chiaki) for the H700
  handheld port, Qt/EGLFS integration, and PortMaster package.
- KNULLI and PortMaster contributors for the firmware and launcher integration.

The project retains the GNU AGPL v3 license and upstream OpenSSL linking
exception. See [COPYING](COPYING) and [LICENSES](LICENSES).
