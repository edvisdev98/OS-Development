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

.PHONY: build

build: $(BUILD_DIR)/boot.img

$(BUILD_DIR)/boot.img: $(ASM_SOURCES)
	$(ASM) $(ASM_FLAGS) $^ -o $(BUILD_DIR)/boot.img

