# Future

This document collects future-facing design notes for AsmOSx86. The rest of the
`Doc` folder should describe the current operating system. This file is allowed
to describe direction, deferred work, and design ideas that should guide future
implementation.

## Advanced Device Model

AsmOSx86 currently has a deliberately simple storage path:

```text
KcFsOpen / KcFsRead / KcFsClose
  -> Fs.asm
  -> ASMF manifest logic
  -> DevReadSector
  -> floppy sector I/O
  -> floppy controller / DMA
```

That is enough for the current floppy-based user-program loader and smoke
tests, but `Fs.asm` should not permanently mean "raw ASMF files on floppy A:".
The long-term shape separates devices, block access, filesystems, and kernel
calls into clear layers.

Current foundation already present:

```text
shared device IDs and device type IDs
device status values
static device registry
reserved read/write/control slots in device records
default floppy block-device selection
block-device read validation
block-device write validation for kernel-owned log writes
registry-routed block read/write handler calls
read-only file open/read/close kernel services
Fs.asm sections for file service, filesystem driver, block device layer, driver
floppy sector-read and sector-write driver path
```

The current `Config.asm` registry knows about:

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

Future layering should keep this shape:

```text
User/kernel calls
  KcFsOpen
  KcFsRead
  KcFsClose
  later KcFsWrite

Filesystem layer
  current ASMF manifest lookup
  later native AsmOSx86 filesystem

Block device layer
  read sector
  write sector
  get geometry/status

Device drivers
  floppy controller
  later IDE hard disk
```

The important boundary is:

```text
filesystem asks for files/directories
block device asks for sectors
driver talks to hardware
```

`KcFsRead` should not care whether bytes came from floppy, hard disk, RAM disk,
the current ASMF manifest, or a future native filesystem.

Possible future device record:

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

Current status of that shape:

```text
DeviceId             done
DeviceType           done
Status               done
Capabilities         not yet
Open entry point     not yet
Read entry point     done for block devices
Write entry point    done for block devices
Control entry point  slot exists, not used yet
Private driver state not yet
```

Deferred work:

```text
capabilities field
open entry point
active control entry point use
private driver state
hard disk driver
filesystem manager / mounted volumes
native AsmOSx86 filesystem beyond ASMF
user-facing KcFsWrite and broader filesystem services
future KcDevCtl / mount / session services
```

## Filesystem

AsmOSx86 does not currently use FAT12 for the active boot or file-loading path.

The current disk layout is a raw 1.44MB floppy image:

```text
Sector 0  Boot.bin
Sector 1  ASMF manifest
Sector 2+ packed file bodies
```

`BuildCopy.ps1` writes the manifest and packs file bodies contiguously after it.
The manifest records:

```text
uppercase 8.3 file name
starting sector
file byte size
file sector count
```

The image also carries:

```text
STARTUP.TXT   optional startup command stream, sourced from Startup.txt
LOG.TXT       reserved kernel-owned console mirror, cleared on startup
```

Current limits and simplifications:

```text
files are packed contiguously by the build script
no free-space map
no create/delete/rename
no general user-facing write path
no directories
no extent table
no per-file BlockSize
no allocation policy in the kernel
floppy A: is the only active block device
```

The current ASMF manifest is not the native filesystem described below. It is a
useful early file table that gives the boot loader, kernel, and user-program
loader a shared way to locate files on the raw floppy image.

Future native filesystem layering:

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

Layer responsibilities:

```text
Application layer
  choose an appropriate BlockSize when desired
  read and write logical file data
  use files without needing to know physical RBAs

File layer
  file name
  FileSizeBytes
  file metadata
  extent ownership
  application-visible file semantics

Filesystem allocation layer
  per-file BlockSize
  free-space allocation
  block alignment
  file extension policy
  extent creation and enlargement

Extent / RBA layer
  physical disk locations
  contiguous sector ranges
  StartRBA / EndRBA representation

Device sector layer
  logical sector size
  sector reads
  sector writes
  device capacity
```

Core future storage concepts:

```text
SectorSize
RBA
Extent
BlockSize
FileSizeBytes
AllocatedSize
SlackBytes
```

An RBA is a 32-bit Relative Block Address expressed in logical sectors, not
bytes. Its byte offset depends on the device's sector size:

```text
ByteOffset = RBA * SectorSize
```

An extent is a contiguous sector range:

```text
StartRBA = first sector
EndRBA   = exclusive sector after the extent
```

`BlockSize` is a per-file allocation and growth quantum expressed in bytes. It
must be an integer multiple of `SectorSize`:

```text
BlockSize MOD SectorSize = 0
SectorsPerBlock = BlockSize / SectorSize
```

Different files may use different block sizes:

```text
SMALL.CFG     BlockSize = 512
PAYROLL.DAT   BlockSize = 4096
DATABASE.DAT  BlockSize = 65536
```

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

Extent boundaries should align to the file's `BlockSize`:

```text
StartRBA MOD SectorsPerBlock = 0
EndRBA   MOD SectorsPerBlock = 0
```

A future file directory entry may contain:

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
```

`FileSizeBytes` is the exact logical length visible to applications.
`AllocatedSize` is the total disk capacity represented by the file's extents.

```text
AllocatedSize >= FileSizeBytes
AllocatedSize MOD BlockSize = 0
SlackBytes = AllocatedSize - FileSizeBytes
```

The design principle:

```text
Do not confuse device geometry with filesystem allocation policy.

Device provides sectors.
Filesystem groups sectors into per-file allocation blocks.
Allocation blocks are represented as contiguous RBA extents.
Files consume the extents but expose only logical byte streams to applications.
```

## Scheduler

AsmOSx86 currently has cooperative scheduling.

User programs voluntarily enter the kernel through scheduling points such as:

```text
KcTsYield
KcTsExit
KcTmSleep
KcKbRead
```

Implemented scheduler foundation:

```text
task table with up to 8 task records
task states: Free, Ready, Running, Blocked, Exited
saved ESP per task
low-memory stack-slot assignment
file-backed raw user-program loading
per-task physical program allocation above the kernel
fixed user virtual base at 00200000h
per-task KcBlock page at 00210000h
round-robin scan for the next Ready task
cooperative sleep blocking and wake checks
keyboard-read blocking until one key event is available
interrupt-aware switch paths for user yield/exit/sleep/key services
```

The current scheduler is cooperative, not preemptive. It does not yet have:

```text
timer interrupt scheduling
preemptive task interruption
runtime budget accounting
runaway-task enforcement
interrupt-safe scheduler state
general wait queues for filesystem/device I/O
```

Cooperative scheduling:

```text
task runs until it calls KcTsYield, KcTsExit, or a blocking Kc* service
```

Preemptive scheduling:

```text
timer interrupt can stop the task even if it did not yield
kernel saves the interrupted task state
kernel chooses another ready task
kernel resumes that other task
```

Full preemption brings complexity:

```text
timer IRQ setup
interrupt handlers
interrupt-safe kernel state
saved interrupted CPU state
critical sections
reentrancy problems
kernel code that can be interrupted mid-update
harder debugging
```

Recommended path:

```text
1. Keep cooperative scheduling as the normal model.
2. Add more blocking scheduling points.
3. Add timer interrupts for tick/event collection.
4. Add timer-based runaway-task detection.
5. Consider true transparent preemption only if it becomes clearly useful.
```

A useful intermediate model is a timer interrupt as watchdog, not necessarily as
a full preemptive scheduler:

```text
task starts or resumes
kernel gives it a CPU budget
timer interrupt tracks elapsed runtime
task is expected to enter the kernel through a scheduling point
if the task exceeds its budget first, it is considered runaway
kernel kills or stops the task
```

Classification:

```text
timer-based runaway detection = likely desirable later
preemptive scheduler          = optional, maybe not planned
```

## Privilege Policy

The active privilege-separation and privilege-policy foundation milestone is
complete. Future privilege work should be driven by new real services.

Current completed foundation:

```text
kernel runs in ring 0
loaded user programs run in ring 3
user programs enter kernel services through int 80h
kernel identity mappings are supervisor-only
user program pages and KcBlock pages are user-accessible
user #GP terminates the task with 0F0D
user #PF terminates the task with 0F0E
KcTsLoadProgram is kernel-originated only
tasks carry a TASK_AUTH_* authority value
Run can launch trusted/system ring 3 test tasks through launch prefixes
KcTable carries each service's minimum authority
KcAuthorize rejects user calls that do not meet that authority
KcMmGetMemory and KcMmFreeMemory are real trusted-only page services
KcMmInfo is a normal-user memory introspection service
legacy gateway address 00100005h is denied
STARTUP.TXT exercises privilege smoke tests through ordinary console commands
```

Current authority levels:

```text
normal user task
  ordinary application/user program
  limited Kc service access

trusted user task
  still ring 3
  allowed to use selected privileged Kc services
  similar in spirit to an APF-authorized program

system user task
  still not kernel code
  started by startup policy
  allowed to manage sessions, devices, or services through approved Kc calls
```

Completed startup-driven validation probes:

```text
normal GetMemory denied
trusted GetMemory allowed and returned memory is writable
system GetMemory allowed and returned memory is writable
normal MmInfo allowed and returns mapped/max user memory
trusted GetMemory changes mapped memory reported by MmInfo
trusted GetMemory refuses to grow beyond the user memory limit
normal FreeMemory denied
trusted FreeMemory allowed after allocating a block
system FreeMemory allowed after allocating a block
trusted FreeMemory with a bad pointer returns BAD_ARG
trusted FreeMemory enforces stack-like release order
```

Future privilege work:

```text
full process/session ownership model
per-task service permission masks
rich user fault reporting
user identity or sign-on integration
preemptive watchdog enforcement
future KcDevCtl / KcMount / KcSession / KcShutdown policies
```

The current ring 3 enforcement and Kc authority foundation should remain small
and stable while the policy model grows only when real services need it.

## Asm32x86 Bootstrap

The long-term goal is to remove NASM from the trusted build path by making
Asm32x86 capable of assembling itself and eventually assembling AsmOSx86.

NASM is the initial seed assembler. Once Asm32x86 can assemble enough of its own
source and the operating system source, NASM should no longer be required.

Intended bootstrap path:

```text
1. NASM builds the first working Asm32x86.
2. Asm32x86 assembles its own source.
3. Asm32x86 runs under Windows first, using a clean host I/O layer.
4. Asm32x86 later runs under AsmOSx86, using AsmOSx86 kernel calls.
5. AsmOSx86 uses Asm32x86 to rebuild Asm32x86 and the OS.
6. NASM is no longer required.
```

Detailed stages:

```text
1. Define the first Asm32x86 language subset.
2. Write Asm32x86 in x86 assembly and build it with NASM.
3. Run Asm32x86 as a Windows console program.
4. Use Asm32x86 to assemble small test programs.
5. Use Asm32x86 to assemble its own source.
6. Keep Windows file I/O isolated behind replaceable host routines.
7. Replace the Windows host routines with AsmOSx86 kernel-call routines.
8. Run Asm32x86 as an AsmOSx86 userland program.
9. Use Asm32x86 under AsmOSx86 to rebuild Asm32x86.
10. Use Asm32x86 under AsmOSx86 to rebuild AsmOSx86.
```

The first host boundary can stay small:

```text
HostOpen
HostRead
HostWrite
HostClose
HostExit
```

Possible future mapping:

```text
HostOpen  -> KcFsOpen
HostRead  -> KcFsRead
HostWrite -> future KcFsWrite
HostClose -> KcFsClose
HostExit  -> KcTsExit
```

Bochs remains the normal AsmOSx86 test environment throughout the transition.
Early Asm32x86 work can happen on Windows while AsmOSx86 continues to boot and
run in Bochs. Build scripts can copy generated userland programs and tools into
the raw ASMF floppy image for AsmOSx86 testing.

When updating the floppy image, Bochs should be closed first so the image file
is not locked.
