#
# Configuration
#

ASM ?= nasm
BUILD_DIR ?= build

#
# Targets
#

.PHONY: setup build

build: $(BUILD_DIR)/boot.img $(BUILD_DIR)/core.img

$(BUILD_DIR)/boot.img: setup
	$(MAKE) -C boot ASM=$(ASM) BUILD_DIR=$(abspath $(BUILD_DIR))

$(BUILD_DIR)/core.img: setup 
	$(MAKE) -C core ASM=$(ASM) BUILD_DIR=$(abspath $(BUILD_DIR))

setup:
	mkdir -p $(BUILD_DIR)
