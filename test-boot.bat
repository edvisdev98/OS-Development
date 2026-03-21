@echo off
:: ================================================================
:: KSDOS Boot Test Script
:: Tests the bootable medium creation
:: ================================================================

echo [KSDOS Boot Test]
echo ===================

echo Testing bootloader compilation...
cd bootloader\boot
mkdir -p ..\..\build 2>nul
nasm -fbin boot.asm -o ..\..\build\boot.bin
if errorlevel 1 (
    echo ERROR: Bootloader compilation failed
    pause
    exit /b 1
)
echo Bootloader compiled successfully

cd ..\core
echo Compiling core with SDK integration...
gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c core.c -o ..\..\build\core\core.o
gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c ksdos-sdk.c -o ..\..\build\core\ksdos-sdk.o
gcc -Wall -Wextra -ffreestanding -fno-pic -m32 -c game-loader.c -o ..\..\build\core\game-loader.o
as --32 entry.s -o ..\..\build\core\entry.o

if errorlevel 1 (
    echo ERROR: Core compilation failed
    pause
    exit /b 1
)
echo Core compiled successfully

echo Linking kernel...
ld -Tlinker.ld -m elf_i386 ..\..\build\core\entry.o ..\..\build\core\core.o ..\..\build\core\ksdos-sdk.o ..\..\build\core\game-loader.o -o ..\..\build\core\after.bin

echo Creating boot image...
nasm -fbin setup.asm -o ..\..\build\core\early.bin
cat ..\..\build\core\early.bin ..\..\build\core\after.bin > ..\..\build\boot.bin
truncate -s 5120 ..\..\build\boot.bin 2>nul

echo Boot image created successfully!
echo.
echo Testing bootable medium creation...
cd ..\..
call create-bootable.bat

echo.
echo Boot test completed!
echo Files created:
echo   build\boot.bin - KSDOS boot image
echo   ksdos.img     - Bootable floppy
echo   ks-dos.iso    - Bootable CD-ROM
echo.
echo To test in QEMU:
echo   qemu-system-i386 -drive format=raw,file=ksdos.img -boot a
echo.
pause
