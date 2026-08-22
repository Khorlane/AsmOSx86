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
Future ring 3 GDT code/data descriptors and selector names exist
Future TSS descriptor, selector, storage, and TR load exist
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
General-protection fault IDT vector 13 is installed
Page-fault IDT vector 14 is installed
General-protection faults and page faults currently halt forever
Task records have future user-mode EIP, ESP, CS, DS, SS, and EFLAGS fields
Prog4 has denial probes for invalid KcVdWriteStr, KcFsOpen, and KcFsRead pointers
Prog4 has denial probes for zero and unknown Kc call numbers
Paging permission intent is named separately from current ring-0-safe flags
```

Current important limitations:

```text
Ring 3 descriptors are scaffolding only and are not used yet
TSS is loaded but only scaffolding until ring transitions exist
No ring transition stack switching
No trap/interrupt gate for user kernel calls
Paging entries are present/writable but not user-accessible
Kernel and user tasks still run with ring 0 segment selectors
Future user-mode task fields are populated but not consumed by the scheduler
User programs are constrained by convention, not by CPU privilege checks
```

## Paging Permission Intent

Current paging flags deliberately preserve existing ring-0 behavior:

```text
PG_KERNEL_FLAGS  = present + writable
PG_USER_FLAGS    = present + writable
PG_KCBLOCK_FLAGS = present + writable
```

The future ring 3 intent is named separately:

```text
PG_FUTURE_KERNEL_FLAGS  = present + writable
PG_FUTURE_USER_FLAGS    = present + writable + user-accessible
PG_FUTURE_KCBLOCK_FLAGS = present + writable + user-accessible
```

That means the intended future policy is:

```text
kernel identity mappings -> supervisor-only
user program mappings    -> user-accessible
user KcBlock mapping     -> user-accessible
kernel stacks/tables      -> supervisor-only
```

This has not been turned on yet. It is scaffolding so the actual ring 3 change
can be audited by comparing each mapping site against its intended access class.

## Fault Policy Intent

Current fault behavior is intentionally simple:

```text
general protection fault -> halt forever
page fault               -> halt forever
```

The future ring 3 policy is:

```text
fault from ring 0 -> kernel panic/halt
fault from ring 3 -> terminate current user task and return to scheduler
```

General protection faults matter because they are how the CPU reports many
privilege violations, such as user code attempting privileged instructions or
loading invalid selectors. Page faults matter because they are how the CPU
reports invalid or disallowed memory access.

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
TSS descriptor and ring 0 stack fields
kernel pages marked supervisor-only
user pages marked user-accessible
a controlled kernel entry path
IDT trap/interrupt gate for Kc calls
TSS setup for ring transition stack switching
fault handlers that distinguish kernel faults from user task faults
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
