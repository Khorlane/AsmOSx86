# Advanced Device Model

## Context

AsmOSx86 currently has a deliberately simple storage path:

```text
KcFsOpen / KcFsRead / KcFsClose
  -> Fs.asm
  -> ASMFS manifest logic
  -> floppy block reads
  -> floppy controller / DMA
```

That is enough for the current floppy-based user-program loader and smoke tests.

Longer term, `Fs.asm` should not permanently mean "FAT12 on floppy A:". A real
OS shape separates devices, block access, filesystems, and kernel calls into
clear layers.

## Current Code Reality

Some of the planned shape now exists in the real code.

`Config.asm` defines shared device identity and registry records:

```text
DEV_TYPE_BLOCK
DEV_TYPE_CHAR
DEV_TYPE_VIDEO

DEV_STATUS_OK
DEV_STATUS_BAD_DEVICE
DEV_STATUS_IO_ERROR
DEV_STATUS_NOT_PRESENT

DEV_ID_VIDEO_TEXT
DEV_ID_KEYBOARD
DEV_ID_FLOPPY_A
DEV_ID_HARDDISK_0
```

It also defines a small static `DevRegistry` with entries for:

```text
video text
keyboard
floppy A:
hard disk 0, currently marked not present
```

Each registry record currently has:

```text
DeviceId
DeviceType
Status
SectorSize
SectorCount
Read entry point slot
Write entry point slot
Control entry point slot
```

The entry point slots exist in the record layout, but they are not actively used
yet. The current block-device path still routes directly through known code.

`Fs.asm` is already organized into rough layers:

```text
Kernel calls
File service
Filesystem driver
Block device layer
Device driver
```

Current implemented path:

```text
KcFsOpen / KcFsRead / KcFsClose
  -> Kc.asm handlers
  -> FsOpen / FsRead / FsClose
  -> ASMFS manifest lookup
  -> DevReadSector
  -> FloppyReadSectorTo
  -> floppy controller / DMA
```

The current file service is read-only and handle-based. It can open files by
name, read bytes from an open handle, track file position, detect EOF, and close
handles.

The current filesystem driver is the simple `ASMF` manifest format. It reads
sector 1, validates the manifest signature, converts filenames to uppercase 8.3
form, and finds file entries.

The current block-device layer is intentionally tiny. It has a default block
device of `DEV_ID_FLOPPY_A`, validates the selected registry record as a present
block device, checks the sector number against the device's sector count, and
then calls the floppy driver.

The current floppy driver can initialize the controller and read 512-byte
sectors through the floppy controller and DMA bounce buffer.

## Done Enough For Now

These parts of the advanced-device direction are already established enough to
count as foundation:

- shared device IDs and device type IDs
- device status values
- static device registry shape
- reserved read/write/control slots in device records
- default floppy block-device selection
- block-device read validation path
- read-only file open/read/close kernel services
- separation inside `Fs.asm` between file service, filesystem driver,
  block-device layer, and device driver
- floppy sector-read driver path

The model is still static and direct, but the boundaries are visible in code.

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

Current status:

```text
DeviceId             done
DeviceType           done
Status               done
Capabilities         not yet
Open entry point     not yet
Read entry point     slot exists, not used yet
Write entry point    slot exists, not used yet
Control entry point  slot exists, not used yet
Private driver state not yet
```

## Deferred Work

This belongs in deferred work, not "not planned".

Unlike ELF loading or dynamic linking, device/filesystem layering sounds like a
natural part of AsmOSx86 growing into a real OS. The goal is not complexity for
its own sake. The goal is to avoid baking "FAT12 floppy only" into every future
file service.
