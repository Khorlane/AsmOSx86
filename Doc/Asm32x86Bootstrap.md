# Asm32x86 Bootstrap Roadmap

## Goal

The long-term goal is to remove NASM from the trusted build path by making
Asm32x86 capable of assembling itself and eventually assembling AsmOSx86.

NASM is the initial seed assembler. Once Asm32x86 can assemble enough of its
own source and the operating system source, NASM should no longer be required.

## Big Picture

The intended bootstrap path is:

1. NASM builds the first working Asm32x86.
2. Asm32x86 assembles its own source.
3. Asm32x86 runs under Windows first, using a clean host I/O layer.
4. Asm32x86 later runs under AsmOSx86, using AsmOSx86 kernel calls.
5. AsmOSx86 uses Asm32x86 to rebuild Asm32x86 and the OS.
6. NASM is no longer required.

## Stages

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

## Host I/O Boundary

Asm32x86 should keep operating-system-specific services in a small, separate
part of the module. The assembler core should not directly know whether it is
running on Windows or AsmOSx86.

The first host boundary can stay small:

- HostOpen
- HostRead
- HostWrite
- HostClose
- HostExit

The Windows version can implement these routines with Windows system calls.
The later AsmOSx86 version can implement the same routines with kernel calls.

Possible future mapping:

- HostOpen -> KcFsOpen
- HostRead -> KcFsRead
- HostWrite -> future KcFsWrite
- HostClose -> KcFsClose
- HostExit -> KcTsExit

## Bochs Role

Bochs remains the normal AsmOSx86 test environment throughout the transition.

Early Asm32x86 work can happen on Windows while AsmOSx86 continues to boot and
run in Bochs. Build scripts can copy generated userland programs and tools into
the FAT12 floppy image for AsmOSx86 testing.

As the OS grows, Bochs can be used to prove:

- ASMX executable loading
- FAT12 file reading
- kernel-call behavior
- userland task execution
- Asm32x86 running as an AsmOSx86 userland program
- later self-hosting steps

When updating the floppy image, Bochs should be closed first so the image file
is not locked.

