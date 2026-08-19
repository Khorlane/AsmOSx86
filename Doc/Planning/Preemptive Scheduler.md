# Preemptive Scheduler

## Where AsmOSx86 Is Now

AsmOSx86 currently has the beginning of cooperative scheduling.

User programs voluntarily enter the kernel through scheduling points such as:

```text
KcTsYield
KcTsExit
```

The kernel can then choose the next ready task and switch to it.

The current user-program tests prove useful groundwork:

```text
raw user programs loaded from FAT12
programs mapped at a fixed virtual base
programs take turns running
programs yield more than once
exit codes prove each program completed its own work
```

This is the right foundation because task switches happen at explicit,
understandable points.

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

Privilege separation through ring 3 is more clearly desirable as a future OS
hardening step. Full preemptive scheduling is more optional. The cooperative
model plus watchdog enforcement may be enough for the kind of OS AsmOSx86 is
becoming.
