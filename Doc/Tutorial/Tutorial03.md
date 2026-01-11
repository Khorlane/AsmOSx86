---
◀️ [Tutorial02](Tutorial02)  [🏠 Tutorial](Tutorial)  [Tutorial04 ▶️](Tutorial04)

---

# Bootloader Stage 1
In the previous tutorial, we used Boot1.asm to create Boot1.bin which is our Stage 1 bootloader. In this tutorial, we will walk through the steps required to actually see our Stage 1 bootloader in action. There are a number of steps involved that might seem somewhat disjointed, so we'll break it down into byte size chunks. We'll be using the Bochs emulator to pretend that we have an i386 architecture machine with a floppy drive as our boot device. The chunks are:
* Prepare a floppy disk
* Write the boot sector
* Fire it up!

# Prepare Floppy
## Create Floppy Image
Create a floppy image by executing this command which will create the equivalent of a 1.44 MB floppy disk.
```
fsutil file createnew floppy.img 1474560
```
One last time, you will not be told every move to make, everything will not be explained. In this case, it is assumed you either know what a command window is and how to use it _**or**_ you will use ChatGPT/Google to figure it out. If you don't know what a **floppy** is, go figure it out and then come back here.

Now you have an imaginary floppy disk with nothing on it. It is not even formatted.

## Format Floppy

---
◀️ [Tutorial02](Tutorial02)  [🏠 Tutorial](Tutorial)  [Tutorial04 ▶️](Tutorial04)

---