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

- Registers are scratch working state, not a trusted interface contract.
- Callers must not assume an incoming register contains meaningful data.
- Callees do not promise to preserve general registers.
- If a routine needs stable input or output, that contract must be expressed through documented memory locations.

This project prefers memory-based contracts over register-based contracts.

---

## 3) Parameter Passing

Default: **inputs and outputs are passed through documented memory state**.

Common patterns:
- module-local variables owned by the subsystem
- shared state such as `KernelCtx` when explicitly applicable
- documented string pointers or working buffers stored in memory

Register-based inputs or outputs are exceptions and must be explicitly documented by the routine that uses them.

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
