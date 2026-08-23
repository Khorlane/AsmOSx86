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

### BuildCopy.ps1

Writes the AsmOSx86 raw floppy manifest and the protected-mode kernel image.

Required inputs:

- `floppy.img`
- `Kernel.bin`

Writes:

- sector `1`: the `ASMF` manifest
- sector `2+`: `KERNEL.BIN`

Manifest format:

- offset `0`: four-byte signature `ASMF`
- offset `4`: version word, currently `1`
- offset `6`: entry-count word
- offset `16`: first 32-byte file entry

Each file entry records an uppercase 8.3 name, starting sector, byte size, and
sector count.

Notes:

- Does not mount the image.
- Does not copy files through FAT12.
- Packs file bodies contiguously and pads each file to a whole sector.

### BuildKernelAndRun.ps1

Wrapper script for rebuilding the kernel, copying files to the floppy, and
launching Bochs.

Runs:

- `BuildKernel.ps1 noexit`
- `BuildCopy.ps1`
- Bochs

Use this for the usual kernel edit/test loop.
