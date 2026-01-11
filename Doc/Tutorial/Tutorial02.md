---
◀️ [Tutorial01](Tutorial01)  [🏠 Tutorial](Tutorial)  [Tutorial03 ▶️](Tutorial03)

---

# Boot1 - The Code

## Introduction
Now we will examine the boot sector code, Stage 1. Remember that the _sole_ purpose of Stage 1 is to load `Boot2.bin`(Stage 2), which in turn loads our kernel. We will not be reviewing the code line by line but attempt to give a good idea of what the various code blocks are trying to accomplish.

The code in Boot1 and Boot2 relies heavily on BIOS Interrupts, the primary one being INT 13h - disk read.

## Booter
The first thing the code doses is a jump to `Booter` which does some initialization, displays a message, loads the root directory table, and tries to find our Stage2Name which is Boot2.bin via the `FindFat` loop. This loop exits when the file is found via this instruction: `je    LoadFat`. The LoadFat code block gathers information needed to read Boot2.bin into memory and falls through to the Load Stage 2 section.

We set the memory address for our Stage 2 code and fall into `LoadStage2` where we actually start loading Boot2.bin into memory sector by sector. The load loop ends when `jb    LoadStage2` falls through to the next instruction (instead of looping back to `LoadStage2`). This fall through occurs when EOF on Boot2.bin is reached.

Now that Boot2.bin is in memory, we print a message, wait for a keypress, and jump to our Stage 2 code. Here's the somewhat strange code that gets us to Stage 2.
```
    push  word 0x0050                   ; Jump to our Stage 2 code that we put at 0050:0000
    push  word 0x0000                   ;   by using a Far Return which pops IP(0h) then CS(50h)
    retf                                ;   and poof, we're executing our Stage 2 code!
```

## Stage 2
Stage 2 will load our kernel, but before we jump into Stage 2, let's actually see Stage 1 working. The next section will walk you through the steps to get Stage 1 fired up using the Bochs emulator. You will be rewarded with two messages: **AsmOSx86 v0.0.1 Stage 1** and **MISSING BOOT2.BIN**. 🎉🎉🎉

---
◀️ [Tutorial01](Tutorial01)  [🏠 Tutorial](Tutorial)  [Tutorial03 ▶️](Tutorial03)

---