# AsmOSx86 High-Level Design and Concept Documentx

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
Keyboard.asm
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
- simple built-in commands:
  - `Date`
  - `Delay`
  - `Help`
  - `Shutdown`
  - `Time`
  - `Uptime`

At this stage, AsmOSx86 is still a single resident kernel with an integrated console. Userland does not exist yet.

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

This rule applies to kernel routines and to future user/kernel interfaces.

### Why this matters

This rule simplifies reasoning in assembly. It makes every routine boundary explicit and prevents accidental dependencies on transient register state.

It also fits the future kernel-call model: user programs will request services by filling a memory-backed parameter block, not by relying on arbitrary live registers.

---

## 4. Current Boot and Kernel Placement Model

The boot flow is currently staged:

```text
Boot1.asm  -> stage 1 boot sector
Boot2.asm  -> stage 2 loader
Kernel.asm -> protected-mode kernel at 00100000h
```

The kernel lives at:

```text
KernelBase = 00100000h
```

This is the preferred long-term kernel base.

Conceptual memory layout:

```text
00000000h - 000FFFFFh   low memory, BIOS legacy areas, loader workspace, reserved
00100000h - KernelEnd   resident AsmOSx86 kernel
UserBase   - UserLimit  future user memory region or user memory pool
```

The kernel should remain fixed in memory. User programs should live above the kernel in a controlled user memory region.

---

## 5. Kernel Residency Principle

The kernel is resident and permanent.

A future user program may be loaded, stopped, replaced, or swapped, but the kernel remains in place.

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

## 6. Userland Concept

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

## 7. Context Switching and Swapping Are Separate

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

## 8. Future Task Model

A future task table may describe each task known to the kernel.

Example fields, not locked implementation:

```text
TaskId
TaskState
TaskResident
TaskMemBase
TaskMemLimit
TaskEntry
TaskEip
TaskEsp
TaskFlags
TaskBackingStore
```

Possible task states:

```text
Free
Loaded
Runnable
Running
Blocked
Waiting
Nonresident
Exited
```

The early implementation can be much simpler. For example, it may begin with only one manually loaded user task, then grow into multiple resident tasks, then later add nonresident task support.

The design should allow that progression.

---

## 9. Kernel Call Interface

AsmOSx86 should expose userland-accessible kernel services through a defined Kernel Call Interface.

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

Core dispatcher names:

```asm
KcDispatch
KcValidate
KcTable
KcTableCount
```

The exact mechanism can evolve.

Early mechanism:

```asm
call  KcDispatch
```

Later mechanism:

```asm
int   KC_VECTOR
```

Possible later protected-mode mechanisms:

```text
trap gate
interrupt gate
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

## 10. Kernel Call Design Philosophy

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

The kernel-call boundary is also a protection boundary in design, even before hardware privilege enforcement exists. Userland requests services; the kernel decides whether the request is valid and how to perform it.

---

## 11. Candidate Kernel Calls

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
```

### Filesystem — `KcFs*`

For AsmOSx86, `file` means a disk-backed filesystem object. It does not mean keyboard, video, console, pipe, socket, device, or memory buffer.

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
KcMmAlloc       - Allocate user memory
KcMmFree        - Free user memory
KcMmInfo        - Get memory limits/available memory for task/session
```

The first practical implementation should be much smaller than this list. The goal is to establish the boundary first, not to build a large service catalog immediately.

---

## 12. Current Time Model

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

## 13. Current Console Model

The current console is a kernel/operator console. It should be understood as the fixed operator terminal for the machine, not as userland standard input/output.

It provides:

- kernel startup messages
- operator command input
- command logging
- command dispatch
- diagnostics
- shutdown/control commands

Current commands:

```text
Date
Delay
Help
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

Future userland input/output should use separate `KcKb*` and `KcVd*` services tied to logical task/session state.

---

## 14. Current Shutdown Semantics

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

## 15. Keyboard, Video, and Session Device Model

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

## 16. Memory Layout Direction

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

## 17. Evolution Path

A reasonable development sequence:

### Phase 1 — Current kernel baseline

Current status:

```text
bootloader loads kernel
kernel initializes timer/video/keyboard/console/time/uptime
console commands work
memory-contract ABI enforced in included kernel files
```

### Phase 2 — Kernel Call Interface skeleton

Add:

```text
KcNumber
KcStatus
KcArg*
KcResult*
KcDispatch
small KcTable
```

Initial calls can be invoked internally with `call KcDispatch`.

### Phase 3 — Simple user program arena

Add:

```text
UserBase
UserLimit
one manually loaded test program
simple user stack
controlled entry/return
```

The first user program can be extremely small.

### Phase 4 — Multiple resident tasks

Add:

```text
task table
resident task states
save/restore task context
round-robin or manual yield
```

No swapping is required if all test tasks fit in memory.

### Phase 5 — Optional swapping

Only after resident task switching works:

```text
task backing store
resident/nonresident task state
swap in/out policy
```

Swapping should not be part of the first context-switch implementation.

### Phase 6 — Hardware timer scheduling

Once task save/restore is solid:

```text
timer interrupt
preemptive scheduling
priority policy
sleep/timeouts
```

---

## 18. Scheduling, Interrupts, and Runaway Task Policy

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

## 19. Blocking Kernel Calls and Task Readiness

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

## 20. Kernel Call Communication Area

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

### Placement in User Programs

A user program image should include or reserve a `KcBlock`-compatible area.

Conceptually:

```text
ProgA image:
  code
  data
  stack
  KcBlock
```

When the program is loaded and prepared for execution, the loader or task setup code records the address of the program’s `KcBlock` in the task table.

Early AsmOSx86 can use the simple rule:

```text
Every user program contains a standard KcBlock in its data area.
```

Later, the kernel could allocate the block or define it through program metadata, but the initial model should stay simple.

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

## User Sessions, Sign-On, and Menu Panels

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

A session may eventually be started by:

```text
operator command
automatic boot policy
future session manager
future task launcher
future remote terminal
```

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

## 21. Design Principles

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

Use direct calls and simple tables before introducing interrupts, privilege transitions, or gates.

### Avoid premature hardware complexity

Do not introduce paging, privilege rings, or preemption before the basic execution model is understandable and testable.

---

## 22. Non-Goals For Now

AsmOSx86 does not need these immediately:

```text
paging
ring 3 enforcement
full filesystem
ELF loader
dynamic linker
preemptive scheduler
virtual memory
user/kernel privilege separation
advanced device model
```

Those can come later.

The near-term goal is a clean conceptual path from:

```text
resident kernel + console
```

to:

```text
resident kernel + kernel call interface + simple user task
```

---

## 23. Working Definition

AsmOSx86 is a resident 32-bit protected-mode kernel loaded at `00100000h`.

It uses a memory-contract ABI internally and should expose future user/kernel services through a memory-backed Kernel Call Interface abbreviated `Kc`.

The kernel remains fixed in memory. User programs live above the kernel. If multiple user programs fit in memory, context switching only changes CPU/task state. Swapping is optional and only needed when runnable tasks cannot all remain resident.

The current console, timer, wall-time, uptime, keyboard, video, and utility subsystems form the practical base for the next step: a small kernel-call dispatcher and a first controlled user program.
