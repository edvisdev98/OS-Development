# 🛠️ OS Development Dev Kit

**Made by EdvinasDev_98, 2025**

Project files are open-sourced. Please feel free to use them.

---

## 🧰 Required Tools

Before getting started, please download and install the following tools:

- **NASM** – Assembler used to compile `.asm` files into bootable `.img` files.
- **QEMU** – Virtual machine emulator for testing and running your custom bootloader.

> **Note:** After installing the tools, make sure to add them to your system environment variables so you can run them from any terminal or command prompt.

---

## 📁 Example Files

Inside the `Examples/` folder, you will find bootloader examples:

| **File Name**             | **Description** |
|--------------------------|-----------------|
| **🔹 HelloWorld.asm**     | - Prints **"Hello World!"** to the screen.<br>- Includes beginner-friendly comments to help you understand the code. |
| **🔹 PrintCharacters.asm**| - Prints characters from **A-Z, a-z, and 0-9** using BIOS interrupts. |
| **🔹 CheckRAM.asm**       | - Checks and displays RAM size up to **1 MB** (typically around 640 KB). |
| **🔹 ClearScreen.asm**    | - Clears the entire **text-mode screen** by filling it with blank spaces and a specified color attribute.<br>- Resets the cursor position to the **top-left corner** (row 0, column 0).<br>- Uses **direct video memory access** and BIOS interrupts to manipulate the screen and cursor. |
| **🔹 BackgroundColor.asm**| - Changes the **background color** of the entire text-mode screen.<br>- Directly writes blank spaces with the specified background color attribute into video memory. |
| **🔹 TextFontColor.asm**  | - Changes the **text (foreground) color** displayed on the screen while leaving the background color unchanged. |

**Note:** `VGA Color Codes for Text Mode.jpg` includes a table listing HEX color codes for use with `BackgroundColor.asm` and `TextFontColor.asm`.
---

## ⚙️ Compilation & Testing

To Compile a Bootloader: 
- Use NASM to assemble the `.asm` file into a raw binary `.img`:

- nasm -f bin <filename>.asm -o <filename>.img

---

To Run the Bootloader in QEMU:
- Use QEMU to boot and test your `.img` file:

- qemu-system-x86_64 -fda <filename>.img

