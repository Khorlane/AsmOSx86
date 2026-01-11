---
[◀️ Tutorial00](Tutorial00)  [🏠 Tutorial](Tutorial)  [Tutorial01 ▶️](Tutorial01)

---

# Expectations
It is important to set expectations for AsmOSx86 by telling you what it is **NOT**. AsmOSx86 is **not** a re-write of *nix, **not** innovative, **not** a complete OS, and **not** portable. Another expectation: this tutorial will not attempt to explain everything. With advent of ChatGPT, it is expected that you will go ask ChatGPT/Copilot/Google/whatever to expound on things that are not explained at all or in a less than satisfactory manner.

You can expect the code to compile cleanly and run as intended. This tutorial walks you through every step, command, and detail needed to get AsmOSx86 up and running.

# Development Environment
Windows 11, there are a few parts of the tutorial where it matters. But for most part this tutorial is Host OS agnostic.

# Target Environment
i386 was the first Intel 32-bit processor, marking it a significant evolution in the [x86](https://en.wikipedia.org/wiki/X86) microarchitecture. It is the third-generation x86 architecture [microprocessor](https://en.wikipedia.org/wiki/Microprocessor) developed jointly by [AMD](https://en.wikipedia.org/wiki/AMD), [IBM](https://en.wikipedia.org/wiki/IBM) and [Intel](https://en.wikipedia.org/wiki/Intel).

# Design
AsmOSx86 features a custom two-stage bootloader and a monolithic kernel built for 32-bit protected mode. It uses a flat memory model and supports virtual memory, preemptive multitasking, and priority-based scheduling. The user interface is entirely text-based, with keyboard-only input for simplicity and control.

# Tools Needed
This section provides an overview of the tools required to build and run AsmOSx86. As you progress through the tutorials, each tool will be introduced just-in-time — with guidance on where to find it, how to install it, and how to use it effectively

You're probably surprised to find that you will need an assembler! 😆 This tutorial uses **NASM** to generate flat binary files meaning that they consist solely of the compiled machine instructions and data, directly representing the program's memory image.

You will need something to emulate a real i386 computer. This tutorial uses **Bochs**, a highly portable open-source IA-32 (x86) PC emulator written in C++, that runs on most popular platforms. It includes emulation of the Intel x86 CPU, common I/O devices, and a custom BIOS.

Lastly, an editor to view the assembly code. If you have Visual Studio Code, clone the repo, and double click on `AsmOSx86.code-workspace` you can view and edit the code. **BUT** be clear, this is not required, you can use any editor.

# Booting AsmOSx86
The Bootloader's primary job is to get the kernel loaded and running. So, the startup sequence is: first - the Boot Sector program `boot1`, second - `boot1` loads `boot2`, and third - `boot2` loads `kernel`.  

So how does `boot1` get started? When a PC is powered on, the BIOS (Basic Input/Output System) which is firmware embedded on the motherboard is activated. A key action that the BIOS takes is to find and load our `boot1` program from the `boot sector` which is the first 512 bytes of a storage device.

We'll dive deep into the Boot Sector program in the next two sections of the tutorial.

---
[◀️ Tutorial00](Tutorial00)  [🏠 Tutorial](Tutorial)  [Tutorial01 ▶️](Tutorial01)

---