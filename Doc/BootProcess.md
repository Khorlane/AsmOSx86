# Boot Process

This document describes how AsmOSx86 gets from a blank floppy image to a
bootable disk, and then how the boot path proceeds from BIOS handoff through
`Boot1.asm`, `Boot2.asm`, and finally the protected-mode kernel.

## From Blank Image to Boot Disk

AsmOSx86 uses a 1.44MB floppy image named `floppy.img`.

The boot disk is created in two broad phases:

1. Prepare the floppy image and boot sector.
2. Copy the boot/runtime files into the FAT12 filesystem.

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
5. Mounts the image through ImDisk as a floppy.
6. Formats the image as FAT.
7. Unmounts the formatted image.
8. Marks sectors `512-2879` as bad FAT12 clusters.
9. Writes `Boot1.bin` directly to byte offset 0.
10. Verifies the boot signature at bytes `510-511` is `55 AA`.

The important detail is the ordering.

The image is formatted first so Windows creates a normal FAT filesystem. Then
the script edits the FAT directly to reserve sectors `512-2879` for future
AsmOSx86 storage. Finally, the script writes `Boot1.bin` over sector 0.

This works because `Boot1.bin` contains a FAT12-compatible BIOS Parameter Block
near the beginning of the boot sector. The disk remains understandable as a
FAT12 floppy, while still using AsmOSx86's own boot code in sector 0.

## FAT12 Layout

The current floppy layout is the standard 1.44MB FAT12 layout:

```text
Sector 0       Boot sector / BPB / Boot1 code
Sectors 1-9    FAT #1
Sectors 10-18  FAT #2
Sectors 19-32  Root directory
Sectors 33-511 FAT-visible data area
Sectors 512+   Reserved for future AsmOSx86 storage
```

FAT12 cluster 2 begins at sector 33. Because this image uses one sector per
cluster, sector-to-cluster conversion is straightforward:

```text
cluster = (sector - 33) + 2
```

So sector `512` maps to cluster `481`.

`BuildWriteBoot1.ps1` marks clusters `481-2848` as `0xFF7` in both FAT copies.
That marks those clusters as bad/unavailable from FAT12's point of view.

The goal is not to hide that space from AsmOSx86. The goal is to stop normal
FAT copy tools from allocating visible files into the future custom filesystem
area.

## Real Hardware Note

`floppy.img` is intended to remain a standard 1.44MB FAT12 floppy image that can
later be written sector-for-sector to a real floppy, for example with WinImage
and a USB floppy drive.

The written floppy should preserve sector 0 from `Boot1.bin`, the FAT root files
such as `BOOT2.BIN`, `KERNEL.BIN`, and `PROG*.BIN`, and the reserved
AsmOSx86 storage area beginning at sector `512`.

## Copying Files After Preparation

`BuildWriteBoot1.ps1` only prepares the floppy image and writes `Boot1.bin`.
It does not copy `Boot2.bin`, `Kernel.bin`, or user programs into the FAT12
root directory.

After preparation, the normal copy script is:

```powershell
.\BuildCopy.ps1
```

That script copies:

```text
BOOT2.BIN
KERNEL.BIN
PROG1.BIN
PROG2.BIN
PROG3.BIN
```

`BuildCopy.ps1` also validates that copied FAT12 files remain below sector
`512`. This protects the reserved AsmOSx86 storage area from accidental FAT
allocation.

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

- providing a FAT12-compatible boot sector and BPB
- printing the stage 1 startup message
- finding `BOOT2.BIN` in the FAT12 root directory
- loading the FAT
- following the `BOOT2.BIN` cluster chain
- loading `BOOT2.BIN` into memory at `0050:0000`
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

Boot1 reads the root directory into memory at:

```text
07C0:0200
```

It searches for the 8.3 FAT name:

```text
BOOT2   BIN
```

After finding the directory entry, Boot1 reads the FAT and follows the FAT12
cluster chain. Each cluster is converted to an LBA sector, then to CHS values
for BIOS disk reads.

Boot1 loads Boot2 at:

```text
0050:0000
```

Then it transfers control by pushing the target segment and offset and using
`retf`.

At that point Boot1 is finished.

## Boot2 Role

`Boot2.asm` is the stage 2 boot loader.

Boot2 is larger than Boot1 and is loaded as a normal FAT12 file. Its job is to
do the work that is too large or too awkward for the 512-byte boot sector.

Boot2 is responsible for:

- setting up real-mode segment registers and stack
- installing a Global Descriptor Table
- enabling the A20 line
- loading the FAT12 root directory
- finding `KERNEL.BIN`
- loading `KERNEL.BIN` into low memory
- entering protected mode
- setting 32-bit segment registers
- copying the kernel to 1MB
- jumping to the kernel entry point

Boot2 is assembled with:

```text
org 0500h
```

That matches where Boot1 loaded it:

```text
0050:0000
```

## Boot2 Loading the Kernel

Boot2 searches the FAT12 root directory for:

```text
KERNEL  BIN
```

It loads the root directory to:

```text
RootSegment:RootOffset = 02E0:0000
```

It loads the FAT to:

```text
FatSegment:0000 = 02C0:0000
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
  -> creates floppy.img
  -> formats FAT12
  -> reserves sectors 512-2879
  -> writes Boot1.bin to sector 0

BuildBoot2.ps1
  -> Boot2.asm becomes Boot2.bin

BuildKernel.ps1
  -> Kernel.asm and included modules become Kernel.bin

BuildPrograms.ps1
  -> Prog1/2/3.asm become raw Prog1/2/3.bin

BuildCopy.ps1
  -> copies BOOT2.BIN, KERNEL.BIN, and PROG*.BIN into FAT12
  -> verifies copied files stay below sector 512

BIOS
  -> loads sector 0 to 0000:7C00
  -> jumps to Boot1

Boot1
  -> finds and loads BOOT2.BIN at 0050:0000
  -> jumps to Boot2

Boot2
  -> finds and loads KERNEL.BIN at 00003000h
  -> enters protected mode
  -> copies kernel to 00100000h
  -> jumps to Kernel.asm
```
