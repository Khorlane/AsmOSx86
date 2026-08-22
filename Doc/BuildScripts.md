# Build Scripts

AsmOSx86 build and run helpers live in `Scripts`. The normal workflow assumes the
terminal is already in the `Scripts` folder before running a script.

Most scripts pause before exiting when run interactively. A few lower-level build
scripts accept `noexit` so wrapper scripts can call them without stopping.

For the boot-sector layout and boot handoff details, see `Doc/BootProcess.md`.

## Common Workflows

### Rebuild Kernel and Run

Use this for the usual protected-mode kernel edit/test loop when `Boot.bin` and
`floppy.img` are already valid.

```powershell
.\BuildKernelAndRun.ps1
```

This runs:

```text
BuildKernel.ps1 noexit
BuildCopy.ps1
Bochs
```

### Prepare Floppy From Scratch

Use this after changing `Boot.asm`, after needing a clean floppy image, or after
changing the raw floppy layout.

```powershell
.\BuildBoot.ps1
.\BuildWriteBoot.ps1
.\BuildKernel.ps1
.\BuildPrograms.ps1
.\BuildCopy.ps1
.\AsmOSx86Run.ps1
```

`BuildWriteBoot.ps1` recreates `floppy.img`, so anything previously copied into
the image is removed.

### Run Existing Image

Use this when `floppy.img` has already been prepared and populated.

```powershell
.\AsmOSx86Run.ps1
```

This does not rebuild or copy files. It only launches Bochs with
`AsmOSx86.bxrc`.

## Script Reference

### AsmOSx86Run.ps1

Launches AsmOSx86 in Bochs.

Inputs:

- `AsmOSx86.bxrc`
- `floppy.img`
- Bochs at `C:\Program Files\Bochs-3.0\bochs.exe`

Output:

- Starts Bochs using the current `floppy.img`

Notes:

- Exit code `1` from Bochs is treated as an acceptable user power-off.
- Does not rebuild or copy anything.
- Tolerates non-interactive shells that cannot clear the host terminal or wait
  for a keypress.

### BuildBoot.ps1

Assembles the boot sector.

Inputs:

- `Boot.asm`

Outputs:

- `Boot.bin`
- `Boot.lst`

Command:

```text
nasm -f bin Boot.asm -o Boot.bin -l Boot.lst
```

Notes:

- Deletes old `Boot.bin` and `Boot.lst` before assembling.
- `Boot.bin` must be exactly 512 bytes before `BuildWriteBoot.ps1` can use it.

### BuildWriteBoot.ps1

Creates and prepares `floppy.img` from scratch.

Inputs:

- `Boot.bin`

Outputs:

- fresh `floppy.img`

Behavior:

- Verifies `Boot.bin` exists and is exactly 512 bytes.
- Deletes and recreates `floppy.img` as a blank 1.44MB image.
- Writes `Boot.bin` to sector 0.
- Verifies the `55 AA` boot signature.

Notes:

- Does not format the image as FAT12.
- Does not mount the image.
- `BuildCopy.ps1` must be run after this before the image can boot past Boot.

### BuildKernel.ps1

Assembles the protected-mode kernel.

Inputs:

- `Kernel.asm`
- all assembly modules included by `Kernel.asm`

Outputs:

- `Kernel.bin`
- `Kernel.lst`

Command:

```text
nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst
```

Arguments:

- `noexit`: skip the ending pause for wrapper scripts.
- `exit`: exit after completion for legacy behavior.

### BuildPrograms.ps1

Assembles the current user-program smoke-test binaries.

Inputs:

- `Prog1.asm`
- `Prog2.asm`
- `Prog3.asm`
- `Prog4.asm`, if present

Outputs:

- `Prog1.bin`
- `Prog1.lst`
- `Prog2.bin`
- `Prog2.lst`
- `Prog3.bin`
- `Prog3.lst`
- `Prog4.bin`, if present
- `Prog4.lst`, if present

Commands:

```text
nasm -f bin Prog1.asm -o Prog1.bin -l Prog1.lst
nasm -f bin Prog2.asm -o Prog2.bin -l Prog2.lst
nasm -f bin Prog3.asm -o Prog3.bin -l Prog3.lst
nasm -f bin Prog4.asm -o Prog4.bin -l Prog4.lst
```

Notes:

- User programs are raw flat binaries.
- They are assembled for the fixed virtual base used by the kernel's paging
  setup.
- There is no ASMX wrapping or relocation step in the current build path.

### BuildCopy.ps1

Writes the AsmOSx86 raw floppy manifest and packed kernel/runtime files.

Required inputs:

- `floppy.img`
- `Kernel.bin`

Optional inputs:

- `Prog1.bin`
- `Prog2.bin`
- `Prog3.bin`
- `Prog4.bin`
- `Data.txt`
- `Startup.txt`

Reserved generated files:

- `LOG.TXT`: 128-sector kernel-owned console mirror file, cleared by the kernel
  on startup

Writes:

- sector `1`: the `ASMF` manifest
- sector `2+`: `KERNEL.BIN`
- next sectors: optional `PROG*.BIN`, `DATA.TXT`, and `STARTUP.TXT` files when
  present
- final reserved file entry: `LOG.TXT`

Manifest format:

- offset `0`: four-byte signature `ASMF`
- offset `4`: version word, currently `1`
- offset `6`: entry-count word
- offset `16`: first 32-byte file entry

Each file entry records an uppercase 8.3 name, starting sector, byte size, and
sector count.

Notes:

- Does not mount the image.
- Does not use ImDisk.
- Does not copy files through FAT12.
- Packs file bodies contiguously and pads each file to a whole sector.
- Includes non-empty `Startup.txt` as `STARTUP.TXT`; the console runs this
  command stream after initialization. It is expected to contain ordinary
  console commands, commonly smoke-test commands and optionally `shutdown` for
  automated runs.

### ExtractFile.ps1

Extracts a file from the AsmOSx86 raw `ASMF` floppy image.

Typical use after a Bochs test session:

```powershell
.\ExtractFile.ps1 LOG.TXT
```

The default output location is `Extracted\<NAME>`. `LOG.TXT` extraction trims
trailing zero bytes from the preallocated log area.

### BuildKernelAndRun.ps1

Wrapper script for rebuilding the kernel, copying files to the floppy, and
launching Bochs.

Runs:

- `BuildKernel.ps1 noexit`
- `BuildCopy.ps1`
- Bochs

Use this for the usual kernel edit/test loop.
