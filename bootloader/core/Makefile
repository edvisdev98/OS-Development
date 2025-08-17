ASM ?= as
override ASM := $(CROSS_TOOLCHAIN)$(ASM)

.PHONY: build

build: $(BUILD_DIR)/core.bin

$(BUILD_DIR)/core/early.bin: setup.asm
	mkdir -p $(dir $@)
	nasm -fbin $< -o $@

CORE_ASM_SOURCES := entry.s
CORE_ASM_OBJECTS := $(patsubst %.s, $(BUILD_DIR)/core/%.o, $(CORE_ASM_SOURCES))
CORE_ASM_FLAGS := --32

CORE_C_SOURCES := core.c
CORE_C_OBJECTS := $(patsubst %.c, $(BUILD_DIR)/core/%.o, $(CORE_C_SOURCES))
CORE_C_FLAGS := -Wall \
				-Wextra \
				-ffreestanding \
				-fno-pic \
				-m32

CORE_LD_FLAGS := -Tlinker.ld -m elf_i386

$(BUILD_DIR)/core.bin: $(CORE_ASM_OBJECTS) $(CORE_C_OBJECTS) | $(BUILD_DIR)/core/early.bin
	$(LD) $(CORE_LD_FLAGS) $^ -o $(BUILD_DIR)/core/after.bin
	cat $(BUILD_DIR)/core/early.bin $(BUILD_DIR)/core/after.bin > $@
# The MBR sector code reads 10 sectors (1 Sector = 512 bytes) as
# of now, so to make sure that it isn't picking up random bytes, we will
# truncate it to 10 sectors (5120 bytes).
	truncate -s 5120 $@

$(BUILD_DIR)/core/%.o: %.s
	mkdir -p $(dir $@)
	$(ASM) $(CORE_ASM_FLAGS) $< -o $@

$(BUILD_DIR)/core/%.o: %.c
	mkdir -p $(dir $@)
	$(CC) $(CORE_C_FLAGS) -c $< -o $@
