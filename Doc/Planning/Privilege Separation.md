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
kernel calls through int 80h
ring 3 user task entry
```

That is now userland as both an execution model and a first hardware-enforced
ring 3 path.

## Current Code Reality

AsmOSx86 now has an initial hardware-enforced ring 3 user path. It is still
small and cooperative, but user programs no longer run with kernel selectors.

Current implemented groundwork:

```text
Kernel runs in protected mode at 00100000h
Kernel owns GDT and IDT setup
Ring 3 GDT code/data descriptors and selector names exist
TSS descriptor, selector, storage, and TR load exist
TSS ESP0 tracks the selected task's kernel stack top
Paging is enabled
First 16 MiB are identity-mapped
Shared user virtual range begins at 00200000h
User KcBlock virtual page is at 00210000h
Each loaded user task has its own physical program pages
Task switches remap the shared user virtual range to the selected task
Legacy kernel-call gateway address 00100005h is reserved and denied
User programs enter the kernel through int 80h
KcUserDispatch copies arguments/results through the current task's KcBlock
KcDispatch is the kernel-originated path and may receive kernel pointers
KcUserDispatch is the user-originated path and requires service validation
DPL 3 Kc interrupt gate exists at vector 80h for user service calls
Yield, exit, sleep, and keyboard read have interrupt-aware switch paths
KcTsGetInfo returns current task index and user-mode tag
General-protection fault IDT vector 13 is installed
Page-fault IDT vector 14 is installed
General-protection faults and page faults terminate user tasks
Kernel faults still halt forever
Fault handlers classify user faults from the CPU-pushed CS selector
User fault diagnostics print vector, CS, EIP, and CR2 before task exit
Task records have user-mode EIP, ESP, CS, DS, SS, and EFLAGS fields
Loaded user tasks have a prepared iretd frame
TaskEnterUserMode validates its frame and enters ring 3 through iretd
Task records carry a kernel/user execution-mode tag
TaskIsUserMode exposes the execution-mode tag through a helper
Prog4 has denial probes for invalid KcVdWriteStr, KcFsOpen, and KcFsRead pointers
Prog4 has denial probes for zero and unknown Kc call numbers
Prog4 can report its CS selector with the cpl argument
Prog4 can verify KcTsGetInfo with the info argument
Prog4 can trigger a user #GP with the priv argument
Prog4 can trigger a user #PF with the mem argument
Prog4 can verify user KcTsLoadProgram calls are denied with the load argument
Prog4 can manually verify the denied legacy gateway with the legacy argument
Paging permission intent is named separately from current ring-0-safe flags
```

Current important limitations:

```text
The scheduler is still cooperative
There is no preemptive timer interrupt
There is not yet a full process/session model
There is not yet a full user-fault reporting model
The old fixed gateway is quarantined as a denied legacy entry point
The legacy probe is destructive and expected to halt the system
KcTsLoadProgram is kernel-originated only
Only the currently selected user stack page is marked user-accessible
User pointer validation is still intentionally small and service-specific
```

## Paging Permission Intent

Current paging flags:

```text
PG_KERNEL_FLAGS  = present + writable
PG_USER_FLAGS    = present + writable + user-accessible
PG_KCBLOCK_FLAGS = present + writable + user-accessible
```

The older `PG_FUTURE_*` names remain as policy markers for the same active
permission intent:

```text
PG_FUTURE_KERNEL_FLAGS  = present + writable
PG_FUTURE_USER_FLAGS    = present + writable + user-accessible
PG_FUTURE_KCBLOCK_FLAGS = present + writable + user-accessible
```

That means the active policy is:

```text
kernel identity mappings -> supervisor-only
user program mappings    -> user-accessible
user KcBlock mapping     -> user-accessible
kernel stacks/tables      -> supervisor-only
```

The user-access bit has been turned on for loaded program pages and KcBlock
pages. Kernel identity mappings still use supervisor-only flags.

## Fault Policy Intent

Current fault behavior is intentionally simple:

```text
kernel general protection fault -> halt forever
kernel page fault               -> halt forever
user general protection fault   -> terminate current task with 0F0D
user page fault                 -> terminate current task with 0F0E
```

User fault diagnostics currently include:

```text
fault vector
faulting CS
faulting EIP
CR2 linear address for page faults
```

The current ring 3 policy is:

```text
fault from ring 0 -> kernel panic/halt
fault from ring 3 -> terminate current user task and return to scheduler
```

General protection faults matter because they are how the CPU reports many
privilege violations, such as user code attempting privileged instructions or
loading invalid selectors. Page faults matter because they are how the CPU
reports invalid or disallowed memory access.

So the current system has a useful userland execution model, paging-backed
address layout, and initial user/kernel privilege enforcement.

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
Now:
  user programs are constrained by hardware

Later:
  fault handling and process/session policy become richer
```

## Likely Requirements

Fully maturing this later would likely require:

```text
more complete user fault reporting
clearer task/process identity
more denial tests for privileged instructions and invalid memory
validation of every user pointer passed through Kc*
eventual syscall ABI cleanup if the Kc surface grows
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
- Keep adding small userland denial tests as hardware enforcement grows.
- Keep fault handling simple until task/process policy needs more detail.
- Keep boot-stage code separate from protected-mode kernel/userland rules.

This groundwork keeps the current ring 3 path from painting itself into a
corner as the userland surface grows.

## Remaining Work

Privilege separation is now real enough for AsmOSx86 to run loaded user tasks
with ring 3 selectors and enter the kernel through `int 80h`.

The remaining work is about maturing the policy around that mechanism:

- richer user fault reporting
- clearer task/process/session identity
- more denial tests for privileged operations and invalid memory
- broader user-pointer validation as more Kc services are added
- eventual preemptive scheduling when hardware interrupts move up the list
