---
[◀️ Tutorial00](Tutorial00.md)  [🏠 Tutorial](Tutorial.md)  [Tutorial00 ▶️](Tutorial00.md)

---

# Introduction
## Building an Operating System from the Bare Metal

Welcome to **AsmOSx86**, a handcrafted operating system built from the ground up in x86 assembly. This tutorial is not just about writing code — it’s about understanding the machine beneath your fingertips. We’ll walk through the bootloader, writing directly to video memory, getting keyboard input, and interrupts with precision, clarity, and purpose.

**AsmOSx86** is built for developers who want deterministic control over every stage of system startup. You'll write a bootloader that directly interfaces with BIOS interrupts, manage segment registers and memory maps manually, and transition into protected mode without relying on external toolchains or runtime environments. Each module — from boot sector to kernel — is crafted in pure x86 assembly, giving you full authority over instruction flow, binary layout, and hardware initialization. This tutorial emphasizes precision, reproducibility, and low-level insight, equipping you to understand the fundamentals of an x86 operating system.

> No C libraries. No abstractions. Just you, x86 assembly, and the bare metal.

The goal of this tutorial is to present functional examples of foundational OS components, with an emphasis on clarity and simplicity. You will see working assembly code alongside a step-by-step breakdown of how it’s built, injected, and executed. By experimenting with these components — even deliberately breaking them — you’ll gain insight into how the system behaves, how to debug failures, and how to evolve AsmOSx86 into something uniquely your own. 

What follows is a series of tutorials that walk you through each stage of building AsmOSx86 from the ground up. Staying true to the bare-metal philosophy, we begin where memory begins — at address zero — with [[Tutorial00]].

---
[◀️ Tutorial00](Tutorial00.md)  [🏠 Tutorial](Tutorial.md)  [Tutorial00 ▶️](Tutorial00.md)

---