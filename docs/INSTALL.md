# KNULLI installation and setup

## Requirements

- Anbernic RG34XX-SP running KNULLI.
- PortMaster installed and working.
- A PS4 or PS5 with Remote Play enabled.
- The handheld and console reachable over the same network for initial setup.

The verified firmware is KNULLI Scarab dated 2026-05-11. This package is not a
drop-in replacement for the muOS release.

## Install the release

Download `retro-chiaki-v0.3.2-knulli1-portmaster-knulli-h700.zip` from
[Releases](https://github.com/vampirekun/retro-chiaki/releases) and extract it
to the root of KNULLI's userdata partition. The archive already contains the
complete `roms/ports` layout, so do not extract it inside `roms` or
`roms/ports`.

Verify these relative paths:

```text
roms/ports/Chiaki.sh
roms/ports/chiaki/chiaki
roms/ports/chiaki/chiaki-cli
roms/ports/chiaki/chiaki.gptk
roms/ports/chiaki/libs/
roms/ports/chiaki/xkb/
```

Safely eject the card, boot KNULLI, refresh the game list if necessary, and
launch **Ports > Chiaki**.

## Upgrade an existing test build

Extract the new archive over the existing port. Chiaki stores registration and
preferences under:

```text
/userdata/system/.local/share/Chiaki/
```

The release archive does not replace that directory. If an early test build
left files ending in `.ubuntu-disabled`, they are inert and may remain in the
port's `libs` directory.

## Register a PS4 or PS5

1. Connect the handheld and console to the same network.
2. Start Chiaki and add the console manually if discovery does not find it.
3. Enter the Base64 PSN Account ID with the on-screen keyboard.
4. On PS5, open **Settings > System > Remote Play > Link Device**. On PS4,
   open **Settings > Remote Play Connection Settings > Add Device**.
5. Enter the displayed PIN and complete registration.

The upstream helper [`scripts/psn-account-id.py`](../scripts/psn-account-id.py)
can obtain an Account ID through PlayStation OAuth. Never publish registration
data or the Chiaki configuration file.

## Controls

During a stream, the physical labels map to PlayStation as follows:

```text
B = Cross        A = Circle
Y = Square       X = Triangle
Select = Share   Start = Options
M = PS Home      M+Start = Exit
```

L1/R1, L2/R2, L3/R3, and the D-pad map directly. Before streaming, B confirms,
A goes back, and the left stick controls the pointer.

## Stream settings

Start with **540p**, **30 FPS**, and **H.264**. Use **Original** for correct
16:9 proportions or **Stretch to Screen** to fill the 720x480 display.

## KNULLI runtime dependencies

The package includes its Qt, FFmpeg, XKB, and Mali EGL requirements. It uses
KNULLI's own SDL and ALSA libraries instead of the Ubuntu copies from the base
PortMaster archive. This is required for:

- RG34XX-SP raw button identifiers;
- PipeWire ALSA plugins installed by KNULLI;
- `/var/run/pipewire-0` and `/var/run/pulse/native` audio sockets.

Do not copy `libSDL2-2.0.so.0` or `libasound.so.2` from a desktop Linux build
into `roms/ports/chiaki/libs`.

## Troubleshooting

### Video does not start

Check `/userdata/roms/ports/chiaki/log.txt`. A working launch reports the
720x480 framebuffer, successful EGL initialization, and OpenGL ES.

### Controls are shifted

Confirm the log reports `Anbernic RG34XX-SP Controller` and the mapping begins
with `a:b4,b:b3,x:b5,y:b6`. Also confirm no active bundled SDL exists in the
port's `libs` directory.

### Video works but audio is silent

The session log should report:

```text
SDL stream audio opened with 2 channels @ 48000 Hz
```

If it reports an ALSA or PipeWire error, verify KNULLI has a selected audio
sink and that the launcher reports `PipeWire runtime=/var/run`. Confirm no
active bundled `libasound.so.2` exists in the port.

### Remote Play session fails after login

`InvalidSessionId`, `Unknown ctrl error`, or a Takion timeout can mean another
Remote Play session is active or the console session is stuck. Close other
clients, wait briefly, and fully restart the console before re-registering it.

## Logs and privacy

```text
/userdata/roms/ports/chiaki/log.txt
/userdata/roms/ports/chiaki/input.log
/userdata/roms/ports/chiaki/temperature.log
/userdata/system/.local/share/Chiaki/Chiaki/log/
```

Remove IP addresses, Account IDs, registration keys, and other private data
before posting logs.

## Uninstall

Remove only:

```text
/userdata/roms/ports/Chiaki.sh
/userdata/roms/ports/chiaki/
```

Removing `/userdata/system/.local/share/Chiaki/` also deletes registrations and
preferences, so keep it when reinstalling or upgrading.
