# KSDOS

16-bit real-mode x86 operating system written in NASM assembly, running in QEMU.

## Architecture

- **Bootloader + Kernel**: `bootloader/kernel/ksdos.asm` — main kernel entry point
- **9 Overlays**: CC, MASM, CSC, MUSIC, NET, OPENGL, PSYQ, GOLD4, IDE — loaded on demand via `ovl_api.asm`
- **Build system**: `Makefile` + `tools/mkimage.pl` — assembles all overlays and embeds them in a FAT12 disk image

## Build

```
make        # build disk.img
make run    # run in QEMU (VNC on :0)
make deploy # package for Raspberry Pi (build/ksdos-watch.tar.gz)
```

## Raspberry Pi Deployment

Files in `raspberry/`:

| File | Purpose |
|---|---|
| `setup.sh` | One-time Pi setup: installs QEMU, configures TFT SPI overlay, compiles vkbd, installs service |
| `launch.sh` | Launch script: starts QEMU + virtual keyboard |
| `vkbd.c` | Virtual keyboard in C: framebuffer rendering + uinput key injection (no QMP socket) |
| `ksdos-watch.service` | systemd unit for auto-start on boot |

### Virtual Keyboard (`vkbd.c`)

- Renders a QWERTY keyboard on the bottom ~36% of the TFT framebuffer
- Reads touch events via Linux evdev (`/dev/input/event*`, auto-detected)
- Injects keypresses into QEMU using **uinput** (a kernel virtual input device)
- No QMP socket is exposed — no attack surface
- Build: `gcc -O2 -o vkbd vkbd.c -lpthread`
- The `setup.sh` script compiles it automatically on the Pi

### Pi Setup

```bash
make deploy
scp build/ksdos-watch.tar.gz pi@<IP>:~/
ssh pi@<IP> "tar xzf ksdos-watch.tar.gz && sudo bash ksdos-watch/setup.sh && sudo reboot"
```

## Key Files

- `bootloader/kernel/ksdos.asm` — kernel main
- `bootloader/kernel/opengl.asm` — software graphics primitives (guarded with `%ifndef`)
- `bootloader/kernel/ovl_api.asm` — overlay loader API
- `bootloader/kernel/compiler_asm.asm` — defines `str_no_space` and compiler helpers
- `tools/mkimage.pl` — builds FAT12 disk image with overlays
- `raspberry/vkbd.c` — touch virtual keyboard (C, uinput)
