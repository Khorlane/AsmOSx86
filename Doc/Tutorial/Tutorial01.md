---
[◀️ Tutorial00](Tutorial00.md)  [🏠 Tutorial](Tutorial.md)  [Tutorial02 ▶️](Tutorial02.md)

---

# The Boot Sector

## Introduction
In this section we will dive deep into the boot sector program which is a set of instructions located in the first sector of a storage device (like a hard drive or floppy) that is responsible for starting a computer's operating system (OS). This is our stage 1 bootloader which sole purpose is load our stage 2 bootloader.

Reminder: The startup sequence is: first - the Boot Sector program boot1, second - boot1 loads boot2, and third - boot2 loads kernel.

## Installing NASM
<details>
  <summary>Installing NASM</summary>

First off, in the repo you'll find `nasm.exe` which is version 2.16.02rc1. This all you really need to complete this tutorial. You can confirm the version by opening a terminal window, ensuring you are in the project folder, and issue this command `./nasm -v`.

If want to install the latest and greatest version of NASM, here's some instructions that worked at the time of this writing.
Navigate to `https://www.nasm.us/` and click on Download (menu at top of the page). Click the release of your choice, find your OS and click it (e.g. wind64) and finally download something like this `nasm-3.00rc18-installer-x64.exe`.

</details>

> ⚠️ **Caution:**  
> Always be careful when downloading and installing software from the internet. Stick to official sources or trusted repositories to avoid malware, corrupted files, or malicious installers. Never run executables from unknown origins, and verify checksums when available. Your system’s security — and your project’s integrity — depend on it.

## Assemble Boot1
This is the boot sector for **AsmOSx86**. The source code file `Boot1.asm` is available in the repository.

To assemble Boot1 using NASM, run this command:

```bash
nasm -f bin Boot1.asm -o Boot1.bin -l Boot1.lst
```

This being the first time running NASM, we'll break down exactly what all this means. The `-f bin` tells NASM that we want a flat binary file, `Boot1.asm` is our assembly code, `-o Boot1.bin` names our output file, and `-l Boot1.lst` is the listing produced.

## Boot1 Overview
There are number of things about a Boot Sector program that **MUST** be exactly as you see in `Boot1.asm`. Most of these are noted in the code, but we'll cover them again for emphasis. The `BIOS Parameter Block`(BPB) **MUST** begin 3 bytes from the start and **MUST** contain those fields. The length of `Boot1.bin` **MUST** be exactly 512 bytes. Lastly, the last two bytes **MUST** be `0xAA55`(Magic Word).

### BPB
This block of code starts with `OEM` which is technically not part of the BPB. There numerous diatribes concerning this field on the web. For our purposes we stick `AsmOSx86` in OEM, which fits in the 8-byte field perfectly. The block ends with `VolumeLabel` and `FileSystem`. In VolumeLabel we again stick `AsmOSx86` in there, but this time with three blanks after it, because VolumneLabel must be exactly 11 bytes. Lastly, FileSystem is set to `FAT12` with 3 blanks after it. VolumeLabel and FileSystem are both descriptive and don't seem break anything if changed.

⚠️ Warning: Unless you fully understand what you're doing, avoid modifying the BIOS Parameter Block (BPB). It's tightly coupled to how the BIOS interprets the boot sector, and careless changes can break boot compatibility.

### The Code
Between the BPB and the Magic Word is the code which loads `Boot2.bin` into memory and then jumps to the loaded stage 2 code. We'll walk through the Boot1.asm code (Stage 1) in the next section of the tutorial.

### Magic Word
Take a look at Boot1.asm, go all the way to the bottom. You should see these two lines:
```
    TIMES 510-($-$$)  db 0              ; make boot sector exactly 512 bytes
                      dw 0xAA55         ; Magic Word that makes this a boot sector
```

Looking at Boot1.lst, go all the way to the bottom. You should see these two lines:
```
304 000001F7 00<rep 7h>                  TIMES 510-($-$$)  db 0              ; make boot sector exactly 512 bytes
305 000001FE 55AA                                          dw 0xAA55         ; Magic Word that makes this a boot sector
```

This is the incantation for ensuring that `Boot1.bin` is **EXACTLY** 512 bytes long and ends with two bytes that contain the hex values of `AA` and `55`.
> ⚙️ **How It Works:**  
> - `$$` marks the start of the current section (usually offset 0).  
> - `$` is the current position in the file.  
> - `($ - $$)` calculates how many bytes have already been emitted.  
> - `TIMES 510 - ($ - $$)` fills the remaining space with zeros.  
> - The final two bytes (`0x55AA`) are reserved for the boot signature and must be emitted separately.

Deep dive into this Magic Word. You will notice in the listing line 305 in the above snippet, we have `dw 0xAA55`, but on the left you see `000001FE 55AA`. To save you some time, Here's the google explanation:

>"The boot sector signature is 0xAA55, which is read as two separate bytes: 0x55 at byte offset 0x1FE and 0xAA at byte offset 0x1FF within the 512-byte boot sector. The confusion between 0xAA55 and 0x55AA arises from endianness; the little-endian x86 architecture stores the 0x55 byte first and the 0xAA byte second, but when expressed as a 16-bit word, it is written as 0xAA55."
> - Google

## Boot Sector
If you want see our carefully crafted, exactly 512 byte boot sector, you can do a hex dump of Boot1.bin using this Powershell command:
```
Format-Hex .\Boot1.bin
```

---
[◀️ Tutorial00](Tutorial00.md)  [🏠 Tutorial](Tutorial.md)  [Tutorial02 ▶️](Tutorial02.md)

---