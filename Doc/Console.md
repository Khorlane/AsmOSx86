# Console Command Semantics

This document defines the current console-command behavior for AsmOSx86.

It is the authoritative behavior/spec document for user-visible console commands.

Use this file for:
- command meanings
- command match rules
- user-visible behavior
- design intent for command outcomes

Use `Console.asm` for implementation details.

---

## Console Role

The console is the primary interactive shell for the current kernel.

Current boot flow brings the console up early in startup, after timer, video, and keyboard initialization.

The active command set currently includes:
- `Date`
- `Delay`
- `Help`
- `Shutdown`
- `Time`

---

## Command Matching

Current command-dispatch rules are:
- exact match only
- case-insensitive
- length must match after input trimming
- no argument parsing

If no command matches, the console currently does nothing and simply returns to the input loop.

---

## Command Semantics

### `Help`
- Prints the current command names from the command table.
- Output order follows the active command table in `Console.asm`.

### `Date`
- Prints the current wall date using the wall-time subsystem.
- Output format is defined by `Doc/Time.md`.

### `Time`
- Prints the current wall time using the wall-time subsystem.
- Output format is defined by `Doc/Time.md`.

### `Delay`
- Prints a start message with the current wall time.
- Performs a 2000 ms busy-wait delay through `Timer.asm`.
- Prints an end message with the current wall time.

### `Shutdown`

#### Purpose
- End interactive operation and place the machine into a safe stopped state.

#### Real-Hardware-First Contract
- On a real 386-class target, the authoritative shutdown outcome is a controlled CPU halt.
- Manual power-off by the user is expected after shutdown completes.
- Software-controlled power-off is not required for correctness on that target class.

#### Optional Environment-Specific Enhancement
- If the runtime environment supports a software power-off request, the shutdown path may attempt it before entering the final halt state.
- Emulator power-off support is a convenience feature, not the core correctness contract.

#### Current Intended Semantics
- Announce shutdown to the user.
- Optionally issue environment-specific power-off requests.
- Enter a non-returning halted state.

#### Current Implementation Notes
- `Console.asm` currently attempts Bochs/ACPI-oriented power-off port writes before halting.
- `Console.asm` currently logs `Shutdown complete.` before the final outcome is knowable.
- That wording is not the desired long-term contract and should be treated as an implementation-alignment issue, not as the authoritative shutdown meaning.

---

## Design Notes

- Console behavior should be truthful for real hardware first.
- Emulator-specific behavior may extend the command outcome, but should not redefine correctness.
- A command should not claim a stronger result than the kernel can guarantee across supported environments.

---

## Summary

- `Doc/Console.md` is the authoritative console-command behavior document.
- `Shutdown` is defined primarily as a controlled halt suitable for real 386-class hardware.
- Manual power-off after shutdown is acceptable and expected on real hardware.
- Emulator power-off is optional environment-specific convenience.
