# DOOM Engine SDK

A restructured SDK version of the classic DOOM engine source code, organized into a clean 2-folder structure.

## Structure

```
DOOM-SDK/
├── include/          # All header files (.h)
├── lib/              # All source files (.c)
├── Makefile          # Build system
└── README.md         # This file
```

## Building

### Prerequisites
- GCC compiler
- Linux/Unix environment (or Windows with MinGW)

### Compile
```bash
make
```

### Clean build artifacts
```bash
make clean
```

### Other targets
```bash
make help    # Show available targets
make install # Show installation info
```

## Usage

This SDK provides the complete DOOM engine source code in a simplified structure:

- **include/**: Contains all header files with public APIs and internal definitions
- **lib/**: Contains all implementation source files

The include paths have been updated to work with the new structure, so you can directly include headers like:
```c
#include "include/doomdef.h"
#include "include/d_main.h"
```

## Original Source

This SDK is based on the linuxdoom-1.10 source code release by id Software.

## License

DOOM Source Code License as published by id Software. See original LICENSE.TXT file for details.

## Files Moved

The following files have been reorganized from `linuxdoom-1.10/`:
- All `.h` files → `include/`
- All `.c` files → `lib/`

All include statements have been automatically updated to reference the new paths.
