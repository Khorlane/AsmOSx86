# Kernel Initialization Sequence

This document describes the current kernel initialization flow implemented by `Kernel.asm`.

It is descriptive of the current code, not a broader future policy.

---

## Ownership Rule

`Kernel.asm` owns the top-level initialization sequence.

It decides which subsystems are initialized explicitly during boot and in what order.

---

## Current Boot Sequence

Current initialization order in `Kernel.asm`:

1. Load GDT and reload code/data segment state
2. Load an empty IDT
3. `TimerInit`
4. `VdInit`
5. `KbInit`
6. `CnInit`
7. Enter the main console loop

This is the active source-of-truth sequence.

---

## Current Dependency Notes

- `TimerInit` must occur before timer-backed services are used.
- `VdInit` must occur before normal kernel screen output is relied on.
- `KbInit` must occur before keyboard polling is used.
- `CnInit` occurs after timer, video, and keyboard initialization.

---

## Time Initialization Behavior

Wall time is not explicitly initialized in `Kernel.asm` during boot.

Current behavior:
- `CnInit` emits startup log messages
- log output uses wall-time printing
- wall time becomes initialized on demand through `TimeNow`
- `TimeNow` calls `TimeSync` if wall-time state is not yet valid

This lazy initialization behavior is intentional, not accidental.

Current design intent:
- `TimerInit` is the only required prerequisite before wall time is used
- the kernel does not perform a separate boot-time `TimeSync`
- console is intended to start as early as practical in boot
- early console logging/display is expected to trigger first wall-time use very early in startup

---

## Uptime Initialization Behavior

`UptimeInit` is not part of the current active kernel initialization path.

`Uptime.asm` exists as a subsystem, but it is not currently included by `Kernel.asm`.

---

## Early-Use Rule

Current code allows limited lazy initialization for wall time through `Time.asm`.

So the correct rule today is:
- some services require explicit init
- wall time currently supports first-use initialization internally

This document should not claim that all subsystems forbid lazy init.

---

## Summary

- `Kernel.asm` owns the active boot order
- current boot order is `TimerInit`, `VdInit`, `KbInit`, `CnInit`
- wall time intentionally initializes lazily on first use
- console is designed to come up early, so first wall-time use normally happens very early in boot
- `UptimeInit` is not part of the active kernel boot path today
