# 🛠️ OS Development Dev Kit

**Created by [EdvinasDev_98](https://github.com/EdvinasDev_98) — 2025**

Welcome to the **OS Development Dev Kit** — a simple starter pack to help you begin your journey into low-level OS development. This kit includes bootloader examples, essential tools, and guidance to get you up and running quickly.

---

## 📂 Project Status

> ✅ Open-source and ready to use!

Feel free to fork, modify, or use any of the files for your personal or professional projects.

---

## 🧰 Required Tools

Before you begin, make sure you have the following installed:

- **[NASM](https://www.nasm.us/)** – Assembler for compiling `.asm` files into bootable `.img` files.
- **[QEMU](https://www.qemu.org/)** – Virtual machine emulator to test your custom bootloader.

> **Note:** After installing, add both NASM and QEMU to your system's PATH so they are accessible via terminal/command prompt.

---

## 📁 Example Bootloaders

Explore the `Examples/` folder for well-documented `.asm` files:

| Filename              | Description |
|-----------------------|-------------|
| `HelloWorld.asm`      | Prints "Hello World!" to the screen. Great starting point with beginner-friendly comments. |
| `PrintCharacters.asm` | Displays characters A-Z, a-z, and 0-9 using BIOS interrupts. |
| `CheckRAM.asm`        | Checks and displays RAM size (up to ~640 KB using BIOS). |
| `ClearScreen.asm`     | Clears the screen and resets the cursor using video memory and BIOS interrupts. |
| `BackgroundColor.asm` | Changes the screen background color using direct video memory writes. |
| `TextFontColor.asm`   | Alters the text (foreground) color while preserving the background. |

> 📌 **Tip:** Check the included `VGA Color Codes for Text Mode.jpg` for hex color reference.

---

## ⚙️ Compilation & Testing

### 🧱 To Compile a Bootloader:

```bash
nasm -f bin <filename>.asm -o <filename>.img
