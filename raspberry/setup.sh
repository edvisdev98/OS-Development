#!/bin/bash
# =============================================================================
# KSDOS Watch - Setup Script for Raspberry Pi
# Compatible with: Raspberry Pi Zero 2W, Pi 3, Pi 4
# Display: Any SPI TFT (ILI9341/ILI9486/ST7789) via FBTFT
#
# Usage: sudo bash setup.sh
# =============================================================================
set -e

KSDOS_DIR="/home/pi/ksdos"
SERVICE_USER="pi"

echo "========================================"
echo " KSDOS Watch - Raspberry Pi Setup"
echo "========================================"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run with sudo: sudo bash setup.sh"
    exit 1
fi

# --------------------------------------------------------------------------
# 1. Install dependencies
# --------------------------------------------------------------------------
echo ""
echo "[1/5] Installing packages..."
apt-get update -qq
apt-get install -y -qq \
    qemu-system-x86 \
    libsdl2-2.0-0 \
    fbset \
    evtest \
    gcc \
    libc6-dev

echo "[OK] Packages installed."

# --------------------------------------------------------------------------
# 2. Enable SPI and configure TFT overlay
# --------------------------------------------------------------------------
echo ""
echo "[2/5] Configuring SPI and TFT display overlay..."

# Enable SPI interface
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    echo "dtparam=spi=on" >> /boot/config.txt
fi

# Detect/select display overlay
# Uncomment the line that matches your display:
DISPLAY_TYPE="waveshare35a"   # Waveshare 3.5" Type A (480x320) - ILI9486
# DISPLAY_TYPE="adafruit18"   # Adafruit 1.8" (160x128) - ST7735
# DISPLAY_TYPE="piscreen"     # PiScreen 3.5" (480x320) - ILI9486
# DISPLAY_TYPE="pitft28-resistive"  # Adafruit PiTFT 2.8" (320x240) - ILI9341

if ! grep -q "dtoverlay=$DISPLAY_TYPE" /boot/config.txt; then
    echo "dtoverlay=$DISPLAY_TYPE" >> /boot/config.txt
    echo "[OK] Added dtoverlay=$DISPLAY_TYPE to /boot/config.txt"
else
    echo "[OK] TFT overlay already configured."
fi

# Rotate display 90 degrees for landscape watch orientation (optional)
# Uncomment if your display appears rotated:
# echo "dtoverlay=$DISPLAY_TYPE,rotate=90" >> /boot/config.txt

# --------------------------------------------------------------------------
# 3. Configure framebuffer for the TFT display
# --------------------------------------------------------------------------
echo ""
echo "[3/5] Configuring framebuffer..."

# Copy framebuffer udev rule so /dev/fb1 is accessible
cat > /etc/udev/rules.d/99-fbdev.rules << 'EOF'
SUBSYSTEM=="graphics", KERNEL=="fb*", GROUP="video", MODE="0660"
EOF

# Add pi user to video group
usermod -aG video "$SERVICE_USER"

echo "[OK] Framebuffer configured."

# --------------------------------------------------------------------------
# 4. Install KSDOS files
# --------------------------------------------------------------------------
echo ""
echo "[4/5] Installing KSDOS files..."

mkdir -p "$KSDOS_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy disk image and launch scripts
cp "$SCRIPT_DIR/disk.img" "$KSDOS_DIR/disk.img" 2>/dev/null || \
    echo "  NOTE: disk.img not found here - copy it manually to $KSDOS_DIR/disk.img"

cp "$SCRIPT_DIR/launch.sh" "$KSDOS_DIR/launch.sh"
chmod +x "$KSDOS_DIR/launch.sh"

# Copy and compile the virtual keyboard
cp "$SCRIPT_DIR/vkbd.c" "$KSDOS_DIR/vkbd.c"
echo "  Compiling virtual keyboard (vkbd.c)..."
if gcc -O2 -o "$KSDOS_DIR/vkbd" "$KSDOS_DIR/vkbd.c" -lpthread; then
    echo "  [OK] vkbd compiled successfully."
else
    echo "  [WARN] vkbd compilation failed — touch keyboard will be disabled."
fi

# Add pi user to input group so vkbd can read touch events without root
usermod -aG input "$SERVICE_USER"

chown -R "$SERVICE_USER:$SERVICE_USER" "$KSDOS_DIR"
echo "[OK] Files installed to $KSDOS_DIR"

# --------------------------------------------------------------------------
# 5. Install and enable systemd service
# --------------------------------------------------------------------------
echo ""
echo "[5/5] Installing systemd service..."

cp "$SCRIPT_DIR/ksdos-watch.service" /etc/systemd/system/ksdos-watch.service
systemctl daemon-reload
systemctl enable ksdos-watch.service

echo "[OK] Service installed and enabled."

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "========================================"
echo " Setup complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. If disk.img was not copied automatically:"
echo "     cp /path/to/build/disk.img $KSDOS_DIR/disk.img"
echo ""
echo "  2. Reboot to activate the TFT overlay:"
echo "     sudo reboot"
echo ""
echo "  3. After reboot, KSDOS starts automatically."
echo "     To start manually: sudo systemctl start ksdos-watch"
echo "     To check status:   sudo systemctl status ksdos-watch"
echo ""
echo "  Display wiring (SPI TFT to Raspberry Pi GPIO):"
echo "    VCC  -> Pin 17 (3.3V)"
echo "    GND  -> Pin 20 (GND)"
echo "    DIN  -> Pin 19 (SPI0 MOSI, GPIO 10)"
echo "    CLK  -> Pin 23 (SPI0 SCLK, GPIO 11)"
echo "    CS   -> Pin 24 (SPI0 CE0,  GPIO 8)"
echo "    DC   -> Pin 18 (GPIO 24)"
echo "    RST  -> Pin 22 (GPIO 25)"
echo "    BL   -> Pin 12 (GPIO 18, PWM)"
echo ""
