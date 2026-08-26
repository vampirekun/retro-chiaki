Retro Chiaki for KNULLI H700

This package targets the Anbernic RG34XX-SP running KNULLI. It installs only:

  roms/ports/Chiaki.sh
  roms/ports/chiaki/

Verified behavior:

  B = Cross, A = Circle, Y = Square, X = Triangle
  Select = Share/Create, Start = Options, M = PS Home
  M+Start exits from the interface or an active stream

The port uses KNULLI's system SDL and ALSA libraries for device-specific
controller support and PipeWire-routed audio. It intentionally excludes the
generic SDL and ALSA copies from the base PortMaster archive.

Runtime logs are written to /userdata/roms/ports/chiaki/log.txt. Session logs
are stored under /userdata/system/.local/share/Chiaki/Chiaki/log/.

To uninstall the port without deleting registrations, remove Chiaki.sh and the
chiaki directory listed above. Keep /userdata/system/.local/share/Chiaki/.
