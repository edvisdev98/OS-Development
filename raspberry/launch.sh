#!/bin/bash
# =============================================================================
# KSDOS Watch - Launcher for Raspberry Pi with TFT display
#
# Display modes (set DISPLAY_MODE below):
#   framebuffer  - Output directly to TFT via /dev/fb1 (headless, no X11)
#   x11          - Output via X11 (requires a running X server on the TFT)
#   hdmi         - Output via HDMI (for testing without TFT)
# =============================================================================

KSDOS_DIR="/home/pi/ksdos"
DISK_IMG="$KSDOS_DIR/disk.img"
VKBD_BIN="$KSDOS_DIR/vkbd"
DISPLAY_MODE="framebuffer"
TFT_DEVICE="/dev/fb1"
MEMORY="32"

# --------------------------------------------------------------------------
# Sanity checks
# --------------------------------------------------------------------------
if [ ! -f "$DISK_IMG" ]; then
    echo "ERROR: disk image not found at $DISK_IMG"
    exit 1
fi

# --------------------------------------------------------------------------
# Hide the console cursor on TFT
# --------------------------------------------------------------------------
if [ -e "$TFT_DEVICE" ]; then
    echo -ne "\033[?25l" > "$TFT_DEVICE" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# QEMU flags — no QMP socket (keyboard goes through uinput)
# --------------------------------------------------------------------------
QEMU_FLAGS=(
    -drive "format=raw,file=$DISK_IMG,if=floppy"
    -boot a
    -m "$MEMORY"
    -vga std
    -no-reboot
    -name "KSDOS"
)

# --------------------------------------------------------------------------
# Start the virtual keyboard daemon (background)
# --------------------------------------------------------------------------
start_vkbd() {
    if [ ! -x "$VKBD_BIN" ]; then
        echo "WARNING: vkbd binary not found at $VKBD_BIN — touch keyboard disabled."
        echo "  Run: gcc -O2 -o $VKBD_BIN $KSDOS_DIR/vkbd.c -lpthread"
        return
    fi

    # Auto-detect touch device if not set
    local TOUCH_DEV="${VKBD_TOUCH:-}"
    if [ -z "$TOUCH_DEV" ]; then
        for ev in /dev/input/event*; do
            if evtest --query "$ev" EV_ABS 2>/dev/null; then
                TOUCH_DEV="$ev"
                break
            fi
        done
    fi

    if [ -n "$TOUCH_DEV" ]; then
        echo "Starting virtual keyboard on $TFT_DEVICE ($TOUCH_DEV)..."
        "$VKBD_BIN" "$TFT_DEVICE" "$TOUCH_DEV" &
        VKBD_PID=$!
    else
        echo "WARNING: No touch device found — starting vkbd without explicit device."
        "$VKBD_BIN" "$TFT_DEVICE" &
        VKBD_PID=$!
    fi
}

cleanup() {
    if [ -n "$VKBD_PID" ]; then
        kill "$VKBD_PID" 2>/dev/null
        wait "$VKBD_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

# --------------------------------------------------------------------------
# Launch
# --------------------------------------------------------------------------
case "$DISPLAY_MODE" in

    framebuffer)
        if [ ! -e "$TFT_DEVICE" ]; then
            echo "WARNING: $TFT_DEVICE not found, falling back to /dev/fb0 (HDMI)"
            TFT_DEVICE="/dev/fb0"
        fi
        export SDL_FBDEV="$TFT_DEVICE"
        export SDL_VIDEODRIVER="fbcon"
        export SDL_NOMOUSE=1
        TFT_RES=$(fbset -fb "$TFT_DEVICE" 2>/dev/null | grep "geometry" | awk '{print $2"x"$3}')
        echo "KSDOS starting on $TFT_DEVICE ($TFT_RES)..."
        start_vkbd
        exec qemu-system-i386 "${QEMU_FLAGS[@]}" -display sdl,show-cursor=off
        ;;

    x11)
        export DISPLAY="${DISPLAY:-:0}"
        start_vkbd
        exec qemu-system-i386 "${QEMU_FLAGS[@]}" -display sdl,show-cursor=off
        ;;

    hdmi)
        export DISPLAY="${DISPLAY:-:0}"
        exec qemu-system-i386 "${QEMU_FLAGS[@]}" -display sdl
        ;;

    *)
        echo "ERROR: Unknown DISPLAY_MODE '$DISPLAY_MODE'"
        exit 1
        ;;
esac
