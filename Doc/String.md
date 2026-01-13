# Doc/Strings.md

## Overview

AsmOSx86 uses **two string formats**:

- **CStr**: C-style, **NUL-terminated** byte string.
- **LStr**: OS-native, **length-prefixed** string produced by the `String` macro and consumed by `PutStr`.

This document defines the canonical rules so all modules handle strings consistently.

---

## CStr (NUL-terminated)

### Layout
`db 'h','e','l','l','o',0`

### Rules
- Ends with a **0 byte** terminator.
- Length is discovered by scanning for NUL.
- Intended for **buffers that are built/edited incrementally** (e.g., keyboard line input).

### Typical producers/consumers
- Produced by: `KbReadLine` (0-terminated line buffer)
- Avoid printing directly once converted workflows exist (prefer conversion to LStr).

---

## LStr (length-prefixed OS string)

### Layout
LStr starts with a 2-byte word length followed by payload bytes:
```
dw TotalLengthBytes
db PayloadBytes...
```

### Critical definition (LOCKED-IN)
**The `dw` length includes the 2-byte `dw` itself.**

So:
- `TotalLengthBytes = 2 + PayloadLengthBytes`

This matches:
- the `String` macro behavior (`dw %%EndStr-%1`)
- `PutStr`, which does `mov cx,[esi]` then `sub cx,2` to get payload length

### Example
String `"ABC"` in LStr format:
- Total length = 2 + 3 = 5

```
dw 5
db 'A','B','C'
```

---

## The `String` macro

The canonical way to define an LStr at assembly time:

- Writes a `dw` length that includes the `dw` itself.
- Emits the payload bytes immediately after the length field.

All LStr constants should be created via this macro (or must exactly match its layout).

---

## Printing: `PutStr`

`PutStr` expects an **LStr** pointer in `EBX`.

Key behavior:
- Reads `dw length` (total bytes)
- Subtracts 2 to get payload length
- Prints exactly that many bytes
- Payload **is not NUL-terminated** and must not be treated as such

---

## Conversion: `CStrToLStr`

### Purpose
Convert a CStr (NUL-terminated) into an LStr (length-prefixed).

### Contract
- Input:
  - `ESI` = CStr pointer
  - `EDI` = LStr destination pointer
- Output:
  - Copies up to `LSTR_MAX` payload bytes
  - Writes `dw total_length` where:
    - `total_length = 2 + payload_length`
- Policy:
  - No padding / no space-fill
  - Truncates at `LSTR_MAX`
  - Consumers must trust the length

### Capacity convention
`LSTR_MAX` is the **payload capacity** (bytes after the 2-byte length).

---

## Standard rules (do this, not that)

### ✅ Do
- Use **CStr** for editable buffers (keyboard input, parsing scratch).
- Convert to **LStr** when passing strings into OS routines like `PutStr`.
- Treat the LStr length as **authoritative** (never require padding).

### ❌ Don’t
- Don’t pass a CStr directly to `PutStr`.
- Don’t assume LStr payload is NUL-terminated.
- Don’t store payload length in the LStr `dw`. It must be **total bytes**.

---

## Naming standards

- **CStr**: NUL-terminated string
- **LStr**: length-prefixed OS-native string (length includes the 2-byte prefix)
- **LSTR_MAX**: payload capacity (excludes the 2-byte length word)

---

## Quick reference

| Type | Terminator | Length storage | Length meaning |
|------|------------|----------------|----------------|
| CStr | NUL (0)    | none           | inferred by scan |
| LStr | none       | `dw` prefix    | total bytes (2 + payload) |

