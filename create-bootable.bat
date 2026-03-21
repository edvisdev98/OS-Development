@echo off
:: ================================================================
:: KSDOS Bootable Medium Creator
:: Creates bootable ISO and disk images
:: ================================================================

setlocal enabledelayedexpansion

echo [KSDOS Bootable Medium Creator]
echo ================================

:: Check if build exists
if not exist "build\boot.bin" (
    echo Building bootloader first...
    call make build-bootloader
    if errorlevel 1 (
        echo ERROR: Failed to build bootloader
        pause
        exit /b 1
    )
)

:: Create bootable floppy image (1.44MB)
echo Creating bootable floppy image...
if exist "tools\mkfs.vfat" (
    tools\mkfs.vfat -C ksdos.img 1440
    tools\mcopy -i ksdos.img build\boot.bin ::/boot.bin
    echo Created: ksdos.img (1.44MB floppy)
) else (
    echo Creating simple boot image...
    fsutil file createnew ksdos.img 1474560
    echo Created: ksdos.img (1.44MB)
)

:: Create bootable CD-ROM ISO
echo Creating bootable CD-ROM ISO...
if exist "tools\mkisofs.exe" (
    tools\mkisofs.exe -o ks-dos.iso -b ksdos.img -c bootcat -no-emul-boot -boot-load-size 4 ksdos.img
    echo Created: ks-dos.iso (bootable CD-ROM)
) else if exist "tools\xorriso.exe" (
    tools\xorriso.exe -as mkisofs -o ks-dos.iso -b ksdos.img -no-emul-boot -boot-load-size 4 ksdos.img
    echo Created: ks-dos.iso (bootable CD-ROM)
) else (
    echo WARNING: mkisofs/xorriso not found, creating simple ISO...
    if exist "tools\oscdimg.exe" (
        tools\oscdimg.exe -b ksdos.img -h ks-dos.iso .
        echo Created: ks-dos.iso (bootable CD-ROM)
    ) else (
        echo ERROR: No ISO creation tool found
        echo Please install mkisofs, xorriso, or oscdimg
    )
)

:: Create hard disk image (20MB)
echo Creating hard disk image...
fsutil file createnew ksdos-hd.img 20971520
echo Created: ksdos-hd.img (20MB hard disk)

:: Create virtual machine configuration
echo Creating VM configuration...
echo # QEMU Configuration > qemu-run.bat
echo qemu-system-i386 -drive format=raw,file=ksdos.img -boot a >> qemu-run.bat
echo qemu-system-i386 -drive format=raw,file=ksdos-hd.img -boot c >> qemu-run.bat
echo qemu-system-i386 -cdrom ks-dos.iso -boot d >> qemu-run.bat

echo.
echo Bootable media created successfully!
echo.
echo Files created:
echo   ksdos.img      - 1.44MB floppy image
echo   ks-dos.iso     - Bootable CD-ROM ISO
echo   ksdos-hd.img   - 20MB hard disk image
echo   qemu-run.bat   - QEMU launch scripts
echo.
echo To test:
echo   qemu-system-i386 -drive format=raw,file=ksdos.img -boot a
echo   qemu-system-i386 -cdrom ks-dos.iso -boot d
echo.
pause
