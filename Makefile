#
# Configuration
#

ASM = nasm
BUILD_DIR = build

#
# Targets
#

.PHONY: setup build

build: bootloader

bootloader: setup
	$(MAKE) -C $@ ASM=$(ASM) BUILD_DIR=$(abspath $(BUILD_DIR))

setup:
	mkdir -p $(BUILD_DIR)
