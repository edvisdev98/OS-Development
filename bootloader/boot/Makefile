#
# Configuration
#

ASM ?= nasm

ASM_FLAGS = -fbin
ASM_SOURCES := boot.asm

BUILD_DIR ?= build

#
# Targets
#

.PHONY: setup build

build: $(BUILD_DIR)/boot.img

$(BUILD_DIR)/boot.img: $(ASM_SOURCES) | setup
	$(ASM) $(ASM_FLAGS) $^ -o $(BUILD_DIR)/boot.img

setup:
	mkdir -p $(BUILD_DIR)
