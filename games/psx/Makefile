# ================================================================
# PS1 Game Makefile - Uses local PSYQ SDK
# SDK: $(PS1_SDK) or ../sdk/psyq
# ================================================================

# Project configuration
PROJECT_NAME = psx-game
PLATFORM = PS1

# Include common build configuration
include ../common.mk

# PS1-specific linker script
LDFLAGS += -T psx.ld

# Directories
SRC_DIR = src

# Source files
SOURCES = $(wildcard $(SRC_DIR)/*.c)
OBJECTS = $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)

# Target executable
TARGET = $(BIN_DIR)/$(PROJECT_NAME).exe

# Default target
.PHONY: all psx-game

all: psx-game

psx-game: $(TARGET)

$(TARGET): $(OBJECTS) | $(BIN_DIR)
	@echo "Linking PS1 game..."
	$(LD) $(LDFLAGS) -o $@ $(OBJECTS) $(LIBS)
	@echo "Creating PS1 executable: $@"

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@
