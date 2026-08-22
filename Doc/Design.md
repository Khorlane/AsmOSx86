# AsmOSx86 High-Level Design and Concept Document

## 1. Purpose

AsmOSx86 is a hobbyist 32-bit x86 operating system written in NASM assembly. Its purpose is educational and architectural: to build a small protected-mode operating system with clear subsystem boundaries, explicit contracts, and a simple path toward multitasking, user programs, and a controlled user/kernel interface.

The project currently emphasizes clarity over cleverness. The code is intentionally direct, heavily commented, and organized around small routines with explicit memory-backed inputs and outputs.

AsmOSx86 is not intended to clone any existing operating system. Some concepts may resemble traditional mainframe, microkernel, or classic protected-mode operating system patterns, but the project uses those only as conceptual reference points. The design should stand on its own.

---

## 2. Current Kernel Identity

The current AsmOSx86 kernel is a flat 32-bit protected-mode binary loaded at physical address `00100000h`.

The kernel is resident. Once loaded, it remains fixed in memory and acts as the control program for the rest of the system.

Current major included kernel components are:

```text
Config.asm
Console.asm
Fs.asm
Keyboard.asm
Kc.asm
Paging.asm
Task.asm
Time.asm
Timer.asm
Uptime.asm
Utility.asm
Video.asm
```

The current kernel provides:

- protected-mode entry at `Stage3`
- GDT and IDT setup
- PIT-based monotonic timer support
- RTC-based wall-clock time support
- uptime reporting
- VGA text-mode output
- keyboard polling
- command-line console
- optional `STARTUP.TXT` console startup command stream
- initial memory-backed Kernel Call dispatcher
- initial tested Kernel Calls:
  - `KcTmGetUptime`
  - `KcVdWriteStr`
  - `KcTsYield`
  - `KcTsLoadProgram`
  - `KcTsExit`
  - `KcFsOpen`
  - `KcFsRead`
  - `KcFsClose`
  - `KcTmSleep`
  - `KcKbRead`
  - `KcTsGetInfo`
  - `KcTsGetAuthority`
  - `KcMmGetMemory`
  - `KcMmFreeMemory`
- simple built-in commands:
  - `Clear`
  - `Date`
  - `Delay`
  - `FsTest`
  - `Help`
  - `KcTest`
  - `Run`
  - `Shutdown`
  - `Time`
  - `Uptime`

At this stage, AsmOSx86 is still a single resident kernel with an integrated console. Early userland exists as raw flat binaries loaded from the raw `ASMF` floppy manifest and run as cooperative tasks through the kernel's task service path.

---

## 3. Fundamental ABI Rule

AsmOSx86 uses a memory-contract ABI.

This is a deliberate project rule.

Registers are scratch only. Calls destroy all registers. No routine may depend on a register preserving a value across a `call`.

Routine contracts should be expressed through named memory variables, not through public register parameters or register return values.

The standard routine shape is:

```asm
RoutineName:
  ; Read input parameters from named globals.
  ; Use registers as local scratch.
  ; Perform the work.
  ; Store results into named globals.
  ret
```

Examples of acceptable public contracts:

```asm
TimerDelayMs    dd 0
TimerOutTicksLo dd 0
TimerOutTicksHi dd 0
pVdStr          dd 0
KbOutHasKey     db 0
```

Examples of public contracts to avoid:

```asm
EAX = input
EDX:EAX = return value
EDI = output pointer
```

This rule applies to kernel routines and to user/kernel interfaces.

### Why this matters

This rule simplifies reasoning in assembly. It makes every routine boundary explicit and prevents accidental dependencies on transient register state.

It also fits the kernel-call model: user programs request services by filling a
memory-backed parameter block, not by relying on arbitrary live registers.

---

## 4. Current Boot and Kernel Placement Model

The current boot process is documented in `Doc/BootProcess.md`.

At a high level:

```text
Boot.asm  -> boot sector
Kernel.asm -> protected-mode kernel at 00100000h
```

The kernel lives at:

```text
KernelBase = 00100000h
```

This is the preferred long-term kernel base.

Conceptual memory layout:

```text
00100000h - KernelEnd   resident AsmOSx86 kernel
UserBase   - UserLimit  future user memory region or user memory pool
```

The kernel remains fixed in memory. User programs should live above the kernel in a controlled user memory region.

Low-memory quick reference:

```text
00000000h - 000004FFh   IVT/BDA / legacy low memory
00000500h - 00000FFFh   low-memory reserved fragment
00001000h - 0008FFFFh   low-memory stack-slot arena, 143 slots of 4K
00090000h - 0009FFFFh   upper conventional memory, reserved for future explicit use
000A0000h - 000FFFFFh   classic PC reserved/video/ROM region
00100000h - KernelEnd   resident AsmOSx86 kernel
```

Low-memory map:

```text
higher addresses
+-------------------------------------------------+
| KernelEnd                                       |
|                                                 |
|   Resident kernel image                         |
|   size: KernelEnd - 00100000h                   |
|                                                 |
|   Kernel.asm loaded here                        |
|   protected-mode resident kernel                |
|                                                 |
| 00100000h                                       |
+-------------------------------------------------+
| 000FFFFFh                                       |
|                                                 |
|   System BIOS ROM area                          |
|   size: 00010000h bytes = 65,536 bytes = 64K    |
|                                                 |
| 000F0000h                                       |
+-------------------------------------------------+
| 000EFFFFh                                       |
|                                                 |
|   Adapter ROM / option ROM area                 |
|   size: 00030000h bytes = 196,608 bytes = 192K  |
|                                                 |
| 000C0000h                                       |
+-------------------------------------------------+
| 000BFFFFh                                       |
|                                                 |
|   Color VGA text memory area                    |
|   size: 00008000h bytes = 32,768 bytes = 32K    |
|                                                 |
|   actual 80x25 text page 0 uses:                |
|   80 * 25 * 2 = 4,000 bytes                     |
|                                                 |
| 000B8000h                                       |
+-------------------------------------------------+
| 000B7FFFh                                       |
|                                                 |
|   Video memory / graphics aperture area         |
|   size: 00018000h bytes = 98,304 bytes = 96K    |
|                                                 |
| 000A0000h                                       |
+-------------------------------------------------+
| 0009FFFFh                                       |
|                                                 |
|   Upper conventional memory                     |
|   size: 00010000h bytes = 65,536 bytes = 64K    |
|                                                 |
|   reserved for future explicit use              |
|                                                 |
| 00090000h                                       |
+-------------------------------------------------+
| 00090000h                                       |
|                                                 |
|   Stack-slot arena exclusive top                |
|   size: 0 bytes                                 |
|                                                 |
+-------------------------------------------------+
| 0008FFFFh                                       |
|                                                 |
|   Low-memory stack-slot arena                   |
|   size: 0008F000h bytes = 585,728 bytes = 572K  |
|                                                 |
|   slot size: 00001000h bytes = 4K               |
|   slot count: 143                               |
|                                                 |
|   slot 0: kernel stack                          |
|   slot 1: task 1 stack                          |
|   slot 2: task 2 stack                          |
|   ...                                           |
|                                                 |
|   StackSlotTop(n)    = 00090000h - n*00001000h  |
|   StackSlotBottom(n) = StackSlotTop(n)-00001000h|
|   InitialESP(n)      = StackSlotTop(n)          |
|                                                 |
| 00001000h                                       |
+-------------------------------------------------+
| 00000FFFh                                       |
|                                                 |
|   Low-memory reserved fragment                  |
|   size: 00000B00h bytes = 2,816 bytes           |
|                                                 |
|   left out of the aligned 4K stack-slot arena   |
|                                                 |
| 00000500h                                       |
+-------------------------------------------------+
| 000004FFh                                       |
|                                                 |
|   IVT / BDA / legacy reserved low memory        |
|   size: 00000500h bytes = 1,280 bytes           |
|                                                 |
| 00000000h                                       |
+-------------------------------------------------+
```

---

## 5. Build and Run Workflow

AsmOSx86 builds as flat binary components and runs from a 1.44 MB floppy image named `floppy.img`.

The build scripts live in `Scripts\`. The expected interactive workflow is to
change into that folder before running them.

### Tool Roles

```text
NASM      assembles flat binary files
fsutil    creates the 1.44 MB floppy image
BuildCopy writes the raw ASMF manifest and packed file data
Bochs     runs the bootable floppy image
```

`BuildCopy.ps1` includes non-empty `Startup.txt` as `STARTUP.TXT`. After
console initialization, the kernel runs that command stream before entering the
interactive console loop.

Detailed script usage lives in `BuildScripts.md`.

The floppy preparation and boot flow from BIOS handoff through `Boot.asm` and
the protected-mode kernel live in `BootProcess.md`.

---

## 6. Kernel Residency Principle

The kernel is resident and permanent.

User programs may be loaded, stopped, or replaced, but the kernel remains in
place. Future nonresident task support may add swapping or backing-store policy.

Design principle:

```text
Kernel is fixed.
Userland is replaceable.
```

The kernel owns:

- hardware access
- task management
- memory assignment
- kernel call dispatch
- scheduling
- console and device services
- time and uptime services
- future file and storage services

User programs should not directly access kernel internals or call arbitrary kernel labels.

---

## 7. Userland Concept

Userland will eventually consist of one or more programs loaded above the resident kernel.

A user program may contain:

```text
code
data
stack
heap/work area
```

A simple early model could use fixed-size user slots:

```text
UserSlot0
UserSlot1
UserSlot2
UserSlot3
```

Each slot can hold one resident user program.

A more advanced model can later replace fixed slots with a memory allocator or variable-sized regions.

The important concept is not the exact address or slot size. The important concept is that user memory is managed separately from the kernel and can be dispatched independently.

---

## 8. Context Switching and Swapping Are Separate

AsmOSx86 should treat context switching and swapping as different operations.

A context switch changes which task owns the CPU.

Swapping changes which task image is resident in memory.

If several user programs are loaded and all fit in real memory, no swapping is needed. The scheduler can simply save the current task state and restore the next resident task state.

Conceptually:

```text
Resident Task A
Resident Task B
Resident Task C
```

A context switch among these tasks should not copy task memory. It should only save and restore CPU/task state.

If memory pressure exists and the next runnable task is not resident, then the kernel may need to swap a user image out and another image in.

Conceptually:

```text
if next task is resident:
  save current CPU context
  restore next CPU context
  resume

if next task is nonresident:
  choose memory victim if needed
  save or swap out victim
  load or swap in next task
  restore next CPU context
  resume
```

This distinction should be locked in early:

```text
Context switching is scheduling.
Swapping is memory residency management.
```

---

## 9. Current Task Model

AsmOSx86 now has a small cooperative task table for kernel and loaded user
programs.

Current implemented concepts include:

```text
task table with fixed slots
task state
saved ESP
execution-mode tag
user program physical allocation
fixed user virtual mapping at 00200000h
per-task KcBlock page at 00210000h
prepared ring 3 iretd frame
per-task startup argument area
```

Current task states:

```text
Free
Ready
Running
Blocked
Exited
```

The scheduler is cooperative. Tasks switch when user programs enter the kernel
through `int 80h` for yield, exit, sleep, keyboard read, or another service that
can block or schedule.

Future refinements may add richer task identity, session ownership, nonresident
task support, runtime budgets, or preemptive/watchdog behavior.

The design should allow that progression.

---

## 10. Current Ring 3 Userland

AsmOSx86 has a working ring 3 userland path for loaded user programs.

User programs are raw flat binaries loaded from the `ASMF` filesystem and mapped
at the fixed user virtual base:

```text
00200000h
```

Loaded user tasks enter through an `iretd` frame with:

```text
CS = USER_CODE_SEL = 001Bh
DS = USER_DATA_SEL = 0023h
SS = USER_DATA_SEL = 0023h
```

User programs enter the kernel through:

```asm
int   80h
```

The old fixed gateway address `00100005h` is reserved and denied. Ring 3
attempts to call that address page fault before reaching the ring 0 diagnostic
guard.

### Ring 3 Kernel Calls

User programs exchange arguments and results through the current task's KcBlock.

Current user-originated path:

```text
KcUserInterruptEntry
  -> KcBlockDispatch
  -> KcDispatch service handlers
```

`KcBlockDispatch` copies KcBlock values into the kernel-call globals, dispatches
the service, and copies results back when the same task resumes.

Switching and blocking calls use interrupt-aware paths:

```text
KcTsYield
KcTsExit
KcTmSleep
KcKbRead
```

`KcTsLoadProgram` is kernel-originated only. Userland program loading goes
through the console `Run` command for now.

### Ring 3 Fault Policy

Kernel faults halt the system.

User faults terminate the current task and return to the scheduler:

```text
general protection fault -> 0F0D
page fault               -> 0F0E
```

User fault diagnostics print:

```text
fault vector
faulting CS
faulting EIP
CR2 linear address for page faults
```

### Ring 3 Smoke Tests

Expected ring 3 proof results:

```text
run prog4.bin -- cpl     -> 001B
run prog4.bin -- info    -> 0101
run prog4.bin -- priv    -> fault line + 0F0D
run prog4.bin -- mem     -> fault line + 0F0E
run prog4.bin -- load    -> 0048
run prog4.bin -- legacy  -> fault at 00100005 + 0F0E
run prog4.bin            -> 0000
run prog1.bin | prog2.bin | prog3.bin
run prog4.bin -- sleep | prog1.bin | prog4.bin -- bad
```

---

## 11. Kernel Call Interface

AsmOSx86 exposes userland-accessible kernel services through a defined Kernel
Call Interface.

Project abbreviation:

```text
Kc = Kernel Call
```

User programs should not call kernel routines directly. Instead, a user program should place a service number and arguments into a memory-backed kernel-call parameter block, then enter the kernel through a defined dispatch mechanism.

Core parameter/result fields:

```asm
KcNumber      dd 0
KcStatus      dd 0
KcArg0        dd 0
KcArg1        dd 0
KcArg2        dd 0
KcArg3        dd 0
KcResult0     dd 0
KcResult1     dd 0
```

Core dispatcher and entry names:

```asm
KcDispatch
KcBlockDispatch
KcUserInterruptEntry
KcValidate
KcTable
KcTableCount
```

Current implementation status:

```text
Kc.asm exists and is included in the kernel.
The dispatcher is table-driven.
Kernel-originated calls use global memory-backed Kc fields through KcDispatch.
User-originated calls enter through int 80h and use the current task's KcBlock
through KcBlockDispatch.
KcTest exercises KcTmGetUptime and KcVdWriteStr through KcDispatch.
Run exercises program loading, task execution, filesystem calls, and task exit
through the kernel-call path.
```

Kernel-originated mechanism:

```asm
call  KcDispatch
```

User-originated mechanism:

```asm
int   80h
```

Possible later protected-mode mechanisms remain design options:

```text
trap gate
call gate
```

The architectural concept is the same in all cases:

```text
user code requests a kernel service
kernel validates the request
kernel dispatches the service
kernel stores status/results
kernel returns control
```

### Kernel Call Naming Rule

Kernel-call service names should use the form:

```text
KcAbName
```

where `Kc` means Kernel Call and `Ab` is a two-character service-family mnemonic.

Current family prefixes:

```text
KcFs*   filesystem services
KcKb*   keyboard/input services
KcVd*   video/display services
KcTm*   time services
KcTs*   task services
KcMm*   memory-management services
```

This keeps names short while still making the service family obvious.

---

## 12. Kernel Call Design Philosophy

The Kernel Call Interface should follow the same memory-contract ABI as the rest of the kernel.

User programs should not rely on register arguments as durable service contracts.

A service call should look conceptually like this:

```asm
mov   dword[KcNumber],KcVdWriteStr
mov   dword[KcArg0],UserString
call  KcDispatch
mov   eax,[KcStatus]          ; local scratch read after return
```

The important part is that the durable contract is memory:

```text
KcNumber
KcArg*
KcStatus
KcResult*
```

Registers may be used locally, but they are not the contract.

This preserves the existing AsmOSx86 rule:

```text
Memory is the contract.
Registers are scratch.
```

The kernel-call boundary is also the current ring 3 protection boundary.
Userland requests services through `int 80h`; the kernel validates the request
and decides whether to perform it.

---

## 13. Candidate Kernel Calls

The following list is conceptual. It captures the broad service families AsmOSx86 is likely to need, without locking in exact argument layouts or implementation details.

### Core Kernel Call Fields and Dispatch

```text
KcNumber        - Kernel call number requested by userland
KcStatus        - Success/error status returned by kernel
KcArg0          - Argument 0
KcArg1          - Argument 1
KcArg2          - Argument 2
KcArg3          - Argument 3, if needed
KcResult0       - Result value 0
KcResult1       - Result value 1

KcDispatch      - Dispatch requested kernel call
KcValidate      - Validate call number, arguments, caller/task state
KcLookup        - Resolve call number to handler through KcTable
KcAuthorize     - Enforce KcTable minimum authority before handler dispatch
```

Current tested calls:

```text
KcTmGetUptime   - Return monotonic uptime seconds in KcResult0
KcVdWriteStr    - Write a kernel Str through the video subsystem
KcTsYield       - Cooperative scheduling point
KcTsLoadProgram - Load a raw user program from the filesystem and prepare a task (kernel-originated only)
KcTsExit        - End the current task with an exit code
KcFsOpen        - Open an existing disk file
KcFsRead        - Read bytes from an open file
KcFsClose       - Close an open file handle
KcTmSleep       - Block current task until a cooperative wake deadline
KcKbRead        - Block current task until one keyboard event is available
KcTsGetInfo     - Return current task index and user-mode tag
KcTsGetAuthority - Return current task authority tag
KcMmGetMemory   - Trusted-only page-rounded user-memory allocation
KcMmFreeMemory  - Trusted-only stack-like user-memory release
```

The dispatch table records each service's minimum caller authority. User-originated
calls are rejected before reaching the handler when the current task does not
meet that policy. Kernel-originated dispatch can still call registered services
such as program loading.

### Filesystem — `KcFs*`

For AsmOSx86, `file` means a disk-backed filesystem object. It does not mean keyboard, video, console, pipe, socket, device, or memory buffer.

The current user-facing implementation is read-only and manifest-backed.
`Fs.asm` opens files from the raw `ASMF` floppy manifest, reads file sectors
through a tiny kernel block-device layer, and the only current block device is
floppy A:. The kernel also has a special internal writer for the preallocated
`LOG.TXT` console mirror; this is not a general file-write service.
Shared device type IDs, device IDs, and the static device registry are defined
in `Config.asm`.

```text
KcFsOpen        - Open an existing disk file; return file handle
KcFsCreate      - Create a new disk file; return file handle
KcFsClose       - Close an open file handle
KcFsRead        - Read bytes from file handle into user buffer
KcFsWrite       - Write bytes from user buffer to file handle
KcFsSeek        - Move current file position
KcFsDelete      - Delete a disk file by name
KcFsRename      - Rename a disk file
KcFsStat        - Get file metadata such as size/flags
KcFsFindFirst   - Start directory search
KcFsFindNext    - Continue directory search
KcFsFindClose   - Close directory search handle
```

### Keyboard/Input — `KcKb*`

Userland gets logical keyboard/input services. It does not call `Keyboard.asm` directly and does not own the physical keyboard hardware.

```text
KcKbPollEvent   - Check whether an input event is available
KcKbReadEvent   - Read next logical key/input event
KcKbGetChar     - Read next translated character
KcKbGetLine     - Read edited text line into user buffer
KcKbGetState    - Get input state: Shift, Ctrl, Alt, Caps Lock, etc.
KcKbFlush       - Clear pending input for the calling task/session
```

### Video/Display — `KcVd*`

Userland writes to a logical video/session buffer, not directly to VGA memory.

```text
KcVdWriteChar   - Write one character at current session cursor
KcVdWriteStr    - Write Str at current session cursor
KcVdWriteAt     - Write character/string at row/column
KcVdClear       - Clear the calling session’s display buffer
KcVdSetCursor   - Set session cursor position
KcVdGetCursor   - Get session cursor position
KcVdSetAttr     - Set current text attribute/color
KcVdGetAttr     - Get current text attribute/color
KcVdGetSize     - Get display dimensions, e.g. rows/columns
KcVdBlit        - Copy user-supplied screen buffer/region to session display
```

### Time — `KcTm*`

```text
KcTmGetWall     - Get wall/calendar time
KcTmGetUptime   - Get monotonic uptime
KcTmSleep       - Sleep/delay current task for a duration
```

### Task Services — `KcTs*`

```text
KcTsYield       - Voluntarily yield CPU
KcTsExit        - End current task
KcTsGetId       - Get current task ID
KcTsGetState    - Get current task state/info
```

### Memory Management — `KcMm*`

```text
KcMmGetMemory   - Request more user memory
KcMmFreeMemory  - Release user memory
KcMmInfo        - Get memory limits/available memory for task/session
```

The current `KcMmGetMemory` / `KcMmFreeMemory` implementation is intentionally
small. Trusted/system tasks can grow their own user mapping by whole pages from
the task's reserved user-program slot. `FreeMemory` currently releases only the
most recent allocation, keeping the first allocator stack-like instead of a full
heap.

The broader memory-service list should remain small until real user programs
need more.

---

## 14. Current Time Model

AsmOSx86 currently distinguishes two time concepts:

```text
monotonic time
wall/calendar time
```

Monotonic time is based on the PIT and is used for elapsed time, delays, scheduling, profiling, and uptime.

Wall time is based on RTC/CMOS and is used for human-readable timestamps, logs, date display, and time display.

Current ownership:

```text
Timer.asm   owns monotonic PIT tick accumulation
Uptime.asm  owns uptime reporting based on monotonic ticks
Time.asm    owns wall/calendar time
```

This separation should remain.

Future scheduler and timeout code should use monotonic time, not wall time.

---

## 15. Current Console Model

The current console is a kernel/operator console. It should be understood as the fixed operator terminal for the machine, not as userland standard input/output.

It provides:

- kernel startup messages
- optional `STARTUP.TXT` startup command stream
- operator command input
- command logging
- command dispatch
- diagnostics
- shutdown/control commands

Current commands:

```text
Clear
Date
Delay
FsTest
Help
KcTest
Run
Shutdown
Time
Uptime
```

The console currently lives inside the kernel and should remain reserved for operator control and diagnostics. Userland should not call `Console.asm` routines directly and should not treat the kernel console as its default terminal.

The console also acts as a convenient proof point for the memory-contract ABI:

- commands are matched through memory-backed state
- video output uses `pVdStr`
- keyboard output uses `KbOut*`
- delay uses `TimerDelayMs`
- uptime prints through `UptimePrint`
- `KcTest` exercises `KcDispatch`, `KcVdWriteStr`, and `KcTmGetUptime`

After startup messages, the console attempts to open optional `STARTUP.TXT`.
Each nonblank line is trimmed, timestamp-logged, and dispatched through the same
command table used for typed input. `Startup.txt` is the source file normally
packed into the image as `STARTUP.TXT`. Its expected contents are ordinary
console commands, commonly diagnostics, smoke-test runs, setup commands, or
`shutdown` for a fully automated build/run/validate cycle.

The trusted startup/console launch path can tag a task as trusted or system
with a launch prefix such as `/trusted` or `/system` before the program name.
For example, `run /system prog4.bin` requests system authority for that loaded
task. This is policy assigned by the trusted command source while loading the
task, not authority granted by the user program after it starts.

Future userland input/output should use separate `KcKb*` and `KcVd*` services tied to logical task/session state.

---

## 16. Current Shutdown Semantics

The current `Shutdown` command:

1. logs shutdown messages
2. waits briefly
3. attempts emulator-style soft power-off ports
4. disables interrupts
5. halts the CPU

Conceptually:

```text
tell the operator what is happening
give the message time to be seen
try soft power-off if the runtime supports it
fall back to halt forever
```

On real 386-class hardware, the soft power-off ports may do nothing. The final halt is the reliable behavior.

---

## 17. Keyboard, Video, and Session Device Model

AsmOSx86 should distinguish physical devices from logical task/session services.

Physical keyboard and video hardware are kernel-owned. Userland should not call `Keyboard.asm` or `Video.asm` directly. Instead, user programs should use `KcKb*` and `KcVd*` services that operate on the calling task/session.

Conceptual split:

```text
Keyboard.asm    = physical keyboard hardware driver
Video.asm       = physical VGA/text display driver
Console.asm     = kernel/operator console
KcKb*           = userland logical input services
KcVd*           = userland logical display services
```

There may be only one physical keyboard and one physical screen, but there can be multiple logical sessions.

Example:

```text
Task A session: input queue + screen buffer
Task B session: input queue + screen buffer
Task C session: input queue + screen buffer

Only the active session receives normal keyboard input.
Only the active session is displayed on the physical screen.
```

Kernel-reserved key combinations, such as a future Alt-Tab style session switch, should be intercepted by the kernel before userland receives the event. Switching sessions would conceptually change both the active input target and the active video buffer.

A full-screen editor-style user program should be able to request logical keyboard events and keyboard state, such as Shift, Ctrl, Alt, and Caps Lock, through `KcKb*` calls. It should also be able to update its own logical display through `KcVd*` calls.

Video output currently uses VGA text memory. The video subsystem owns:

- output cursor position
- input cursor position
- color attribute
- screen clearing
- scrolling
- hardware cursor update

Strings use the AsmOSx86 `Str` representation:

```text
[u16 length][payload bytes]
```

The `String` macro creates this representation.

Current kernel text output flows through:

```text
pVdStr -> VdPutStr -> VdPutChar -> VGA memory
```

That remains the kernel-side text output path. Future userland display output should go through `KcVd*` and logical session buffers rather than direct VGA access.

---

## 18. Memory Layout Direction

The current concrete base is:

```text
KernelBase = 00100000h
```

Future layout should keep the kernel resident and place user memory above it.

Example conceptual layout:

```text
00100000h  KernelBase
           resident kernel image
           kernel globals
           kernel stacks
           kernel buffers
KernelEnd

UserPoolBase
           user task memory blocks
           user stacks
           user data
UserPoolEnd
```

The exact addresses do not need to be locked yet.

Early experimentation may use fixed user slots. Later versions can use a user memory allocator.

---

## 19. Evolution Path

A reasonable development sequence is now partly complete.

### Completed foundation

Current status includes:

```text
Boot.asm loads the kernel
kernel initializes paging, Kc, timer, uptime, filesystem, video, log, keyboard, and console
wall time initializes lazily on first Time* use
console commands work
memory-contract ABI enforced in included kernel files
ASMF manifest file loading works
Run launches one to three loaded user programs
loaded user programs run in ring 3
user programs enter kernel services through int 80h
cooperative task switching works for yield, exit, sleep, and keyboard wait
LOG.TXT captures console output
STARTUP.TXT can automate smoke tests and shutdown
```

### Remaining direction

Future growth should build from the current foundation:

```text
richer task/process/session identity
more complete filesystem behavior
additional block devices
logical user sessions
optional nonresident task/backing-store policy
timer interrupt event collection
runaway-task watchdog policy
possible preemptive scheduling only if it proves useful
```

Swapping should remain separate from task switching. Hardware timer scheduling
should remain separate from timer interrupt event collection.

---

## 20. Scheduling, Interrupts, and Runaway Task Policy

AsmOSx86 should distinguish interrupts from scheduling.

Hardware interrupts may be used for device event collection and kernel timekeeping, but an interrupt does not automatically mean the kernel should transparently preempt the current task and resume it later.

The preferred scheduling model is cooperative:

```text
Tasks keep running until they reach a kernel-defined scheduling point.
```

Examples of scheduling points:

```text
KcTsYield        ; task voluntarily yields
KcTsExit         ; task exits
KcTmSleep        ; task sleeps for a duration
KcKbReadEvent    ; task blocks waiting for input
KcFsRead         ; task blocks waiting for file/device I/O
KcFsWrite        ; task blocks waiting for file/device I/O
```

Interrupt handlers should normally do minimal work:

```text
acknowledge hardware
record event/state
wake or mark blocked tasks as ready if appropriate
return
```

Examples:

```text
Timer interrupt     -> update tick state, wake sleepers if needed
Keyboard interrupt  -> collect/queue input event
Disk interrupt      -> mark I/O complete
```

The scheduler runs at explicit kernel-controlled points, not merely because an interrupt occurred.

### Yield Does Not Require a Context Switch

A task reaching a scheduling point gives the kernel permission to make a scheduling decision. It does not require the kernel to dispatch a different task.

For example, if two programs are runnable:

```text
ProgA = Runnable/Running
ProgB = Runnable
```

and `ProgA` calls `KcTsYield`, the kernel may choose to continue running `ProgA` if scheduler policy says it has not yet used enough of its current cooperative runtime budget.

Conceptually:

```text
ProgA calls KcTsYield after 5 ms.
Kernel checks runtime accounting.
ProgA budget is 50 ms.
Kernel may return to ProgA.

ProgA later calls KcTsYield after total 50 ms.
Kernel may save ProgA and dispatch ProgB.
```

Design rule:

```text
Yield = safe scheduling opportunity.
Context switch = scheduler decision.
```

A possible future policy:

```text
KcTsYield:
  update current task runtime accounting
  check runnable tasks, priority, wait state, and runtime budget
  if current task should continue:
    return to current task
  else:
    save current task context
    choose next runnable task
    dispatch selected task
```

This preserves cooperative control flow while still allowing the kernel to enforce fairness. Programs must enter the kernel at scheduling points, but the scheduler decides whether that point results in an actual task switch.

### Runaway Task Policy

AsmOSx86 may later use timer interrupts as an enforcement mechanism, but not as the normal scheduling mechanism.

If a user task exceeds its allowed CPU budget without entering the kernel through a yield, block, sleep, wait, or exit call, the task is considered runaway.

The kernel may terminate the offending task rather than transparently preempting and later resuming it.

Conceptually:

```text
Task starts or resumes.
Kernel gives it a CPU budget.
Task is expected to reach a kernel scheduling point.
If the budget expires first, the task is killed as runaway.
```

This policy keeps the system understandable:

```text
Normal scheduling = cooperative
Timer enforcement = watchdog / runaway detection
Overrun result    = terminate offending task
```

Possible future task states:

```text
Running
Runnable
Blocked
Sleeping
Exited
Killed
Runaway
```

The operator console may report runaway termination events, for example:

```text
Task 3 killed: CPU budget exceeded
```

Design principle:

```text
Interrupts keep the kernel aware of hardware events.
They do not automatically grant permission to context-switch a task.
Context switches occur at explicit kernel scheduling points.
A task that refuses to cooperate may be terminated.
```

---

## 21. Blocking Kernel Calls and Task Readiness

Some Kernel Calls complete immediately. Others may need to wait for a device, file operation, input event, timer, or other external condition.

A Kernel Call is therefore both a service request and, in some cases, a scheduling point.

Example:

```text
ProgA calls KcFsOpen.
Kernel validates the request.
If the file can be opened immediately, the kernel returns to ProgA.
If the open cannot complete yet, the kernel blocks ProgA and dispatches another ready task.
```

Conceptual state transition:

```text
Running -> Blocked -> Ready -> Running
```

### Example: KcFsOpen

A user program requests a disk file open:

```text
KcNumber = KcFsOpen
KcArg0   = pointer to filename
KcArg1   = open mode
```

The kernel then:

```text
validates the caller
validates the filename pointer
validates the open mode
starts or performs the filesystem open work
```

If the request completes immediately:

```text
KcStatus  = success or error
KcResult0 = file handle if successful
return to ProgA
```

If the request must wait on disk or filesystem work:

```text
ProgA.State      = Blocked
ProgA.WaitReason = FileOpen
ProgA.WaitObject = file/disk request
kernel dispatches another Ready task
```

Later, when the file operation completes:

```text
kernel finishes file-open bookkeeping
KcStatus  = success or error
KcResult0 = file handle if successful
ProgA.State = Ready
```

When the scheduler later chooses ProgA again, ProgA resumes immediately after the Kernel Call and reads the memory-backed result fields.

### Immediate Calls vs Blocking Calls

Not every Kernel Call blocks.

Examples of calls that usually complete immediately:

```text
KcTmGetUptime
KcTmGetWall
KcVdSetCursor
KcVdGetSize
```

Examples of calls that may block:

```text
KcFsOpen
KcFsRead
KcFsWrite
KcKbReadEvent
KcKbGetLine
```

Examples of calls that are scheduling points by definition:

```text
KcTsYield
KcTmSleep
KcTsExit
```

Design rule:

```text
If a Kernel Call can complete now, return to the caller.
If a Kernel Call cannot complete now, block the caller and run another ready task.
When the event completes, mark the caller Ready.
```

### Blocked Reasons

A task may be blocked for different reasons:

```text
BlockedOnFile
BlockedOnKeyboard
BlockedOnTimer
BlockedOnDevice
```

These reason names are conceptual. The exact implementation may use numeric wait codes, flags, or task-table fields.

The important rule is that a blocked task is not runnable until the event it waits on completes.

### Kernel Call Result Contract

Even when a Kernel Call blocks, the user program still sees a normal return later.

The task resumes after the Kernel Call with memory-backed results populated:

```text
KcStatus
KcResult0
KcResult1
```

The user program does not need to know whether the service completed immediately or required the task to be blocked and resumed later.

---

## 22. Kernel Call Communication Area

Each user task should have a standard Kernel Call communication area.

Project term:

```text
KcBlock
```

The `KcBlock` is the shared memory contract between one user task and the kernel.

Conceptually:

```text
User task fills KcBlock.
User task enters kernel through the Kernel Call Interface.
Kernel reads KcBlock.
Kernel performs or starts the requested service.
Kernel writes status/results back to KcBlock.
User task resumes and reads KcBlock.
```

### One Task, One Active KcBlock

Each task should have its own active `KcBlock`.

A single global `KcBlock` would not work well once multiple tasks exist because tasks could overwrite one another’s arguments or results.

Design rule:

```text
One task owns one active KcBlock.
Only the running task and the kernel access that task’s KcBlock.
```

The task table may eventually record:

```text
TaskId
TaskState
TaskKcBlockPtr
```

When the task enters the kernel, the kernel uses the current task record to find the correct `KcBlock`.

### Generic Layout

The `KcBlock` should be generic. It should not be customized per service.

Example conceptual fields:

```text
KcNumber       requested Kernel Call number
KcStatus       returned success/error status
KcArg0         argument 0
KcArg1         argument 1
KcArg2         argument 2
KcArg3         argument 3
KcResult0      result 0
KcResult1      result 1
```

Individual Kernel Calls interpret `KcArg*` and `KcResult*` according to `KcNumber`.

Example: file open

```text
KcNumber  = KcFsOpen
KcArg0    = pointer to filename Str
KcArg1    = open mode
KcStatus  = success/error
KcResult0 = file handle if successful
```

Example: file read

```text
KcNumber  = KcFsRead
KcArg0    = file handle
KcArg1    = destination buffer pointer
KcArg2    = byte count
KcStatus  = success/error
KcResult0 = bytes read
```

Example: uptime

```text
KcNumber  = KcTmGetUptime
KcStatus  = success/error
KcResult0 = uptime seconds or low result value
KcResult1 = optional high result value if needed
```

### Placement for User Programs

Each user task should have a `KcBlock`-compatible communication area, but it does
not need to live inside the user program image.

Conceptually:

```text
ProgA task:
  code
  data
  stack
  KcBlock
```

When the program is loaded and prepared for execution, the loader or task setup code records the address of the program's `KcBlock` in the task table.

Early AsmOSx86 currently uses the simple rule:

```text
Every user task receives a separate KcBlock page.
```

The current raw user programs are assembled for virtual base `00200000h`, and
the task's KcBlock is mapped at the fixed virtual address `00210000h`.

Later, the kernel could make this address discoverable through metadata or a
startup contract, but the initial model should stay simple.

### Blocking Calls and KcBlock Completion

If a Kernel Call blocks, the task’s `KcBlock` remains the place where the eventual result is written.

Example:

```text
ProgA fills KcBlock for KcFsOpen.
ProgA enters kernel.
Kernel marks ProgA BlockedOnFile.
Kernel dispatches another Ready task.
File operation completes.
Kernel writes ProgA.KcStatus and ProgA.KcResult0.
Kernel marks ProgA Ready.
ProgA later resumes after the Kernel Call.
ProgA reads its KcBlock.
```

This keeps immediate and delayed completion using the same user-visible contract.

Design rule:

```text
The user program resumes as if the Kernel Call returned normally,
even if the task was blocked and resumed before the result became available.
```

---

## 23. User Sessions, Sign-On, and Menu Panels

AsmOSx86 should use the concept of a user session rather than centering the userland model around a shell.

A session is a kernel-managed user interaction environment.

A session is not the same thing as a shell. A shell, menu, editor, or application may run inside or be attached to a session, but the session itself is the authenticated interaction context.

Design terms:

```text
Session       = user interaction environment
SignOn        = authentication front door for a session
MenuPanel     = post-login program selection panel
UserProgram   = work performed after menu selection
Console       = kernel/operator-only interface
```

### Console vs Session

The kernel console remains reserved for the computer operator.

The operator console is used for:

```text
kernel startup messages
kernel commands
diagnostics
shutdown
operator control
```

Userland does not own the kernel console and should not call `Console.asm` routines directly.

Userland interaction happens through sessions and future session/device-oriented Kernel Calls.

Design rule:

```text
Console.asm is the kernel/operator interface.
A user session is the user interaction environment.
They are separate concepts.
```

### Starting a Session

The OS should not care too much how a session was started.

Current AsmOSx86 can already load raw userland binaries from the raw `ASMF`
floppy image and run multiple cooperative user tasks. The console is the current
operator interface to that capability.

A session may eventually be started by:

```text
operator command
automatic boot policy
future session manager
future task launcher
future remote terminal
```

The first practical session path may therefore be a console command such as
`StartSession` or `Start Session`. That command would ask the kernel to load a
session/sign-on program from disk, create the required task and session state,
and make that session eligible to become the active input/video target.

Once started, a session presents a sign-on panel.

### Sign-On Panel

The initial user-facing panel should be simple.

Conceptual sign-on panel:

```text
SIGN ON

USER ID  . . . . . . . . . . .
PASSWORD . . . . . . . . . . .
```

For now, the sign-on panel needs only:

```text
User ID
Password
```

After successful sign-on:

```text
session becomes authenticated
session receives logical input/video state
session proceeds to the post-login menu panel
```

If sign-on fails, the session may redisplay the sign-on panel or end the session.

### Menu Panel

After successful login, the user should be presented with a menu panel.

Conceptual menu panel:

```text
MAIN MENU

1. Customer Inquiry
2. Customer Update
3. Customer List

Selection . . . _
```

The menu is not a shell. It is the session’s initial program selection interface.

Selecting a menu item requests that the system start or attach the corresponding userland program.

The implementation behind that selection is intentionally left as a black box for now. Later it may involve:

```text
loading a program from disk
starting an already-resident program
attaching to an existing task
dispatching through a session manager
calling a task launcher
```

The design does not need to lock that in yet.

### Session and Logical Devices

A session owns logical input and logical video state.

There may be one physical keyboard and one physical display, but multiple logical sessions.

Conceptually:

```text
Session A:
  input queue
  video buffer
  cursor state
  authenticated user state

Session B:
  input queue
  video buffer
  cursor state
  authenticated user state
```

Only the active session receives normal keyboard input. Only the active session’s video buffer is displayed on the physical screen.

A future session switch, such as an Alt-Tab-style operation, would be kernel-managed:

```text
kernel intercepts session-switch key
active input session changes
active video session changes
new active session buffer is redrawn
new active session cursor is restored
```

Design rule:

```text
Physical devices are kernel-owned.
User sessions receive logical input and logical video services.
```

---

## 24. Design Principles

### Keep the kernel resident

The kernel stays at a fixed address and is not swapped.

### Keep userland replaceable

User programs live outside the kernel and can be loaded, scheduled, and eventually swapped independently.

### Separate scheduling from swapping

A task switch should not imply memory movement.

### Use memory-backed contracts

Registers are scratch. Memory variables and parameter blocks define the contract.

### Keep services behind a kernel-call boundary

User programs do not call arbitrary kernel routines.

### Start simple

Use direct calls and simple tables for kernel-originated paths. Use the current
`int 80h` ring 3 path for user-originated services. Avoid adding larger
frameworks until the current memory-backed contracts need them.

### Add hardware complexity deliberately

Introduce hardware features only when they clarify or support the execution
model being tested. Paging is now part of the current user-program loading
model, and ring 3 is now the current userland enforcement mechanism.
Preemption, richer interrupt use, and broader hardware enforcement can still
come later.

---

## 25. Out of Scope For Now

AsmOSx86 does not need these immediately:

```text
general-purpose file write/create/delete
full native filesystem allocation
full dynamic device model
logical user sessions
nonresident task swapping
preemptive scheduler
```

Those can come later.

The current completed foundation is:

```text
resident kernel + console + ASMF file loading + ring 3 user tasks
```

The next growth path is toward:

```text
resident kernel + kernel call interface + logical sessions + richer filesystem
```

---

## 26. Working Definition

AsmOSx86 is a resident 32-bit protected-mode kernel loaded at `00100000h`.

It uses a memory-contract ABI internally and exposes user/kernel services through
a memory-backed Kernel Call Interface abbreviated `Kc`.

The kernel remains fixed in memory. User programs live above the kernel. If multiple user programs fit in memory, context switching only changes CPU/task state. Swapping is optional and only needed when runnable tasks cannot all remain resident.

The current console, timer, wall-time, uptime, keyboard, video, utility,
filesystem, task, paging, and kernel-call subsystems support loaded ring 3 user
programs through `int 80h`.
