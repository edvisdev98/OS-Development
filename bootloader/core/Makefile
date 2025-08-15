#
# Configuration
#

BUILD_DIR ?= build

ASM ?= nasm

CROSS_COMPILER ?= i386-elf-
CC ?= $(CROSS_COMPILER)gcc
LD ?= $(CROSS_COMPILER)ld

ASMFLAGS ?= -felf32
ASMSOURCES := entry.asm
ASMOBJECTS = $(patsubst %.asm, $(BUILD_DIR)/core/%.o, $(ASMSOURCES))

CFLAGS ?= -Wall -Wextra -ffreestanding
CSOURCES :=
COBJECTS = $(patsubst %.c, $(BUILD_DIR)/core/%.o, $(CSOURCES))

LDFLAGS ?= -m elf_i386 -Tlinker.ld

#
# Targets
#

.PHONY: setup build link

build: $(BUILD_DIR)/core.img

# Link & copy the object files into a raw binary file.
$(BUILD_DIR)/core.img: $(ASMOBJECTS) $(COBJECTS) | setup
	$(LD) $(LDFLAGS) $^ -o $(BUILD_DIR)/core/core
	objcopy -O binary $(BUILD_DIR)/core/core $@

# Assemble *.asm files
$(BUILD_DIR)/core/%.o: %.asm
	mkdir -p $(dir $@)
	$(ASM) $(ASMFLAGS) $< -o $@

# Compile *.c files
$(BUILD_DIR)/core/%.o: %.c
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

setup:
	mkdir -p $(BUILD_DIR)
