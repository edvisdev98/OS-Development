#!/bin/bash
# ================================================================
# KSDOS Bootable Medium Creator (Linux/Mac)
# Creates bootable ISO and disk images
# ================================================================

echo "[KSDOS Bootable Medium Creator]"
echo "==============================="

# Check if build exists
if [ ! -f "build/boot.bin" ]; then
    echo "Building bootloader first..."
    make build-bootloader
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to build bootloader"
        exit 1
    fi
fi

# Create bootable floppy image (1.44MB)
echo "Creating bootable floppy image..."
if command -v mkfs.vfat &> /dev/null; then
    mkfs.vfat -C ksdos.img 1440
    if command -v mcopy &> /dev/null; then
        mcopy -i ksdos.img build/boot.bin ::/boot.bin
    fi
    echo "Created: ksdos.img (1.44MB floppy)"
else
    echo "Creating simple boot image..."
    dd if=/dev/zero of=ksdos.img bs=1024 count=1440
    echo "Created: ksdos.img (1.44MB)"
fi

# Create bootable CD-ROM ISO
echo "Creating bootable CD-ROM ISO..."
if command -v mkisofs &> /dev/null; then
    mkisofs -o ks-dos.iso -b ksdos.img -c bootcat -no-emul-boot -boot-load-size 4 ksdos.img
    echo "Created: ks-dos.iso (bootable CD-ROM)"
elif command -v xorriso &> /dev/null; then
    xorriso -as mkisofs -o ks-dos.iso -b ksdos.img -no-emul-boot -boot-load-size 4 ksdos.img
    echo "Created: ks-dos.iso (bootable CD-ROM)"
elif command -v genisoimage &> /dev/null; then
    genisoimage -o ks-dos.iso -b ksdos.img -c bootcat -no-emul-boot -boot-load-size 4 ksdos.img
    echo "Created: ks-dos.iso (bootable CD-ROM)"
else
    echo "WARNING: No ISO creation tool found"
    echo "Please install mkisofs, xorriso, or genisoimage"
fi

# Create hard disk image (20MB)
echo "Creating hard disk image..."
dd if=/dev/zero of=ksdos-hd.img bs=1024 count=20480
echo "Created: ksdos-hd.img (20MB hard disk)"

# Create virtual machine configuration
echo "Creating VM configuration..."
cat > qemu-run.sh << 'EOF'
#!/bin/bash
# QEMU launch scripts for KSDOS

echo "KSDOS QEMU Launcher"
echo "=================="
echo "1. Floppy boot"
echo "2. Hard disk boot"
echo "3. CD-ROM boot"
echo -n "Choose boot method [1-3]: "
read choice

case $choice in
    1)
        echo "Booting from floppy..."
        qemu-system-i386 -drive format=raw,file=ksdos.img -boot a
        ;;
    2)
        echo "Booting from hard disk..."
        qemu-system-i386 -drive format=raw,file=ksdos-hd.img -boot c
        ;;
    3)
        echo "Booting from CD-ROM..."
        qemu-system-i386 -cdrom ks-dos.iso -boot d
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
EOF

chmod +x qemu-run.sh
echo "Created: qemu-run.sh (QEMU launcher)"

echo
echo "Bootable media created successfully!"
echo
echo "Files created:"
echo "  ksdos.img      - 1.44MB floppy image"
echo "  ks-dos.iso     - Bootable CD-ROM ISO"
echo "  ksdos-hd.img   - 20MB hard disk image"
echo "  qemu-run.sh    - QEMU launcher"
echo
echo "To test:"
echo "  ./qemu-run.sh"
echo "  qemu-system-i386 -drive format=raw,file=ksdos.img -boot a"
echo "  qemu-system-i386 -cdrom ks-dos.iso -boot d"
echo
