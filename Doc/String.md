# Doc/Strings.md

## Overview

AsmOSx86 uses **two string formats**:

- **CStr**: C-style, **NUL-terminated** byte string.
- **Str**: OS-native, **length-prefixed** string produced by the `String` macro and consumed by `PutStr`.

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
- Avoid printing directly once converted workflows exist (prefer conversion to Str).

---

## Str (length-prefixed OS string)

### Layout
Str starts with a 2-byte word length followed by payload bytes:
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
String `"ABC"` in Str format:
- Total length = 2 + 3 = 5

```
dw 5
db 'A','B','C'
```

---

## The `String` macro

The canonical way to define an Str at assembly time:

- Writes a `dw` length that includes the `dw` itself.
- Emits the payload bytes immediately after the length field.

All Str constants should be created via this macro (or must exactly match its layout).

---

## Printing: `PutStr`

`PutStr` expects an **Str** pointer in `EBX`.

Key behavior:
- Reads `dw length` (total bytes)
- Subtracts 2 to get payload length
- Prints exactly that many bytes
- Payload **is not NUL-terminated** and must not be treated as such

---

## Conversion: `CStrToStr`

### Purpose
Convert a CStr (NUL-terminated) into an Str (length-prefixed).

### Contract
- Input:
  - `ESI` = CStr pointer
  - `EDI` = Str destination pointer
- Output:
  - Copies up to `STR_MAX` payload bytes
  - Writes `dw total_length` where:
    - `total_length = payload_length`
- Policy:
  - No padding / no space-fill
  - Truncates at `STR_MAX`
  - Consumers must trust the length

### Capacity convention
`STR_MAX` is the **maximum payload length** (bytes after the 2-byte length).

---

## Standard rules (do this, not that)

### ✅ Do
- Use **CStr** for editable buffers (keyboard input, parsing scratch).
- Convert to **Str** when passing strings into OS routines like `PutStr`.
- Treat the Str length as **authoritative** (never require padding).

### ❌ Don’t
- Don’t pass a CStr directly to `PutStr`.
- Don’t assume Str payload is NUL-terminated.
- Don’t store payload length in the Str `dw`. It must be **total payload bytes**.

---

## Naming standards

- **CStr**: NUL-terminated string
- **Str**: length-prefixed OS-native string (length includes the 2-byte prefix)
- **STR_MAX**: maximum payload length (excludes the 2-byte length word)

---

## Quick reference

| Type | Terminator | Length storage | Length meaning |
|------|------------|----------------|----------------|
| CStr | NUL (0)    | none           | inferred by scan |
| Str  | none       | `dw` prefix    | total bytes (= payload length) |

