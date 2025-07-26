OS Development Dev Kit
Made by EdvinasDev_98, 2025
Project files are open-sourced. Please feel free to use them.

Required Tools:
    Before getting started, please download and install the following tools:

    NASM - Assembler used to compile .asm files into bootable .img files.

    QEMU - Virtual machine emulator for testing and running your custom bootloader.

    Note: After installing the tools, make sure to add them to your system environment variables so you can run them from any terminal or command prompt.

Example Files:
    Inside the Examples/ folder, you will find bootloader examples:

    HelloWorld.asm
    Prints "Hello World!" to the screen.
    Includes beginner-friendly comments to help you understand the code.

    PrintCharacters.asm
    Prints characters from A-Z, a-z, and 0-9 using BIOS interrupts.

Compilation & Testing:

    To Compile a Bootloader
    Use NASM to assemble the .asm file into a raw binary .img:
    
    nasm -f bin <filename>.asm -o <outputname>.img

    To Run the Bootloader in QEMU:
    Use QEMU to boot and test your .img file:
    
    qemu-system-x86_64 -fda <outputname>.img

Happy Coding!
This dev kit is designed to help you get started with low-level OS development. Explore, experiment, and have fun creating your own bootloaders and eventually - your own operating system!

