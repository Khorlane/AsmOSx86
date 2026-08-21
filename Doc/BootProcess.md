# Boot Process

This document describes how AsmOSx86 gets from a blank floppy image to a
bootable disk, and then how the boot path proceeds from BIOS handoff through
`Boot.asm` and into the protected-mode kernel.

## From Blank Image to Boot Disk

AsmOSx86 currently uses a 1.44MB raw floppy image named `floppy.img`.

The boot disk is created in two broad phases:

1. Prepare the blank floppy image and write the boot sector.
2. Write the AsmOSx86 manifest and packed kernel/runtime files.

The main preparation script is:

```powershell
.\BuildWriteBoot.ps1
```

That script assumes it is run from the `Scripts` folder.

## BuildWriteBoot.ps1

`BuildWriteBoot.ps1` creates a fresh floppy image and installs the boot sector.

Its input is:

```text
Boot.bin
```

Its output is:

```text
floppy.img
```

The script does this:

1. Verifies `Boot.bin` exists.
2. Verifies `Boot.bin` is exactly 512 bytes.
3. Deletes any existing `floppy.img`.
4. Creates a new 1,474,560-byte image.
5. Writes `Boot.bin` directly to byte offset 0.
6. Verifies the boot signature at bytes `510-511` is `55 AA`.

The script does not format the image as FAT12.

## Raw Floppy Layout

The current floppy layout is:

```text
Sector 0      Boot.bin
Sector 1      AsmOSx86 file manifest
Sector 2+     Kernel.bin
Next sectors  Prog1.bin
Next sectors  Prog2.bin
Next sectors  Prog3.bin
Next sectors  Prog4.bin, if present
Next sectors  Data.txt, if present
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

That script writes the manifest and raw file data.

`KERNEL.BIN` is required.

The script also includes optional files when they exist:

```text
PROG1.BIN
PROG2.BIN
PROG3.BIN
PROG4.BIN
DATA.TXT
```

`Run3` can launch `PROG1.BIN`, `PROG2.BIN`, and `PROG3.BIN` together from the
console.

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

At this point, AsmOSx86 is executing `Boot.asm`.

## Boot Role

`Boot.asm` is the current AsmOSx86 boot loader.

It is deliberately small because it must fit in one 512-byte boot sector, but it
now performs the whole boot handoff itself. There is no separate `Boot2.asm`
stage in the current boot path.

Boot is responsible for:

- setting up enough real-mode state to run predictably
- installing a small IRQ6 handler for floppy-controller interrupts
- initializing the floppy controller directly
- reading the AsmOSx86 manifest from sector 1
- finding `KERNEL.BIN` in the manifest
- enabling A20
- loading `KERNEL.BIN` directly to physical address `00100000h`
- installing a minimal GDT
- entering protected mode
- jumping to the kernel entry point

Boot does not use BIOS interrupts after the BIOS transfers control to it.

Boot does not read a FAT12 root directory or FAT table.

## What Boot.asm Does

Boot starts in 16-bit real mode at `0000:7C00`.

The first setup step clears interrupts, sets `DS` and `SS` to zero, places the
stack at `0000:7C00`, and clears the direction flag. With `org 07C00h`, labels in
Boot line up with the address where the BIOS loaded the sector.

Boot then installs its own real-mode IRQ6 handler at interrupt vector `0Eh`.
IRQ6 is the floppy-controller interrupt. The handler only marks
`FdcDone = 1`, sends an end-of-interrupt to the PIC, and returns.

Next, Boot unmasks IRQ6 on the master PIC and initializes the primary floppy
controller. The current loader assumes a simple PC-compatible 1.44MB drive A:
configuration:

```text
18 sectors per track
2 heads
512-byte sectors
500 Kbit/s data rate
```

Once the controller is ready, Boot reads logical sector 1 into memory at:

```text
0000:0500
```

That sector contains the `ASMF` manifest. Boot walks the manifest entries,
looking for the uppercase 8.3 name:

```text
KERNEL  BIN
```

When the entry is found, Boot reads the starting sector and sector count from
the manifest entry.

Before loading the kernel, Boot enables A20 using the fast A20 gate at port
`092h`. This is needed because the kernel is loaded above the 1MB boundary.

Boot then reads each kernel sector from the floppy and writes it directly to
physical memory starting at:

```text
00100000h
```

The floppy DMA setup uses `BX` for the low 16 bits of the destination address
and `FdcDmaPage` for the DMA page register. For the kernel load, `FdcDmaPage` is
set to `10h`, which makes the destination physical page `00100000h`.

After the kernel sectors are loaded, Boot disables interrupts, loads a minimal
GDT, sets `CR0.PE`, and performs a far jump:

```asm
jmp   CODE_SEL:Protected
```

The far jump reloads `CS` with the protected-mode code selector and lands at the
`Protected` label in Boot.

At `Protected`, Boot switches `DS`, `ES`, and `SS` to the protected-mode data
selector, sets the stack to:

```text
00090000h
```

and then jumps to:

```text
CODE_SEL:00100000h
```

That is the start of `Kernel.asm`. At that point Boot is finished and the
protected-mode kernel owns execution.

## Entering Protected Mode

Before switching modes, Boot installs a small GDT with:

- a null descriptor
- a flat 32-bit code descriptor
- a flat 32-bit data descriptor

Boot enables A20 before loading the kernel above 1MB.

To enter protected mode, Boot sets bit 0 in `CR0`:

```text
CR0.PE = 1
```

Then it performs a far jump to reload `CS` with the protected-mode code
selector.

Boot intentionally does not leave interrupts enabled for the kernel handoff.

## End-to-End Summary

The full path looks like this:

```text
BuildBoot.ps1
  -> Boot.asm becomes Boot.bin

BuildWriteBoot.ps1
  -> creates blank floppy.img
  -> writes Boot.bin to sector 0

BuildKernel.ps1
  -> Kernel.asm and included modules become Kernel.bin

BuildPrograms.ps1
  -> Prog1/2/3/4.asm become raw Prog*.bin

BuildCopy.ps1
  -> writes the ASMF manifest to sector 1
  -> writes Kernel.bin and optional runtime files contiguously from sector 2

BIOS
  -> loads sector 0 to 0000:7C00
  -> jumps to Boot

Boot
  -> initializes enough floppy-controller hardware to read sectors directly
  -> reads sector 1 manifest
  -> finds KERNEL.BIN
  -> enables A20
  -> loads KERNEL.BIN directly to 00100000h
  -> enters protected mode
  -> jumps to Kernel.asm
```
