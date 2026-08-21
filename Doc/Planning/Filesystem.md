# Filesystem Design Notes

## Purpose

This document captures the future native filesystem direction for AsmOSx86.

It is separate from the current `ASMF` manifest-based floppy layout used to boot
from `floppy.img` and load early user programs. The current manifest support is
intentionally small and practical. This document is about the longer-term native
filesystem model.

The central idea is to keep device-level storage concepts, filesystem allocation
policy, and file-level logical semantics distinct.

## Current Code Reality

AsmOSx86 does not currently use FAT12 for the active boot or file-loading path.

The current disk layout is a raw 1.44MB floppy image:

```text
Sector 0  Boot.bin
Sector 1  ASMF manifest
Sector 2+ packed file bodies
```

The current `BuildCopy.ps1` script writes the manifest and packs file bodies
contiguously after it. The manifest records:

```text
uppercase 8.3 file name
starting sector
file byte size
file sector count
```

The current kernel file path is:

```text
KcFsOpen / KcFsRead / KcFsClose
  -> Kc.asm handlers
  -> FsOpen / FsRead / FsClose
  -> ASMF manifest lookup
  -> DevReadSector
  -> FloppyReadSectorTo
  -> floppy controller / DMA
```

The current file service is read-only and handle-based:

```text
open existing file by name
read bytes from an open file handle
track current file position
detect EOF
close file handle
```

Current limits and simplifications:

```text
files are packed contiguously by the build script
no free-space map
no create/delete/rename
no write path
no directories
no extent table
no per-file BlockSize
no allocation policy in the kernel
floppy A: is the only active block device
```

So the current `ASMF` manifest is not the native filesystem described below. It
is a useful early file table that gives the boot loader, kernel, and user-program
loader a shared way to locate files on the raw floppy image.

## Layer Overview

Conceptually:

```text
Application / User Program
        |
        v
File Layer
        |
        v
Filesystem Allocation Layer
        |
        v
Extent / RBA Layer
        |
        v
Device Sector Layer
        |
        v
Physical or Virtual Storage Device
```

The layers are related, but they should not be collapsed into one concept.

## Layer Responsibilities

### Application Layer

Responsible for:

```text
choosing an appropriate BlockSize when desired
reading and writing logical file data
using files without needing to know their physical RBAs
```

### File Layer

Responsible for:

```text
file name
FileSizeBytes
file metadata
extent ownership
application-visible file semantics
```

### Filesystem Allocation Layer

Responsible for:

```text
per-file BlockSize
free-space allocation
block alignment
file extension policy
extent creation and enlargement
```

### Extent / RBA Layer

Responsible for:

```text
physical disk locations
contiguous sector ranges
StartRBA / EndRBA representation
```

### Device Sector Layer

Responsible for:

```text
logical sector size
sector reads
sector writes
device capacity
```

## Core Storage Model

The filesystem uses 32-bit Relative Block Addresses, or RBAs, to describe
contiguous extents on a device.

RBAs are expressed in units of device sectors. The device sector size is a
filesystem/device property and is not assumed to always be 512 bytes.

Each file has its own `BlockSize`, expressed in bytes.

The filesystem uses `BlockSize` as the file's allocation and growth quantum.

Important core concepts:

```text
SectorSize
RBA
Extent
BlockSize
FileSizeBytes
AllocatedSize
SlackBytes
```

## Device Sector Layer

`SectorSize` is the device's logical sector size in bytes.

Examples:

```text
SectorSize = 512
SectorSize = 4096
```

An RBA identifies one logical sector.

```text
ByteOffset = RBA * SectorSize
```

The sector is the minimum unit understood by the block device interface.

The filesystem may choose to allocate space in units larger than a sector, but
it cannot allocate less than one logical sector.

## RBA Layer

An RBA is expressed in logical sectors, not bytes.

For example, on a 512-byte-sector device:

```text
RBA 1000
```

refers to the sector beginning at:

```text
1000 * 512 = 512000 bytes
```

On a 4096-byte-sector device, the same RBA value refers to a different byte
offset:

```text
1000 * 4096 = 4096000 bytes
```

Therefore:

```text
RBA meaning depends on SectorSize
```

but the filesystem's extent structure itself does not need to change.

## Extent Layer

Each file is represented by one or more contiguous extents.

An extent contains:

```text
StartRBA
EndRBA
```

Both values are 32-bit RBAs.

`EndRBA` is exclusive.

For example:

```text
StartRBA = 1000
EndRBA   = 1016
```

means the file owns:

```text
RBA 1000 through 1015
```

The extent contains:

```text
1016 - 1000 = 16 sectors
```

If:

```text
SectorSize = 512
```

then the extent contains:

```text
16 * 512 = 8192 bytes
```

The extent layer describes where a file's allocated storage physically resides.
It does not define the file's exact logical length.

## Filesystem Allocation Layer

`BlockSize` is a per-file allocation property, expressed in bytes.

It defines the minimum amount of disk space the filesystem allocates when
creating or extending that file.

A valid `BlockSize` must be an integer multiple of `SectorSize`.

```text
BlockSize MOD SectorSize = 0
```

For a device with 512-byte sectors, examples of valid block sizes include:

```text
512
1024
1536
2048
4096
8192
16384
65536
```

A value such as:

```text
BlockSize = 400
```

would be invalid when:

```text
SectorSize = 512
```

The number of sectors in one file allocation block is:

```text
SectorsPerBlock = BlockSize / SectorSize
```

The allocation layer decides how much new space to reserve when a file is
created or extended.

The device still reads and writes sectors. The filesystem chooses to manage
those sectors in larger per-file allocation units.

## Per-File BlockSize Policy

Different files may use different `BlockSize` values.

For example:

```text
SMALL.CFG
    BlockSize = 512

PAYROLL.DAT
    BlockSize = 4096

DATABASE.DAT
    BlockSize = 65536
```

`BlockSize` allows the programmer or application to choose the allocation
behavior appropriate for the expected file size and growth pattern.

A small `BlockSize` reduces wasted space for small files.

A larger `BlockSize` reduces allocation frequency and increases the chance that
a growing file remains in a small number of extents.

The tradeoff is intentional:

```text
Smaller BlockSize
    less wasted space
    potentially more allocation operations
    potentially more extents

Larger BlockSize
    more potential slack space
    fewer allocation operations
    better chance of remaining contiguous
    fewer extents for large growing files
```

Once selected, `BlockSize` becomes part of the file's persistent allocation
policy.

The central design principle is:

```text
Small files can optimize for space.
Large growing files can optimize for contiguity.
```

The filesystem therefore accepts some internal slack space in exchange for fewer
extents, reduced allocation activity, and lower fragmentation for files whose
growth pattern is known in advance.

## Extent Alignment

Extent boundaries must align to the file's `BlockSize`.

First calculate:

```text
SectorsPerBlock = BlockSize / SectorSize
```

Then the extent must satisfy:

```text
StartRBA MOD SectorsPerBlock = 0
EndRBA   MOD SectorsPerBlock = 0
```

For example:

```text
SectorSize      = 512
BlockSize       = 4096
SectorsPerBlock = 8

StartRBA = 1000
EndRBA   = 1016
```

is valid because:

```text
1000 MOD 8 = 0
1016 MOD 8 = 0
```

This keeps the extent layer expressed in sectors while allowing allocation
policy to remain expressed naturally in bytes.

## File Layer

The file layer represents the logical file as seen by an application.

Important file-level properties include:

```text
FileSizeBytes
BlockSize
ExtentCount
Extent[]
```

`FileSizeBytes` stores the exact logical length of the file.

This is separate from the amount of disk space allocated to the file.

Example:

```text
BlockSize     = 4096
FileSizeBytes = 5000
AllocatedSize = 8192
```

The application sees a 5000-byte file.

The filesystem has reserved 8192 bytes.

The final 3192 bytes of the allocated space are unused. This unused portion is
the file's slack space.

## File Directory Entry

Conceptually, a file directory entry contains:

```text
File directory entry
    BlockSize
    FileSizeBytes
    ExtentCount

    Extent[0]
        StartRBA
        EndRBA

    Extent[1]
        StartRBA
        EndRBA

    ...
```

`BlockSize` is stored with the file because different files may use different
allocation sizes.

## AllocatedSize

`AllocatedSize` is the total capacity represented by all extents belonging to
the file.

The following invariants apply:

```text
AllocatedSize >= FileSizeBytes

AllocatedSize MOD BlockSize = 0
```

Slack space can therefore be calculated as:

```text
SlackBytes = AllocatedSize - FileSizeBytes
```

## File Growth and Extension Rule

When a file grows beyond its currently allocated space, the filesystem extends
it in units of the file's `BlockSize`.

For example:

```text
SectorSize = 512
BlockSize  = 4096
```

This means:

```text
SectorsPerBlock = BlockSize / SectorSize
                = 4096 / 512
                = 8 sectors
```

If the file contains:

```text
FileSizeBytes = 5000
```

the filesystem may have:

```text
AllocatedSize = 8192
```

The file occupies two 4096-byte allocation blocks.

When the file grows beyond 8192 bytes, the filesystem allocates another
4096-byte block:

```text
AllocatedSize = 12288
```

The filesystem first attempts to allocate the new block immediately after the
current final extent.

If that space is free:

```text
existing extent is enlarged
```

If the adjacent block is unavailable:

```text
another extent is allocated elsewhere
```

This policy is intended to reduce fragmentation for files that are expected to
grow substantially.

## Allocation Versus Device I/O

A useful distinction is:

```text
SectorSize
    What the device reads and writes.

BlockSize
    What the filesystem allocates for a particular file.
```

For example:

```text
SectorSize = 512
BlockSize  = 4096
```

means:

```text
device transfer/accounting unit = 512-byte sector
filesystem file allocation unit = 4096 bytes
```

One 4096-byte file block therefore contains:

```text
8 device sectors
```

The disk does not know or care that the filesystem considers those eight sectors
to be one file allocation block.

## Allocation Versus File Length

Another important distinction is:

```text
FileSizeBytes
    Exact amount of meaningful file data.

AllocatedSize
    Total amount of disk space reserved for the file.
```

The relationship is:

```text
AllocatedSize >= FileSizeBytes
```

and:

```text
AllocatedSize MOD BlockSize = 0
```

Slack space is:

```text
SlackBytes = AllocatedSize - FileSizeBytes
```

This allows the filesystem to preallocate growth capacity without changing the
logical file length visible to the application.

## Design Principle

The key architectural rule is:

```text
Do not confuse device geometry with filesystem allocation policy.
```

A sector is a device concept.

An RBA identifies a sector.

An extent groups contiguous RBAs.

A `BlockSize` defines how much storage the filesystem allocates to a particular
file at a time.

A file has an exact logical byte length independent of the amount of space
reserved for it.

Conceptually:

```text
Device provides sectors.

Filesystem groups sectors into per-file allocation blocks.

Allocation blocks are represented as contiguous RBA extents.

Files consume the extents but expose only logical byte streams to applications.
```

This layered approach allows the filesystem to support different device sector
sizes, per-file allocation strategies, large contiguous files, and future
changes to storage devices without redesigning the basic file abstraction.

## Terminology Summary

```text
SectorSize
    Device logical sector size in bytes.

RBA
    32-bit Relative Block Address identifying one device sector.

BlockSize
    Per-file allocation and growth quantum in bytes.
    Must be an integer multiple of SectorSize.

SectorsPerBlock
    Number of device sectors in one file allocation block.

FileSizeBytes
    Exact logical size of the file.

AllocatedSize
    Total disk space allocated to the file.

Extent
    One contiguous range of allocated RBAs.

StartRBA
    First sector belonging to an extent.

EndRBA
    Exclusive sector immediately following an extent.

SlackBytes
    AllocatedSize - FileSizeBytes.
```
