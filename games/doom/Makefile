# ================================================================
# DOOM Game Makefile - Uses local GOLD4 SDK
# SDK: $(DOOM_SDK) or ../sdk/gold4
# ================================================================

# Project configuration
PROJECT_NAME = doom-game
PLATFORM = DOOM

# Include common build configuration
include ../common.mk

# Directories
SRC_DIR = src

# Source files
SOURCES = $(wildcard $(SRC_DIR)/*.c)
OBJECTS = $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)

# Target executable
TARGET = $(BIN_DIR)/$(PROJECT_NAME).exe

# Default target
.PHONY: all doom-game

all: doom-game

doom-game: $(TARGET)

$(TARGET): $(OBJECTS) | $(BIN_DIR)
	@echo "Linking DOOM game..."
	$(LD) $(LDFLAGS) -o $@ $(OBJECTS) $(LIBS)
	@echo "Creating DOOM executable: $@"

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@
