CROSS_TOOLCHAIN ?=
CC = gcc
LD = ld
override CC = $(CROSS_TOOLCHAIN)gcc
override LD = $(CROSS_TOOLCHAIN)ld

BUILD_DIR ?= build
override BUILD_DIR := $(abspath $(BUILD_DIR))

export CROSS_TOOLCHAIN CC LD BUILD_DIR

.PHONY: build-bootloader

build-bootloader: $(BUILD_DIR)/boot.bin \
					$(BUILD_DIR)/core.bin

$(BUILD_DIR)/boot.bin:
	$(MAKE) -C ./bootloader/boot

$(BUILD_DIR)/core.bin:
	$(MAKE) -C ./bootloader/core
