$(BUILD_DIR)/boot.bin: boot.asm
	mkdir -p $(dir $@)
	nasm -fbin $^ -o $@
