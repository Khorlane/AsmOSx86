# 🧠 AsmOSx86  
*A Hobbyist Operating System in x86 Assembly*

AsmOSx86 is a 32-bit x86 operating system written entirely in NASM assembly and designed to run  
in protected mode. Its long-term goal is to provide a fully preemptive, priority-based multitasking  
kernel with a clear, minimal, and educational design.

---

## 🧱 OS Design
- Monolithic kernel  
- Preemptive multitasking  
- Priority-based scheduling  

## 🛠️ Development Environment
- Windows 11  
- x86 assembly language  

## 🧮 Target Hardware
- x86 architecture (e.g., Intel 386)  

## 🔧 Toolchain
- NASM (Netwide Assembler)  
- PowerShell scripting  

## 🚀 Execution Environment
- Bochs emulator  
- Real x86 hardware (e.g., 386 PC)  

---

## 📚 Project Wiki  
Explore detailed tutorials and documentation in the [AsmOSx86 Wiki](https://github.com/Khorlane/AsmOSx86/wiki).  
The Wiki needs updating to reflect the move from DOS-based tooling to PowerShell tooling. The underlying concepts remain consistent.

---

## 🏷️ Naming & Abbreviations

AsmOSx86 favors **clarity and consistency over brevity**. Names are generally spelled out in full unless a word is used frequently enough that a standard abbreviation improves readability.

### General conventions
- Prefer full words where practical.
- If a word is abbreviated, it is abbreviated **consistently everywhere**.
- Avoid mixing abbreviated and non-abbreviated forms of the same word.
- Function names may use abbreviations more freely than variable names.
- Pointer variables are prefixed with `p` and are used **only** for variables that store an address.

### Common abbreviations

| Abbreviation | Meaning |
|-------------|---------|
| Addr | Address |
| Attr | Attribute |
| Calc | Calculate |
| Char | Character |
| Col | Column |
| Desc | Descriptor (e.g., GDT/IDT descriptor) |
| Dir | Directory (filesystem context only) |
| Fore | Foreground |
| Hex | Hexadecimal |
| Mem | Memory |
| Msg | Message |
| Ofs | Offset |
| Str | String |
| Sz | Size |
| Tot | Total |
| Vid | Video |
| Xlate | Translate |

### Prefix usage
- Subsystem prefixes are used when there is a clear owner (e.g., `Kb*`, `Tv*`, `Cn*`, `Mm*`, `Ts*`).
- Kernel-wide primitives intended for general use may be unprefixed.
- In ambiguous cases, naming defaults to the **highest-level abstraction**.

These conventions are intended to keep the codebase readable, searchable, and maintainable as the system evolves.