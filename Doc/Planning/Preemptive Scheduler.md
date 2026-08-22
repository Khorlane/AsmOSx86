# Preemptive Scheduler

## Where AsmOSx86 Is Now

AsmOSx86 currently has the beginning of cooperative scheduling.

User programs voluntarily enter the kernel through scheduling points such as:

```text
KcTsYield
KcTsExit
KcTmSleep
KcKbRead
```

The kernel can then choose the next ready task and switch to it.

The current user-program tests prove useful groundwork:

```text
raw user programs loaded from the ASMF manifest filesystem
programs mapped at a fixed virtual base
programs take turns running
programs yield more than once
exit codes prove each program completed its own work
```

This is the right foundation because task switches happen at explicit,
understandable points.

## Current Code Reality

The current scheduler is cooperative, not preemptive.

Implemented pieces:

```text
Task table with up to 8 task records
task states: Free, Ready, Running, Blocked, Exited
saved ESP per task
low-memory stack-slot assignment
file-backed raw user-program loading
per-task physical program allocation above the kernel
fixed user virtual base at 00200000h
per-task KcBlock page at 00210000h
round-robin scan for the next Ready task
cooperative sleep blocking and wake checks
keyboard-read blocking until a key event is available
interrupt-aware switch paths for user yield/exit/sleep/key services
```

The current user-program loader reads raw `PROG*.BIN` files through the
`KcFsOpen` / `KcFsRead` / `KcFsClose` path, which currently resolves files
through the `ASMF` manifest on the raw floppy image.

The current cooperative switch point is `TaskYield`. It saves the current
kernel task's `ESP`, marks the current task ready unless it has exited, scans
the task table for the next `Ready` task, maps that task's program into the
shared user virtual range, and resumes the selected task. Kernel tasks resume
through their saved stack; user tasks resume through a saved ring 3 `iretd`
frame.

The current user/kernel entry path for user tasks is `int 80h`. Kc calls still
use the current task's KcBlock, and switching/blocking calls are handled
through interrupt-aware task routines because they can change which task resumes
after the kernel call.

What does not exist yet:

```text
timer interrupt scheduling
preemptive task interruption
runtime budget accounting
runaway-task enforcement
interrupt-safe scheduler state
general wait queues for filesystem/device I/O
```

The empty IDT is loaded during kernel startup, and the PIT is polled for current
timekeeping. The current kernel still does not depend on hardware interrupts for
normal scheduling.

## Cooperative vs Preemptive

Cooperative scheduling:

```text
task runs until it calls KcTsYield, KcTsExit, or a blocking Kc* service
```

Preemptive scheduling:

```text
timer interrupt can stop the task even if it did not yield
kernel saves the interrupted task state
kernel chooses another ready task
kernel resumes that other task
```

The conceptual difference is:

```text
cooperative:
  task gives the kernel a scheduling opportunity

preemptive:
  kernel takes a scheduling opportunity
```

## Why Not Rush It

Full preemption brings a lot of complexity:

```text
timer IRQ setup
interrupt handlers
interrupt-safe kernel state
saved interrupted CPU state
critical sections
reentrancy problems
kernel code that can be interrupted mid-update
harder debugging
```

AsmOSx86 currently benefits from keeping scheduling explicit and easy to reason
about. Cooperative scheduling is not a lesser toy model here. It is a clean
foundation.

## Recommended Future Path

A staged path makes the most sense:

```text
1. Keep cooperative scheduling as the normal model.
2. Add more blocking scheduling points.
3. Add timer interrupts for tick/event collection.
4. Add timer-based runaway-task detection.
5. Consider true transparent preemption only if it becomes clearly useful.
```

Likely future scheduling points:

```text
KcTsYield       task voluntarily yields
KcTsExit        task exits
KcTmSleep       task sleeps for a duration
KcKbReadEvent   task waits for input
KcFsRead        task waits for file/device I/O
KcFsWrite       task waits for file/device I/O
```

## Timer Interrupt as Watchdog

A timer interrupt does not have to imply full preemptive scheduling.

One useful intermediate model:

```text
task starts or resumes
kernel gives it a CPU budget
timer interrupt tracks elapsed runtime
task is expected to enter the kernel through a scheduling point
if the task exceeds its budget first, it is considered runaway
kernel kills or stops the task
```

This gives AsmOSx86 a safety story without requiring transparent preemption.

Important distinction:

```text
timer interrupt as watchdog:
  detects a task that failed to cooperate

timer interrupt as preemptive scheduler:
  saves the task and resumes it later automatically
```

## Possible Long-Term Policy

AsmOSx86 may never need classic full preemptive scheduling.

A strong and understandable model could be:

```text
well-behaved task:
  yields, sleeps, blocks, or exits

runaway task:
  exceeds its budget and gets killed

kernel:
  schedules at explicit kernel-controlled points
```

This keeps the OS simple, direct, and debuggable while still preventing a bad
user task from owning the CPU forever.

## Classification

This feature should probably be split into two ideas:

```text
timer-based runaway detection = likely desirable later
preemptive scheduler          = optional, maybe not planned
```

Privilege separation through ring 3 is now present as an initial OS hardening
step. Full preemptive scheduling is more optional. The cooperative model plus
watchdog enforcement may be enough for the kind of OS AsmOSx86 is becoming.
