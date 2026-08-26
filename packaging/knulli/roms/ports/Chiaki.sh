#!/bin/bash
# PORTMASTER: chiaki, Chiaki.sh

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/userdata/roms/ports/PortMaster"
fi

# shellcheck disable=SC1090,SC1091
source "$controlfolder/control.txt"
# shellcheck disable=SC1090,SC1091
source "$controlfolder/device_info.txt"
if [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ]; then
  # shellcheck disable=SC1090
  source "${controlfolder}/mod_${CFW_NAME}.txt"
fi
get_controls

# shellcheck disable=SC2154
GAMEDIR="/${directory}/ports/chiaki"
LOGFILE="$GAMEDIR/log.txt"

: > "$LOGFILE"
exec > >(tee "$LOGFILE") 2>&1

# shellcheck disable=SC2329
cleanup() {
	if [ -n "${TEMPERATURE_MONITOR_PID:-}" ]; then
		kill "$TEMPERATURE_MONITOR_PID" 2>/dev/null
	fi
	if [ -n "${GPTOKEYB_PID:-}" ]; then
		$ESUDO kill -9 "$GPTOKEYB_PID" 2>/dev/null
	fi
  printf "\033c" > /dev/tty0 2>/dev/null
}
trap cleanup EXIT INT TERM

cd "$GAMEDIR" || exit 1

export LD_LIBRARY_PATH="$GAMEDIR/libs:${LD_LIBRARY_PATH:-}"
export QT_PLUGIN_PATH="$GAMEDIR/libs/qt5/plugins"

export RETRO_CHIAKI_GLES=1
SYSTEM_SDL=/usr/lib/libSDL2-2.0.so.0
SYSTEM_ALSA=/usr/lib/libasound.so.2
if [ ! -r "$SYSTEM_SDL" ] || [ ! -r "$SYSTEM_ALSA" ]; then
  echo "KNULLI SDL/ALSA libraries not found: $SYSTEM_SDL $SYSTEM_ALSA"
  exit 1
fi
# Always resolve SDL and ALSA from KNULLI. Ubuntu's SDL uses different raw
# button indices, while Ubuntu's ALSA looks for plugins in the wrong directory.
CHIAKI_LD_PRELOAD="$SYSTEM_SDL:$SYSTEM_ALSA:$GAMEDIR/libs/libmaliegl.so:/usr/lib/libGLESv2.so.2"

export XKB_CONFIG_ROOT="$GAMEDIR/xkb"
export QT_XKB_CONFIG_ROOT="$GAMEDIR/xkb"
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_HIDECURSOR=0
export QT_QPA_EGLFS_FB=/dev/fb0

# KNULLI starts PipeWire with XDG_RUNTIME_DIR=/var/run. Qt needs its own
# restricted runtime directory, so preserve the system socket location for
# PipeWire and PulseAudio clients before replacing XDG_RUNTIME_DIR below.
SYSTEM_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run}"
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-$SYSTEM_RUNTIME_DIR}"
export PULSE_SERVER="${PULSE_SERVER:-unix:/var/run/pulse/native}"

RUNTIME_DIR=/tmp/retro-chiaki-runtime
mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"

SCREEN_WIDTH="${DISPLAY_WIDTH:-}"
SCREEN_HEIGHT="${DISPLAY_HEIGHT:-}"
FB_DEPTH=""

if [ -r /sys/class/graphics/fb0/modes ]; then
  SCREEN_MODE=$(head -n 1 /sys/class/graphics/fb0/modes)
  if [[ "$SCREEN_MODE" =~ ([0-9]+)x([0-9]+) ]]; then
    SCREEN_WIDTH="${BASH_REMATCH[1]}"
    SCREEN_HEIGHT="${BASH_REMATCH[2]}"
  fi
fi

if command -v fbset >/dev/null 2>&1; then
  read -r FB_WIDTH FB_HEIGHT FB_DEPTH < <(
    fbset -s 2>/dev/null | awk '/geometry/ { print $2, $3, $6; exit }'
  )
  SCREEN_WIDTH="${SCREEN_WIDTH:-$FB_WIDTH}"
  SCREEN_HEIGHT="${SCREEN_HEIGHT:-$FB_HEIGHT}"
fi

SCREEN_WIDTH="${SCREEN_WIDTH:-720}"
SCREEN_HEIGHT="${SCREEN_HEIGHT:-480}"
# Match KNULLI's H700 SDL video driver, which exposes RGBX8888.
SCREEN_DEPTH=32

export QT_QPA_EGLFS_WIDTH="$SCREEN_WIDTH"
export QT_QPA_EGLFS_HEIGHT="$SCREEN_HEIGHT"
export QT_QPA_EGLFS_DEPTH="$SCREEN_DEPTH"
export QT_QPA_EGLFS_FORCE888=1
export QT_OPENGL=es2
export QT_SCALE_FACTOR=1
export QT_AUTO_SCREEN_SCALE_FACTOR=0
unset QT_QPA_GENERIC_PLUGINS
export QT_ENABLE_HIGHDPI_SCALING=0
export QT_QPA_EGLFS_PHYSICAL_WIDTH=$((SCREEN_WIDTH * 254 / 960))
export QT_QPA_EGLFS_PHYSICAL_HEIGHT=$((SCREEN_HEIGHT * 254 / 960))
export MALI_WINDOW_WIDTH="$SCREEN_WIDTH"
export MALI_WINDOW_HEIGHT="$SCREEN_HEIGHT"
unset MALI_EGL_SHIM_TEST_CLEAR
unset MALI_EGL_SHIM_INSPECT_FRAME
unset MALI_EGL_SHIM_FORCE_OPAQUE
unset SDL_NOMOUSE

# SDL's logical face names describe position. Match KNULLI's RG34XX-SP
# indices so physical B/A/Y/X become SDL A/B/X/Y respectively.
CONTROLLER_MAPPING="19000000010000000100000000010000,Anbernic RG34XX-SP Controller,a:b4,b:b3,x:b5,y:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,leftx:a0,lefty:a1,rightx:a2,righty:a3,leftshoulder:b7,rightshoulder:b8,lefttrigger:b13,righttrigger:b14,leftstick:b12,rightstick:b15,back:b9,start:b10,guide:b11,platform:Linux,"
CONTROLLER_DB=/tmp/retro-chiaki-gamecontrollerdb.txt
printf '%s\n' "$CONTROLLER_MAPPING" > "$CONTROLLER_DB"
export SDL_GAMECONTROLLERCONFIG="$CONTROLLER_MAPPING"
export SDL_GAMECONTROLLERCONFIG_FILE="$CONTROLLER_DB"
export RETRO_CHIAKI_RG34XXSP=1
export RETRO_CHIAKI_LOG_INPUT=1
export RETRO_CHIAKI_INPUT_LOG="$GAMEDIR/input.log"
export HOTKEY=guide

: > "$RETRO_CHIAKI_INPUT_LOG"

echo "Retro Chiaki for KNULLI"
echo "Firmware: ${CFW_NAME:-unknown} ${CFW_VERSION:-unknown}"
echo "Device: ${DEVICE_NAME:-unknown} (${DEVICE_ARCH:-unknown})"
echo "Display: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}; framebuffer=${FB_DEPTH:-unknown}, Qt=${SCREEN_DEPTH}"

LD_PRELOAD="$SYSTEM_SDL" $GPTOKEYB "chiaki" -c "$GAMEDIR/chiaki.gptk" &
GPTOKEYB_PID=$!
export GPTOKEYB_PID
echo "gptokeyb PID=$GPTOKEYB_PID"
sleep 1

echo "RETRO_CHIAKI_GLES=${RETRO_CHIAKI_GLES:-0}"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "KNULLI SDL=$SYSTEM_SDL"
echo "KNULLI ALSA=$SYSTEM_ALSA"
echo "PipeWire runtime=$PIPEWIRE_RUNTIME_DIR"
echo "Pulse server=$PULSE_SERVER"
echo "Chiaki LD_PRELOAD=$CHIAKI_LD_PRELOAD"
echo "SDL_GAMECONTROLLERCONFIG=$SDL_GAMECONTROLLERCONFIG"

TEMPERATURE_LOG="$GAMEDIR/temperature.log"
(
	: > "$TEMPERATURE_LOG"
	while true; do
		printf '%s' "$(date -Iseconds)" >> "$TEMPERATURE_LOG"
		for zone in /sys/class/thermal/thermal_zone*; do
			[ -r "$zone/temp" ] || continue
			printf ' %s=%s' "$(basename "$zone")" "$(cat "$zone/temp")" >> "$TEMPERATURE_LOG"
		done
		printf '\n' >> "$TEMPERATURE_LOG"
		sleep 10
	done
) &
TEMPERATURE_MONITOR_PID=$!

LD_PRELOAD="$CHIAKI_LD_PRELOAD" ./chiaki
CHIAKI_STATUS=$?
echo "chiaki exited: $CHIAKI_STATUS"
exit "$CHIAKI_STATUS"
