#
# Configuration
#

ASM ?= nasm
BUILD_DIR ?= build

#
# Targets
#

.PHONY: build

build: $(BUILD_DIR)/boot.img $(BUILD_DIR)/core.img

$(BUILD_DIR)/boot.img:
	$(MAKE) build -C boot ASM=$(ASM) BUILD_DIR=$(abspath $(BUILD_DIR))

$(BUILD_DIR)/core.img:
	$(MAKE) build -C core ASM=$(ASM) BUILD_DIR=$(abspath $(BUILD_DIR))
