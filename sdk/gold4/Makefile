# DOOM SDK Makefile
# Simplified SDK structure with include/ and lib/ folders

CC = gcc
CFLAGS = -Wall -Wextra -O2 -DNORMALUNIX -DLINUX
INCLUDES = -Iinclude
LIBDIR = lib
INCLUDEDIR = include

# Source files
LIB_SOURCES = $(wildcard $(LIBDIR)/*.c)
OBJECTS = $(LIB_SOURCES:.c=.o)

# Target executable
TARGET = doom

# Default target
all: $(TARGET)

# Build the main executable
$(TARGET): $(OBJECTS)
	$(CC) $(OBJECTS) -o $@ -lm

# Compile source files
$(LIBDIR)/%.o: $(LIBDIR)/%.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Clean build artifacts
clean:
	rm -f $(OBJECTS) $(TARGET)

# Install headers and libraries to system directories (optional)
install: all
	@echo "DOOM SDK built successfully"
	@echo "Headers: $(INCLUDEDIR)/"
	@echo "Sources: $(LIBDIR)/"
	@echo "Executable: $(TARGET)"

# Help target
help:
	@echo "DOOM SDK Makefile"
	@echo "Targets:"
	@echo "  all      - Build the DOOM engine"
	@echo "  clean    - Remove build artifacts"
	@echo "  install  - Show installation info"
	@echo "  help     - Show this help"

.PHONY: all clean install help
