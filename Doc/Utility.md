# 🧰 Utility Module (Utility.asm)

This document defines the purpose, scope, and rules for **`Utility.asm`** in AsmOSx86.

`Utility.asm` exists to hold **small, reusable helper routines** that are:
- broadly useful across subsystems, and
- not owned by any single subsystem.

It is intentionally minimal and conservative.

---

## 1) Purpose

**`Utility.asm` is a neutral helper module.**

It contains routines that:
- do not touch hardware directly,
- do not implement policy,
- and do not “belong” to a specific subsystem (Console, Keyboard, Time, etc.).

Utility code should make other code **simpler and clearer**, not smarter.

---

## 2) What Belongs in Utility.asm

A routine belongs in `Utility.asm` if **all** of the following are true:

- It is **purely functional or mechanical**
- It has **no hardware I/O**
- It has **no hidden state**
- It can be reused by **multiple subsystems**
- It does **one small thing**

### Typical examples

- String conversion helpers  
  (`CStrToLStr`)
- Small formatting helpers
- Buffer manipulation helpers
- Simple math helpers that don’t belong to Timer/Time/etc.

---

## 3) What Does NOT Belong in Utility.asm

The following must **never** live in `Utility.asm`:

- Hardware access (ports, MMIO, BIOS, IRQs)
- Policy decisions (timeouts, retries, logging behavior)
- Subsystem-specific logic
- Anything that depends on:
  - Console state
  - Keyboard state
  - Time policy
  - KernelCtx internals (unless explicitly documented)

If a routine “feels like” it belongs somewhere else, it probably does.

---

## 4) ABI and Register Discipline (LOCKED-IN)

All Utility routines **must follow the global ABI**:

- Preserve all general registers (`pusha` / `popa`)
- If a return value would be clobbered by `popa`, it must be:
  - staged in memory
  - restored after `popa`

Utility routines must be **safe to call from anywhere**.

---

## 5) String Handling Rules (LOCKED-IN)

Utility routines **must respect canonical string formats**:

- **CStr** = NUL-terminated string
- **LStr** = length-prefixed OS string (`dw total_bytes`)

Utility code must:
- never assume LStr payloads are NUL-terminated
- never print directly
- never mix CStr and LStr implicitly

### Example (canonical)

`CStrToLStr`:
- Input: CStr
- Output: LStr
- No printing
- No padding
- Length is authoritative

---

## 6) Dependencies

`Utility.asm` may depend on:

- Constants (`equ`)
- Global limits (e.g. `LSTR_MAX`)
- ABI rules defined in `Doc/Abi.md`

`Utility.asm` must **not** depend on:
- Kernel initialization order
- Any subsystem being initialized
- Console, Timer, Keyboard, or Video behavior

---

## 7) Growth Rule

**Utility.asm grows slowly and deliberately.**

Before adding a routine, ask:

> “Would I be annoyed to see this here six months from now?”

If yes:
- it belongs somewhere else
- or it shouldn’t exist yet

---

## Summary (LOCKED-IN)

- `Utility.asm` is for **small, reusable helpers**
- No hardware, no policy, no subsystem ownership
- Strict ABI compliance
- Explicit string formats only
- Keep it boring on purpose