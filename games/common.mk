# ================================================================
# Common build configuration for KSDOS games
# Includes SDK detection and standard build rules
# ================================================================

# Include SDK detection
include ../sdk/detect-sdk.mk

# Auto-configure SDKs
$(eval $(call auto_configure_sdk))

# Common build settings
BUILD_DIR ?= build
BIN_DIR ?= bin

# Common compiler flags
COMMON_CFLAGS = -Wall -Wextra -O2
COMMON_LDFLAGS = 

# Platform-specific settings
ifeq ($(PLATFORM),PS1)
    CC = mipsel-none-elf-gcc
    LD = mipsel-none-elf-ld
    OBJCOPY = mipsel-none-elf-objcopy
    CFLAGS = $(COMMON_CFLAGS) -msoft-float -nostdlib
    INCLUDES = -I$(PS1_INC)
    LDFLAGS = $(COMMON_LDFLAGS) -L$(PS1_LIB)
    LIBS = -lpsx -lc -lm
endif

ifeq ($(PLATFORM),DOOM)
    CC = gcc
    LD = ld
    CFLAGS = $(COMMON_CFLAGS) -m32 -ffreestanding -nostdlib
    INCLUDES = -I$(DOOM_INC)
    LDFLAGS = $(COMMON_LDFLAGS) -L$(DOOM_LIB)
    LIBS = -lgold4 -lc -lm
endif

# Default platform if not specified
PLATFORM ?= DOOM

# Common build rules
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(BIN_DIR):
	@mkdir -p $(BIN_DIR)

# Common clean rule
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(BIN_DIR)

# Common help rule
.PHONY: help
help:
	@echo "$(PROJECT_NAME) Build System"
	@echo "============================"
	@echo "Platform: $(PLATFORM)"
	@echo "Targets:"
	@echo "  all/$(PROJECT_NAME) - Build $(PROJECT_NAME)"
	@echo "  clean              - Remove build artifacts"
	@echo "  info               - Show SDK information"
	@echo ""
	$(call print_sdk_info)

# SDK info rule
.PHONY: info
info:
	$(call print_sdk_info)
