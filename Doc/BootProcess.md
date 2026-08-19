# Boot Process

This document describes how AsmOSx86 gets from a blank floppy image to a
bootable disk, and then how the boot path proceeds from BIOS handoff through
`Boot1.asm`, `Boot2.asm`, and finally the protected-mode kernel.

## From Blank Image to Boot Disk

AsmOSx86 currently uses a 1.44MB raw floppy image named `floppy.img`.

The boot disk is created in two broad phases:

1. Prepare the blank floppy image and write the stage 1 boot sector.
2. Write the AsmOSx86 manifest and packed boot/runtime files.

The main preparation script is:

```powershell
.\BuildWriteBoot1.ps1
```

That script assumes it is run from the `Scripts` folder.

## BuildWriteBoot1.ps1

`BuildWriteBoot1.ps1` creates a fresh floppy image and installs the stage 1 boot
sector.

Its input is:

```text
Boot1.bin
```

Its output is:

```text
floppy.img
```

The script does this:

1. Verifies `Boot1.bin` exists.
2. Verifies `Boot1.bin` is exactly 512 bytes.
3. Deletes any existing `floppy.img`.
4. Creates a new 1,474,560-byte image.
5. Writes `Boot1.bin` directly to byte offset 0.
6. Verifies the boot signature at bytes `510-511` is `55 AA`.

The script does not format the image as FAT12.

## Raw Floppy Layout

The current floppy layout is:

```text
Sector 0      Boot1.bin
Sector 1      AsmOSx86 file manifest
Sector 2+     Boot2.bin
Next sectors  Kernel.bin
Next sectors  Prog1.bin
Next sectors  Prog2.bin
Next sectors  Prog3.bin
```

The manifest is one 512-byte sector.

Manifest header:

```text
Offset 0  4 bytes  Signature: ASMF
Offset 4  2 bytes  Version: 1
Offset 6  2 bytes  Entry count
Offset 16          First file entry
```

Each manifest entry is 32 bytes:

```text
Offset +0   11 bytes  Uppercase 8.3 file name
Offset +12   4 bytes  Starting sector
Offset +16   4 bytes  File byte size
Offset +20   4 bytes  File sector count
```

File data is packed contiguously after the manifest and rounded up to whole
512-byte sectors.

## Copying Files After Preparation

After `floppy.img` exists, the normal copy script is:

```powershell
.\BuildCopy.ps1
```

That script writes manifest entries and raw file data for:

```text
BOOT2.BIN
KERNEL.BIN
PROG1.BIN
PROG2.BIN
PROG3.BIN
```

`BOOT2.BIN` and `KERNEL.BIN` are required. The user programs are optional, but
`UserTest` expects all three to be present.

## Real Hardware Note

`floppy.img` is intended to remain a standard 1.44MB sector image that can later
be written sector-for-sector to a real floppy, for example with WinImage and a
USB floppy drive.

It is no longer intended to be mounted or edited as a FAT12 floppy.

## BIOS Handoff

When the machine boots from the floppy, the BIOS loads sector 0 into memory at:

```text
0000:7C00
```

Then the BIOS jumps to that loaded boot sector.

At this point, AsmOSx86 is executing `Boot1.asm`.

The BIOS also provides the boot drive number in `DL`. `Boot1.asm` stores that
value so later BIOS disk reads use the same drive the BIOS booted from.

## Boot1 Role

`Boot1.asm` is the stage 1 boot loader.

Its job is deliberately small because it must fit in one 512-byte boot sector.

Boot1 is responsible for:

- printing the stage 1 startup message
- reading the AsmOSx86 manifest from sector 1
- finding `BOOT2.BIN` in the manifest
- loading Boot2 into memory at `0050:0000`
- transferring control to Boot2 with a far return

Boot1 uses BIOS interrupts because it is still in 16-bit real mode.

For screen output it uses:

```text
INT 10h
```

For floppy reads it uses:

```text
INT 13h
```

Boot1 does not read a FAT12 root directory or FAT table.

## Boot2 Role

`Boot2.asm` is the stage 2 boot loader.

Boot2 is larger than Boot1 and is loaded from the raw sectors named by the
manifest. Its job is to do the work that is too large or too awkward for the
512-byte boot sector.

Boot2 is responsible for:

- setting up real-mode segment registers and stack
- installing a Global Descriptor Table
- enabling the A20 line
- reading the AsmOSx86 manifest from sector 1
- finding `KERNEL.BIN` in the manifest
- loading `KERNEL.BIN` into low memory
- entering protected mode
- setting 32-bit segment registers
- copying the kernel to 1MB
- jumping to the kernel entry point

Boot2 is assembled with:

```text
org 0500h
```

That matches where Boot1 loads it:

```text
0050:0000
```

## Boot2 Loading the Kernel

Boot2 searches the AsmOSx86 manifest for:

```text
KERNEL  BIN
```

It loads the manifest to:

```text
ManifestSegment:0000 = 02E0:0000
```

It loads `KERNEL.BIN` into real-mode memory at:

```text
RModeBase = 00003000h
```

The loader tracks how many sectors were read in `Stage3Size`.

This is still done in 16-bit real mode using BIOS disk services.

## Entering Protected Mode

Before switching modes, Boot2 installs a small GDT with:

- a null descriptor
- a flat 32-bit code descriptor
- a flat 32-bit data descriptor

Boot2 also enables the A20 line through the 8042 keyboard controller. A20 must
be enabled before using memory above 1MB.

To enter protected mode, Boot2 sets bit 0 in `CR0`:

```text
CR0.PE = 1
```

Then it performs a far jump to reload `CS` with the protected-mode code
selector.

Boot2 intentionally does not enable interrupts.

## Boot2 Jumping to the Kernel

Once in protected mode, Boot2 switches to 32-bit code and sets:

```text
DS = data selector
SS = data selector
ES = data selector
ESP = 00090000h
```

Then it copies the kernel from its temporary real-mode load address:

```text
00003000h
```

to its protected-mode runtime address:

```text
00100000h
```

Finally, Boot2 jumps to:

```text
CodeDesc:00100000h
```

That is the start of `Kernel.asm`.

At that point Boot2 is finished and the protected-mode kernel owns execution.

## End-to-End Summary

The full path looks like this:

```text
BuildBoot1.ps1
  -> Boot1.asm becomes Boot1.bin

BuildWriteBoot1.ps1
  -> creates blank floppy.img
  -> writes Boot1.bin to sector 0

BuildBoot2.ps1
  -> Boot2.asm becomes Boot2.bin

BuildKernel.ps1
  -> Kernel.asm and included modules become Kernel.bin

BuildPrograms.ps1
  -> Prog1/2/3.asm become raw Prog1/2/3.bin

BuildCopy.ps1
  -> writes the ASMF manifest to sector 1
  -> writes Boot2, Kernel, and Prog*.bin contiguously from sector 2

BIOS
  -> loads sector 0 to 0000:7C00
  -> jumps to Boot1

Boot1
  -> reads sector 1 manifest
  -> finds and loads BOOT2.BIN at 0050:0000
  -> jumps to Boot2

Boot2
  -> reads sector 1 manifest
  -> finds and loads KERNEL.BIN at 00003000h
  -> enters protected mode
  -> copies kernel to 00100000h
  -> jumps to Kernel.asm
```
