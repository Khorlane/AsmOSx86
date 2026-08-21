# Build Scripts

AsmOSx86 build and run helpers live in `Scripts`. The normal workflow assumes the
terminal is already in the `Scripts` folder before running a script.

Most scripts pause before exiting when run interactively. A few lower-level build
scripts accept `noexit` so wrapper scripts can call them without stopping.

## Common Workflows

### Rebuild Kernel and Run

Use this after changing protected-mode kernel code when `Boot.bin`,
`Boot2.bin`, and `floppy.img` are already valid.

```powershell
.\BuildKernelAndRun.ps1
```

This runs:

```text
BuildKernel.ps1 noexit
BuildCopy.ps1
Bochs
```

### Rebuild Boot2, Kernel, and Run

Use this after changing `Boot2.asm` or kernel code when `Boot.bin` and
`floppy.img` are already valid.

```powershell
.\BuildBoot2KernelAndRun.ps1
```

This runs:

```text
BuildBoot2.ps1 noexit
BuildKernel.ps1 noexit
BuildCopy.ps1
Bochs
```

### Run Existing Image

Use this when `floppy.img` has already been prepared and populated.

```powershell
.\AsmOSx86Run.ps1
```

This does not rebuild or copy files. It only launches Bochs with
`AsmOSx86.bxrc`.

### Prepare Floppy From Scratch

Use this after changing `Boot.asm`, after needing a clean floppy image, or after
changing the raw floppy layout.

```powershell
.\BuildBoot.ps1
.\BuildWriteBoot.ps1
.\BuildBoot2.ps1
.\BuildKernel.ps1
.\BuildPrograms.ps1
.\BuildCopy.ps1
.\AsmOSx86Run.ps1
```

`BuildWriteBoot.ps1` recreates `floppy.img`, so anything previously copied into
the image is removed.

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

### BuildBoot.ps1

Assembles the stage 1 boot sector.

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

### BuildBoot2.ps1

Assembles the stage 2 boot loader.

Inputs:

- `Boot2.asm`

Outputs:

- `Boot2.bin`
- `Boot2.lst`

Command:

```text
nasm -f bin Boot2.asm -o Boot2.bin -l Boot2.lst
```

Arguments:

- `noexit`: skip the ending pause for wrapper scripts.
- `exit`: exit after completion for legacy behavior.

### BuildBoot2KernelAndRun.ps1

Wrapper script for rebuilding Boot2 and the kernel, copying files to the floppy,
and launching Bochs.

Runs:

- `BuildBoot2.ps1 noexit`
- `BuildKernel.ps1 noexit`
- `BuildCopy.ps1`
- Bochs

Use this when `Boot2.asm` or kernel code changed, but `Boot.bin` and the
prepared `floppy.img` are already valid.

### BuildCopy.ps1

Writes the AsmOSx86 raw floppy manifest and packed boot/runtime files.

Required inputs:

- `floppy.img`
- `Boot2.bin`
- `Kernel.bin`

Optional inputs:

- `Prog1.bin`
- `Prog2.bin`
- `Prog3.bin`

Writes:

- sector `1`: the `ASMF` manifest
- sector `2+`: `BOOT2.BIN`
- next sectors: `KERNEL.BIN`
- next sectors: `PROG1.BIN`, `PROG2.BIN`, `PROG3.BIN` when present

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

### BuildKernelAndRun.ps1

Wrapper script for rebuilding the kernel, copying files to the floppy, and
launching Bochs.

Runs:

- `BuildKernel.ps1 noexit`
- `BuildCopy.ps1`
- Bochs

Use this for the usual kernel edit/test loop.

### BuildPrograms.ps1

Assembles the current user-program smoke-test binaries.

Inputs:

- `Prog1.asm`
- `Prog2.asm`
- `Prog3.asm`

Outputs:

- `Prog1.bin`
- `Prog1.lst`
- `Prog2.bin`
- `Prog2.lst`
- `Prog3.bin`
- `Prog3.lst`

Commands:

```text
nasm -f bin Prog1.asm -o Prog1.bin -l Prog1.lst
nasm -f bin Prog2.asm -o Prog2.bin -l Prog2.lst
nasm -f bin Prog3.asm -o Prog3.bin -l Prog3.lst
```

Notes:

- User programs are raw flat binaries.
- They are assembled for the fixed virtual base used by the kernel's paging
  setup.
- There is no ASMX wrapping or relocation step in the current build path.

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
