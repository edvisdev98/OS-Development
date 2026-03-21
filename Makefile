# =============================================================================
# KSDOS Build System
# Produces a 1.44MB FAT12 floppy image (disk.img) bootable in QEMU
# =============================================================================

NASM     := nasm
PERL     := perl
QEMU     := qemu-system-i386

# Overlay load address — must match OVERLAY_BUF in ovl_api.asm
OVL_ORG  := 0x7000

BUILD    := build
BOOT_DIR := bootloader/boot
KERN_DIR := bootloader/kernel
OVL_DIR  := bootloader/kernel/overlays
TOOLS    := tools

BOOTSECT_SRC := $(BOOT_DIR)/bootsect.asm
KERNEL_SRC   := $(KERN_DIR)/ksdos.asm
MBR_SRC      := $(BOOT_DIR)/mbr.asm

BOOTSECT_BIN := $(BUILD)/bootsect.bin
KERNEL_BIN   := $(BUILD)/ksdos.bin
MBR_BIN      := $(BUILD)/mbr.bin
DISK_IMG     := $(BUILD)/disk.img

# ---------------------------------------------------------------------------
# Overlay binaries (assembled separately, embedded as .OVL files on disk)
# ---------------------------------------------------------------------------
OVL_NAMES := CC MASM CSC MUSIC NET OPENGL PSYQ GOLD4 IDE
OVL_BINS  := $(patsubst %,$(BUILD)/%.OVL,$(OVL_NAMES))

RASPBERRY := raspberry
DEPLOY_DIR := $(BUILD)/ksdos-watch
DEPLOY_TAR := $(BUILD)/ksdos-watch.tar.gz

.PHONY: all image run run-sdl run-serial deploy clean help

all: image

image: $(DISK_IMG)

$(BOOTSECT_BIN): $(BOOTSECT_SRC) | $(BUILD)
	@echo "[NASM] Assembling boot sector..."
	$(NASM) -f bin -i $(BOOT_DIR)/ -o $@ $<
	@echo "[OK]   bootsect.bin"

$(KERNEL_BIN): $(KERNEL_SRC) | $(BUILD)
	@echo "[NASM] Assembling kernel (KSDOS.SYS)..."
	$(NASM) -f bin -i $(KERN_DIR)/ -o $@ $<
	@echo "[OK]   ksdos.bin"

$(MBR_BIN): $(MBR_SRC) | $(BUILD)
	@echo "[NASM] Assembling MBR..."
	$(NASM) -f bin -i $(BOOT_DIR)/ -o $@ $<
	@echo "[OK]   mbr.bin"

# Rule: assemble each overlay (sources live in OVL_DIR, include kernel dir too)
OVL_FLAGS := -f bin -DOVERLAY_BUF=$(OVL_ORG) -i $(KERN_DIR)/ -i $(OVL_DIR)/

$(BUILD)/CC.OVL:     $(OVL_DIR)/cc.ovl.asm     $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay CC..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   CC.OVL"

$(BUILD)/MASM.OVL:   $(OVL_DIR)/masm.ovl.asm   $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay MASM..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   MASM.OVL"

$(BUILD)/CSC.OVL:    $(OVL_DIR)/csc.ovl.asm     $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay CSC..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   CSC.OVL"

$(BUILD)/MUSIC.OVL:  $(OVL_DIR)/music.ovl.asm   $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay MUSIC..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   MUSIC.OVL"

$(BUILD)/NET.OVL:    $(OVL_DIR)/net.ovl.asm     $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay NET..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   NET.OVL"

$(BUILD)/OPENGL.OVL: $(OVL_DIR)/opengl.ovl.asm  $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay OPENGL..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   OPENGL.OVL"

$(BUILD)/PSYQ.OVL:   $(OVL_DIR)/psyq.ovl.asm    $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay PSYQ..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   PSYQ.OVL"

$(BUILD)/GOLD4.OVL:  $(OVL_DIR)/gold4.ovl.asm   $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay GOLD4..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   GOLD4.OVL"

$(BUILD)/IDE.OVL:    $(OVL_DIR)/ide.ovl.asm     $(KERN_DIR)/ovl_api.asm | $(BUILD)
	@echo "[NASM] Assembling overlay IDE..."
	$(NASM) $(OVL_FLAGS) -o $@ $<
	@echo "[OK]   IDE.OVL"

$(DISK_IMG): $(BOOTSECT_BIN) $(KERNEL_BIN) $(OVL_BINS) | $(BUILD)
	@echo "[PERL] Building FAT12 disk image..."
	$(PERL) $(TOOLS)/mkimage.pl $(BOOTSECT_BIN) $(KERNEL_BIN) $(DISK_IMG) $(OVL_BINS)
	@echo "[OK]   disk.img ready"

$(BUILD):
	mkdir -p $(BUILD)

run: image
	@echo "[QEMU] Booting KSDOS v2.0..."
	mkdir -p /tmp/xdg-runtime
	XDG_RUNTIME_DIR=/tmp/xdg-runtime \
	$(QEMU) \
	        -drive format=raw,file=$(DISK_IMG),if=floppy \
	        -boot a \
	        -m 4 \
	        -vga std \
	        -display vnc=:0 \
	        -no-reboot \
	        -name "KSDOS v2.0"

run-sdl: image
	$(QEMU) -fda $(DISK_IMG) -boot a -m 4 -vga std -display sdl -no-reboot

run-serial: image
	$(QEMU) -fda $(DISK_IMG) -boot a -m 4 -nographic -no-reboot

# ---------------------------------------------------------------------------
# deploy: package disk.img + Raspberry Pi scripts into ksdos-watch.tar.gz
# ---------------------------------------------------------------------------
deploy: image
	@echo "[PKG]  Building Raspberry Pi deployment package..."
	rm -rf $(DEPLOY_DIR)
	mkdir -p $(DEPLOY_DIR)
	cp $(DISK_IMG) $(DEPLOY_DIR)/disk.img
	cp $(RASPBERRY)/setup.sh $(DEPLOY_DIR)/setup.sh
	cp $(RASPBERRY)/launch.sh $(DEPLOY_DIR)/launch.sh
	cp $(RASPBERRY)/ksdos-watch.service $(DEPLOY_DIR)/ksdos-watch.service
	chmod +x $(DEPLOY_DIR)/setup.sh $(DEPLOY_DIR)/launch.sh
	tar -czf $(DEPLOY_TAR) -C $(BUILD) ksdos-watch
	@echo "[OK]   $(DEPLOY_TAR)"
	@echo ""
	@echo "Transfer to your Raspberry Pi:"
	@echo "  scp $(DEPLOY_TAR) pi@<pi-ip>:~/"
	@echo "  ssh pi@<pi-ip> 'tar xzf ksdos-watch.tar.gz && sudo bash ksdos-watch/setup.sh'"

clean:
	rm -rf $(BUILD)

help:
	@echo "KSDOS Build System - 16-bit Real Mode OS"
	@echo "========================================="
	@echo "Targets:"
	@echo "  all / image   - Build disk.img (default)"
	@echo "  run           - Build and boot in QEMU (VNC)"
	@echo "  run-sdl       - Build and boot (SDL window)"
	@echo "  run-serial    - Boot headless (serial only)"
	@echo "  deploy        - Package for Raspberry Pi TFT watch"
	@echo "  clean         - Remove build directory"
	@echo ""
	@echo "Output: $(DISK_IMG) (1.44MB FAT12 floppy)"
	@echo "Overlays: $(OVL_NAMES)"
	@echo ""
	@echo "Raspberry Pi deploy:"
	@echo "  make deploy"
	@echo "  scp $(DEPLOY_TAR) pi@<ip>:~/"
	@echo "  ssh pi@<ip> 'tar xzf ksdos-watch.tar.gz && sudo bash ksdos-watch/setup.sh'"
