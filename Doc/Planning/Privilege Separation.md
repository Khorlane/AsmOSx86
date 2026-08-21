# Privilege Separation

## Meaning

For AsmOSx86, user/kernel privilege separation means the CPU and kernel enforce
that user programs cannot freely touch kernel memory, hardware, or privileged
CPU state.

Today, AsmOSx86 has an early userland model:

```text
raw user program binaries
loaded from the ASMF manifest filesystem
mapped at a fixed virtual base
cooperative task switching
kernel calls by convention
```

That is userland as an execution model, but not yet hardware-enforced user mode.

## Current Code Reality

AsmOSx86 has useful groundwork, but it does not yet have hardware-enforced
privilege separation.

Current implemented groundwork:

```text
Kernel runs in protected mode at 00100000h
Kernel owns GDT and IDT setup
Paging is enabled
First 16 MiB are identity-mapped
Shared user virtual range begins at 00200000h
User KcBlock virtual page is at 00210000h
Each loaded user task has its own physical program pages
Task switches remap the shared user virtual range to the selected task
Kernel-call gateway exists at 00100005h
KcUserDispatch copies arguments/results through the current task's KcBlock
KcDispatch is the kernel-originated path and may receive kernel pointers
KcUserDispatch is the user-originated path and requires service validation
Page-fault IDT vector 14 is installed
Page faults currently halt forever
Prog4 has denial probes for invalid KcVdWriteStr, KcFsOpen, and KcFsRead pointers
```

Current important limitations:

```text
No ring 3 code/data descriptors
No TSS
No ring transition stack switching
No trap/interrupt gate for user kernel calls
No general-protection fault handler
Paging entries are present/writable but not user-accessible
Kernel and user tasks still run with ring 0 segment selectors
User programs are constrained by convention, not by CPU privilege checks
```

So the current system has a useful userland execution model and paging-backed
address layout, but not actual user/kernel privilege enforcement yet.

Future privilege separation would mean:

```text
Kernel:
  runs in ring 0
  owns hardware ports, page tables, scheduler, filesystems, and devices
  owns supervisor-only kernel memory

User programs:
  run in ring 3
  cannot execute privileged instructions
  cannot access kernel-only memory pages
  cannot directly access I/O ports
  must request services through Kc*
```

## Ring 3 Enforcement

`user/kernel privilege separation` is the design goal.

`ring 3 enforcement` is the x86 mechanism for enforcing that goal.

Conceptually:

```text
user/kernel privilege separation = OS design boundary
ring 3 enforcement               = x86 hardware support for that boundary
```

So these should not be treated as two unrelated future features. In AsmOSx86
documentation they can usually be folded together as:

```text
user/kernel privilege separation through ring 3
```

## What Ring 3 Would Prevent

If a user program tried to do this:

```asm
out  03F2h,al
mov  [00100000h],eax
cli
lgdt [Something]
```

the CPU should reject it with a protection fault rather than allowing the
program to affect hardware, kernel memory, interrupt state, or descriptor
tables.

The long-term distinction is:

```text
Today:
  user programs cooperate by convention

Later:
  user programs are constrained by hardware
```

## Likely Requirements

Fully implementing this later would likely require:

```text
GDT entries for ring 3 user code and data
kernel pages marked supervisor-only
user pages marked user-accessible
a controlled kernel entry path
IDT trap/interrupt gate for Kc calls
TSS setup for ring transition stack switching
fault handlers for page faults and general-protection faults
task state that records user-mode CS/DS/SS/ESP/EIP
validation of user pointers passed through Kc*
denial tests that prove invalid user pointers are rejected before use
```

## Foundational Groundwork

The best way to make future privilege separation easier is to keep today's
interfaces honest.

Recommended groundwork:

- Keep user programs using `Kc*` services instead of calling kernel routines
  directly.
- Keep the kernel-call contract memory-backed and explicit.
- Keep user program virtual addresses separate from kernel addresses.
- Keep paging central to the user-program loader.
- Keep task records responsible for user program image, stack, KcBlock, and
  saved execution state.
- Keep hardware access inside kernel-owned drivers.
- Keep filesystem access behind `KcFs*` and filesystem/block-device layers.
- Avoid teaching user programs to depend on kernel globals or kernel labels.
- Keep adding small userland denial tests before turning on hardware enforcement.
- Start adding fault handlers before relying on faults for enforcement.
- Keep boot-stage code separate from protected-mode kernel/userland rules.

This groundwork does not require implementing ring 3 immediately. It simply
keeps the current design from painting itself into a corner.

## Deferred Work

Privilege separation is real OS work and belongs in deferred work.

It is not needed before the cooperative user-program model, paging-based virtual
layout, kernel calls, and task switching are stable. Once those pieces are
solid, ring 3 enforcement becomes a natural next hardening step rather than a
rewrite.
