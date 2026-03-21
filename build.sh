#!/bin/bash
# ================================================================
# KSDOS Complete Build System
# Builds bootloader, kernel, SDK, games, and creates bootable media
# ================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Build configuration
BUILD_DIR="build"
DIST_DIR="dist"
KERNEL_VERSION="1.0.0"
BUILD_DATE=$(date +%Y%m%d)

# Function to print colored output
print_status() {
    echo -e "${BLUE}[BUILD]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check dependencies
check_dependencies() {
    print_status "Checking build dependencies..."
    
    local missing_deps=()
    
    # Check for required tools
    for tool in nasm gcc ld make git; do
        if ! command -v $tool &> /dev/null; then
            missing_deps+=($tool)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_status "Please install the missing tools and try again."
        exit 1
    fi
    
    print_success "All dependencies found"
}

# Function to clean previous build
clean_build() {
    print_status "Cleaning previous build..."
    
    rm -rf $BUILD_DIR
    rm -rf $DIST_DIR
    rm -f *.img *.iso *.bin
    
    print_success "Build directory cleaned"
}

# Function to create build directories
create_directories() {
    print_status "Creating build directories..."
    
    mkdir -p $BUILD_DIR/bootloader/boot
    mkdir -p $BUILD_DIR/bootloader/core
    mkdir -p $BUILD_DIR/sdk/psyq/bin
    mkdir -p $BUILD_DIR/sdk/psyq/lib
    mkdir -p $BUILD_DIR/sdk/psyq/include
    mkdir -p $BUILD_DIR/sdk/gold4/bin
    mkdir -p $BUILD_DIR/sdk/gold4/lib
    mkdir -p $BUILD_DIR/sdk/gold4/include
    mkdir -p $BUILD_DIR/games/psx/bin
    mkdir -p $BUILD_DIR/games/psx/build
    mkdir -p $BUILD_DIR/games/doom/bin
    mkdir -p $BUILD_DIR/games/doom/build
    mkdir -p $DIST_DIR
    
    print_success "Build directories created"
}

# Function to build bootloader
build_bootloader() {
    print_status "Building bootloader..."
    
    # Build stage 1 bootloader
    print_status "Building stage 1 bootloader (boot.asm)..."
    nasm -f bin bootloader/boot/boot.asm -o $BUILD_DIR/bootloader/boot.bin
    
    if [ $? -ne 0 ]; then
        print_error "Failed to build stage 1 bootloader"
        exit 1
    fi
    
    # Build setup code
    print_status "Building setup code (setup.asm)..."
    nasm -f bin bootloader/core/setup.asm -o $BUILD_DIR/bootloader/core/early.bin
    
    if [ $? -ne 0 ]; then
        print_error "Failed to build setup code"
        exit 1
    fi
    
    # Build core kernel
    print_status "Building core kernel..."
    nasm -f elf32 bootloader/core/entry.s -o $BUILD_DIR/bootloader/core/entry.o
    
    # Compile C sources
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/core.c -o $BUILD_DIR/bootloader/core/core.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/ksdos-sdk.c -o $BUILD_DIR/bootloader/core/ksdos-sdk.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/game-loader.c -o $BUILD_DIR/bootloader/core/game-loader.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/opengl.c -o $BUILD_DIR/bootloader/core/opengl.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/gl-hardware.c -o $BUILD_DIR/bootloader/core/gl-hardware.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/gl-context.c -o $BUILD_DIR/bootloader/core/gl-context.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/gl-demos.c -o $BUILD_DIR/bootloader/core/gl-demos.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/msdos.c -o $BUILD_DIR/bootloader/core/msdos.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/filesystem.c -o $BUILD_DIR/bootloader/core/filesystem.o
    gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c bootloader/core/system.c -o $BUILD_DIR/bootloader/core/system.o
    
    if [ $? -ne 0 ]; then
        print_error "Failed to compile core kernel"
        exit 1
    fi
    
    # Link kernel
    ld -T bootloader/core/linker.ld -m elf_i386 \
       $BUILD_DIR/bootloader/core/entry.o \
       $BUILD_DIR/bootloader/core/core.o \
       $BUILD_DIR/bootloader/core/ksdos-sdk.o \
       $BUILD_DIR/bootloader/core/game-loader.o \
       $BUILD_DIR/bootloader/core/opengl.o \
       $BUILD_DIR/bootloader/core/gl-hardware.o \
       $BUILD_DIR/bootloader/core/gl-context.o \
       $BUILD_DIR/bootloader/core/gl-demos.o \
       $BUILD_DIR/bootloader/core/msdos.o \
       $BUILD_DIR/bootloader/core/filesystem.o \
       $BUILD_DIR/bootloader/core/system.o \
       -o $BUILD_DIR/bootloader/core/after.bin
    
    if [ $? -ne 0 ]; then
        print_error "Failed to link kernel"
        exit 1
    fi
    
    # Create final boot image
    cat $BUILD_DIR/bootloader/core/early.bin $BUILD_DIR/bootloader/core/after.bin > $BUILD_DIR/boot.bin
    truncate -s 5120 $BUILD_DIR/boot.bin
    
    print_success "Bootloader built successfully"
}

# Function to setup SDKs
setup_sdks() {
    print_status "Setting up SDKs..."
    
    # Create SDK directories
    mkdir -p $BUILD_DIR/sdk/psyq/{bin,lib,include}
    mkdir -p $BUILD_DIR/sdk/gold4/{bin,lib,include}
    
    # Create dummy SDK files (in a real build, these would be actual SDK files)
    touch $BUILD_DIR/sdk/psyq/bin/mipsel-none-elf-gcc
    touch $BUILD_DIR/sdk/psyq/bin/mipsel-none-elf-ld
    touch $BUILD_DIR/sdk/psyq/lib/libps.a
    touch $BUILD_DIR/sdk/psyq/include/psx.h
    touch $BUILD_DIR/sdk/psyq/include/libps.h
    
    touch $BUILD_DIR/sdk/gold4/bin/djgpp-gcc
    touch $BUILD_DIR/sdk/gold4/bin/ld.gold
    touch $BUILD_DIR/sdk/gold4/lib/libgold4.a
    touch $BUILD_DIR/sdk/gold4/include/gold4.h
    touch $BUILD_DIR/sdk/gold4/include/djgpp.h
    
    print_success "SDKs setup completed"
}

# Function to build games
build_games() {
    print_status "Building games..."
    
    # Build PS1 game
    print_status "Building PS1 game..."
    cd games/psx
    make clean || true
    make
    cd ../..
    
    # Build DOOM game
    print_status "Building DOOM game..."
    cd games/doom
    make clean || true
    make
    cd ../..
    
    print_success "Games built successfully"
}

# Function to create bootable media
create_bootable_media() {
    print_status "Creating bootable media..."
    
    # Create floppy image
    print_status "Creating 1.44MB floppy image..."
    dd if=/dev/zero of=$DIST_DIR/ksdos.img bs=1024 count=1440
    dd if=$BUILD_DIR/boot.bin of=$DIST_DIR/ksdos.img conv=notrunc
    
    # Create CD-ROM ISO
    print_status "Creating CD-ROM ISO..."
    mkdir -p $DIST_DIR/iso
    cp $BUILD_DIR/boot.bin $DIST_DIR/iso/
    cp -r games $DIST_DIR/iso/
    cp -r sdk $DIST_DIR/iso/
    cp README*.md $DIST_DIR/iso/
    
    # Create ISO (requires mkisofs or xorriso)
    if command -v mkisofs &> /dev/null; then
        mkisofs -o $DIST_DIR/ks-dos.iso -b boot.bin -no-emul-boot -boot-load-size 4 $DIST_DIR/iso/
    elif command -v xorriso &> /dev/null; then
        xorriso -as mkisofs -o $DIST_DIR/ks-dos.iso -b boot.bin -no-emul-boot -boot-load-size 4 $DIST_DIR/iso/
    else
        print_warning "mkisofs/xorriso not found, skipping ISO creation"
    fi
    
    # Create hard disk image
    print_status "Creating 20MB hard disk image..."
    dd if=/dev/zero of=$DIST_DIR/ksdos-hd.img bs=1024 count=20480
    dd if=$BUILD_DIR/boot.bin of=$DIST_DIR/ksdos-hd.img conv=notrunc
    
    print_success "Bootable media created"
}

# Function to run tests
run_tests() {
    print_status "Running tests..."
    
    # Test kernel compilation
    if [ -f $BUILD_DIR/boot.bin ]; then
        print_success "Kernel compilation test passed"
    else
        print_error "Kernel compilation test failed"
        exit 1
    fi
    
    # Test boot image creation
    if [ -f $DIST_DIR/ksdos.img ]; then
        print_success "Boot image creation test passed"
    else
        print_error "Boot image creation test failed"
        exit 1
    fi
    
    print_success "All tests passed"
}

# Function to generate build report
generate_report() {
    print_status "Generating build report..."
    
    local report_file="$DIST_DIR/build-report-$BUILD_DATE.txt"
    
    cat > $report_file << EOF
KSDOS Build Report
==================
Build Date: $(date)
Kernel Version: $KERNEL_VERSION
Build Host: $(hostname)

Build Artifacts:
- Boot Image: ksdos.img ($(stat -c%s $DIST_DIR/ksdos.img 2>/dev/null || echo "N/A") bytes)
- CD-ROM ISO: ks-dos.iso ($(stat -c%s $DIST_DIR/ks-dos.iso 2>/dev/null || echo "N/A") bytes)
- Hard Disk: ksdos-hd.img ($(stat -c%s $DIST_DIR/ksdos-hd.img 2>/dev/null || echo "N/A") bytes)

Components Built:
- Bootloader: Stage 1 + Stage 2
- Kernel: Core with OpenGL, MS-DOS, Filesystem, System Management
- SDKs: PSYq (PS1), GOLD4 (DOOM)
- Games: PS1 Demo, DOOM Demo

Features:
- OpenGL 1.5 Real Implementation
- MS-DOS 6.22 Compatible Commands
- FAT12/16/32 File System
- Hardware Acceleration
- Multi-Context OpenGL
- Real System Management
- Virtual Disk Support
- Boot Menu System

Build Configuration:
- Target: i386 32-bit
- Compiler: GCC $(gcc --version | head -n1)
- Assembler: NASM $(nasm -v | head -n1)
- Linker: GNU LD

EOF
    
    print_success "Build report generated: $report_file"
}

# Function to create distribution package
create_package() {
    print_status "Creating distribution package..."
    
    local package_name="ksdos-$KERNEL_VERSION-$BUILD_DATE"
    local package_dir="$DIST_DIR/$package_name"
    
    mkdir -p $package_dir
    
    # Copy essential files
    cp $DIST_DIR/*.img $package_dir/
    cp $DIST_DIR/*.iso $package_dir/ 2>/dev/null || true
    cp README*.md $package_dir/
    cp -r bootloader $package_dir/
    cp -r sdk $package_dir/
    cp -r games $package_dir/
    cp build.sh $package_dir/
    cp create-bootable.sh $package_dir/
    
    # Create package info
    cat > $package_dir/PACKAGE_INFO.txt << EOF
KSDOS - Complete MS-DOS Compatible Operating System
Version: $KERNEL_VERSION
Build Date: $(date)
Package: $package_name

Installation:
1. Use ksdos.img for floppy boot
2. Use ks-dos.iso for CD-ROM boot
3. Use ksdos-hd.img for hard disk boot

Testing:
qemu-system-i386 -drive format=raw,file=ksdos.img -boot a
qemu-system-i386 -cdrom ks-dos.iso -boot d

Features:
- Complete MS-DOS 6.22 compatibility
- OpenGL 1.5 real implementation
- Hardware acceleration support
- FAT12/16/32 file system
- PS1 and DOOM SDK integration
- Real system management
- Multi-context OpenGL rendering
- Boot menu system
- Virtual disk support

EOF
    
    # Create tar.gz package
    cd $DIST_DIR
    tar -czf $package_name.tar.gz $package_name/
    cd ..
    
    print_success "Package created: $DIST_DIR/$package_name.tar.gz"
}

# Function to show usage
show_usage() {
    echo "KSDOS Build System"
    echo "=================="
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  clean        Clean build directory"
    echo "  bootloader   Build bootloader only"
    echo "  kernel       Build kernel only"
    echo "  sdks         Setup SDKs only"
    echo "  games        Build games only"
    echo "  media        Create bootable media only"
    echo "  tests        Run tests only"
    echo "  package      Create distribution package"
    echo "  all          Build everything (default)"
    echo "  help         Show this help"
    echo ""
    echo "Examples:"
    echo "  $0              # Build everything"
    echo "  $0 clean        # Clean build"
    echo "  $0 bootloader   # Build bootloader only"
    echo "  $0 package      # Create distribution package"
}

# Main build function
main() {
    echo "KSDOS Build System v$KERNEL_VERSION"
    echo "=================================="
    echo ""
    
    # Check if we're in the right directory
    if [ ! -f "bootloader/core/core.c" ]; then
        print_error "Please run this script from the KSDOS root directory"
        exit 1
    fi
    
    # Parse command line arguments
    case "${1:-all}" in
        "clean")
            clean_build
            ;;
        "bootloader")
            check_dependencies
            create_directories
            build_bootloader
            ;;
        "kernel")
            check_dependencies
            create_directories
            build_bootloader
            ;;
        "sdks")
            create_directories
            setup_sdks
            ;;
        "games")
            check_dependencies
            create_directories
            setup_sdks
            build_games
            ;;
        "media")
            create_directories
            create_bootable_media
            ;;
        "tests")
            run_tests
            ;;
        "package")
            create_directories
            create_package
            ;;
        "all")
            check_dependencies
            clean_build
            create_directories
            build_bootloader
            setup_sdks
            build_games
            create_bootable_media
            run_tests
            generate_report
            create_package
            ;;
        "help"|"-h"|"--help")
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    
    echo ""
    print_success "Build completed successfully!"
    echo ""
    echo "Build artifacts:"
    if [ -f "$DIST_DIR/ksdos.img" ]; then
        echo "  - Floppy image: $DIST_DIR/ksdos.img"
    fi
    if [ -f "$DIST_DIR/ks-dos.iso" ]; then
        echo "  - CD-ROM ISO: $DIST_DIR/ks-dos.iso"
    fi
    if [ -f "$DIST_DIR/ksdos-hd.img" ]; then
        echo "  - Hard disk: $DIST_DIR/ksdos-hd.img"
    fi
    if [ -f "$DIST_DIR/ksdos-$KERNEL_VERSION-$BUILD_DATE.tar.gz" ]; then
        echo "  - Package: $DIST_DIR/ksdos-$KERNEL_VERSION-$BUILD_DATE.tar.gz"
    fi
    echo ""
    echo "To test:"
    echo "  qemu-system-i386 -drive format=raw,file=$DIST_DIR/ksdos.img -boot a"
    echo "  qemu-system-i386 -cdrom $DIST_DIR/ks-dos.iso -boot d"
}

# Run main function with all arguments
main "$@"
