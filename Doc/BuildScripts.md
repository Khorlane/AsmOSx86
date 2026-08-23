# Build Scripts

AsmOSx86 build helpers live in `Scripts`. The normal workflow assumes the
terminal is already in the `Scripts` folder before running a script.

Most scripts pause before exiting when run interactively. A few lower-level build
scripts accept `noexit` so wrapper scripts can call them without stopping.

For the boot-sector layout and boot handoff details, see `Doc/BootProcess.md`.

## BuildBoot.ps1

Assembles the 512-byte boot sector binary from `Boot.asm`.

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
- Accepts `noexit` to skip the ending pause.

## BuildCopy.ps1

Writes the AsmOSx86 boot manifest, kernel image, and raw filesystem area into an
existing `floppy.img`.

Required inputs:

- `floppy.img`
- `Kernel.bin`

Optional inputs:

- `Prog1.bin`
- `Prog2.bin`
- `Prog3.bin`
- `Prog4.bin`
- `Data.txt`
- non-empty `Startup.txt`

Writes:

- sector `1`: the boot manifest sector with the `ASMF` manifest signature
- sector `2+`: contiguous `KERNEL.BIN` sectors
- immediately after `KERNEL.BIN`: filesystem manifest sector
- after the filesystem manifest: packed runtime file bodies
- a reserved, zero-filled `LOG.TXT` file entry

Boot manifest format:

- offset `0`: four-byte `ASMF` manifest signature
- offset `4`: version word, currently `1`
- offset `6`: entry-count word, currently `1`
- offset `8`: filesystem start sector
- offset `12`: filesystem sector count
- offset `16`: first 32-byte file entry

The boot manifest contains the `KERNEL.BIN` entry that `Boot.asm` needs.

Filesystem manifest format:

- offset `0`: four-byte `ASMF` manifest signature
- offset `4`: version word, currently `1`
- offset `6`: entry-count word
- offset `16`: first 32-byte file entry

Each file entry records an uppercase 8.3 name, starting sector, byte size, and
sector count. Runtime files live in the filesystem manifest, not the boot
manifest.

Notes:

- Does not mount the image.
- Does not copy files through FAT12.
- Packs file bodies contiguously and pads each file to a whole sector.
- Supports at most 15 manifest entries in this first version.

## BuildKernel.ps1

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

## BuildKernelAndRun.ps1

Builds the kernel, refreshes the floppy image contents, and launches AsmOSx86 in
Bochs.

Runs:

- `BuildKernel.ps1 noexit`
- `BuildCopy.ps1`
- Bochs through `AsmOSx86Run.ps1` behavior

Use this for the usual kernel edit/test loop when the boot sector and image
already exist.

Notes:

- Does not rebuild `Boot.bin`.
- Does not recreate `floppy.img`.
- Use the from-scratch workflow after changing `Boot.asm` or the raw image
  layout.

## BuildPrograms.ps1

Assembles available `Prog*.asm` user programs into flat binaries.

Inputs:

- `Prog1.asm`, if present
- `Prog2.asm`, if present
- `Prog3.asm`, if present
- `Prog4.asm`, if present

Outputs:

- matching `.bin` files
- matching `.lst` files

Commands:

```text
nasm -f bin Prog1.asm -o Prog1.bin -l Prog1.lst
nasm -f bin Prog2.asm -o Prog2.bin -l Prog2.lst
nasm -f bin Prog3.asm -o Prog3.bin -l Prog3.lst
nasm -f bin Prog4.asm -o Prog4.bin -l Prog4.lst
```

Notes:

- Skips a program if the matching `.asm` file is not present.
- User programs are raw flat binaries consumed by the current loader contract.
- Run `BuildCopy.ps1` afterward to place rebuilt program binaries into
  `floppy.img`.

## BuildWriteBoot.ps1

Creates a fresh raw 1.44MB floppy image, writes `Boot.bin` to sector 0, and
verifies the boot signature.

Inputs:

- `Boot.bin`

Outputs:

- fresh `floppy.img`

Behavior:

- Verifies `Boot.bin` exists and is exactly 512 bytes.
- Deletes and recreates `floppy.img` as a blank 1.44MB image.
- Writes `Boot.bin` to sector 0.
- Verifies the `55 AA` boot signature at bytes 510-511.

Notes:

- Does not format the image.
- Does not mount the image.
- Requires `BuildCopy.ps1` afterward before the image can boot past `Boot.asm`.
