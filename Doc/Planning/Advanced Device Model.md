# Advanced Device Model

## Context

AsmOSx86 currently has a deliberately simple storage path:

```text
KcFsOpen / KcFsRead / KcFsClose
  -> Fs.asm
  -> FAT12 logic
  -> floppy block reads
  -> floppy controller / DMA
```

That is enough for the current floppy-based user-program loader and smoke tests.

Longer term, `Fs.asm` should not permanently mean "FAT12 on floppy A:". A real
OS shape separates devices, block access, filesystems, and kernel calls into
clear layers.

## Future Layering

Conceptually:

```text
User/kernel calls
  KcFsOpen
  KcFsRead
  KcFsClose
  later KcFsWrite

Filesystem layer
  FAT12
  later FAT16
  maybe native AsmOSx86 filesystem

Block device layer
  read sector
  write sector
  get geometry/status

Device drivers
  floppy controller
  later IDE hard disk
```

The important boundary is that each layer asks for the right kind of thing:

```text
filesystem asks for files/directories
block device asks for sectors
driver talks to hardware
```

## Why This Matters

`KcFsRead` should not care whether bytes came from:

- floppy
- hard disk
- RAM disk
- FAT12
- FAT16
- a future native AsmOSx86 filesystem

The kernel call asks the filesystem layer. The filesystem layer asks the block
device layer. The block device layer asks the actual hardware driver.

## Example: Floppy FAT12

```text
KcFsOpen("A:\PROG1.BIN")
  -> filesystem manager sees drive A:
  -> drive A is mounted as FAT12
  -> FAT12 opens PROG1.BIN
  -> FAT12 reads directory/FAT data through block device 0
  -> block device 0 is backed by floppy driver
```

## Example: Future Hard Disk FAT16

```text
KcFsOpen("C:\SYSTEM\MENU.BIN")
  -> filesystem manager sees drive C:
  -> drive C is mounted as FAT16
  -> FAT16 opens MENU.BIN
  -> FAT16 reads sectors through block device 1
  -> block device 1 is backed by IDE driver
```

## Possible Device Record

A future kernel device table might eventually describe devices with records like:

```text
DeviceId
DeviceType
Status
Capabilities
Open entry point
Read entry point
Write entry point
Control entry point
Private driver state
```

This does not need to be fancy plug-and-play. At first, it can simply be a small
static registry of devices the kernel knows how to talk to.

## Deferred Work

This belongs in deferred work, not "not planned".

Unlike ELF loading or dynamic linking, device/filesystem layering sounds like a
natural part of AsmOSx86 growing into a real OS. The goal is not complexity for
its own sake. The goal is to avoid baking "FAT12 floppy only" into every future
file service.
