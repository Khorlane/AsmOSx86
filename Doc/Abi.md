# 🧷 ABI + Calling Conventions (AsmOSx86)

This document defines the authoritative ABI (Application Binary Interface) for AsmOSx86 kernel modules.
The ABI specifies the formal rules and conventions for how modules interact and call each other at the binary level.

---

## 1) CPU / Mode

- 32-bit protected mode
- 386-safe (no 64-bit instructions)
- No BIOS usage in kernel code
- No interrupts required for core services (polled designs)

---

## 2) Register Discipline (LOCKED-IN)

Unless a routine explicitly documents otherwise:

- **All exported (public) routines preserve all general registers**
  using `pusha` / `popa`.
- If a routine returns a value in a register that would be clobbered
  by `popa`, it must **stage** that value in memory and reload it
  after `popa`.

Example pattern:
- compute return in EAX/EDX
- store to `Ret*` variables
- `popa`
- reload EAX/EDX from `Ret*`
- `ret`

---

## 3) Parameter Passing

Default: **inputs are passed in registers**, documented per routine.

Common patterns:
- `EBX = address of String` for printing (`PutStr`, `CnPrint`)
- `EAX = value` for numeric inputs (example: `TimerSpinDelayMs`)

### 3.1 Reading the caller’s original registers after `pusha`

Some routines may read the caller’s original EAX/ECX/etc from the stack
after `pusha`.

This is allowed **only if** documented in that routine’s contract.

Reminder:
`pusha` pushes 8 dwords (32 bytes) in this order:
EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI

So inside the callee after `pusha`:
- caller’s original **EAX** is at `[esp+28]`

(Used by `FloppySetDrive`.)

---

## 4) String Format (LOCKED-IN)

A “String” in AsmOSx86 is:

- 2-byte little-endian length word
- followed by payload bytes

Length word is the payload length in bytes.

Example:
```
String CrLf,0Dh,0Ah
; dw length=2, db 0Dh,0Ah
```

`PutStr`:
- reads the length word
- prints payload bytes
- interprets CR and LF as control characters (CR resets Col, LF increments Row)

See also: `Doc/String.md`

---

## 5) Global Working Storage

Modules may rely on kernel-owned globals (KernelCtx, buffers, strings),
but that dependency must be documented either:
- in the module header “Requires:” block, or
- in `Doc/KernelCtx.md`.

Hidden coupling is forbidden.
