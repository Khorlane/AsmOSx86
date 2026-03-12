# Strings

## Overview

AsmOSx86 uses two string formats at the project level:

- `CStr`: NUL-terminated byte string
- `Str`: length-prefixed string used by the kernel

This split is intentional.

---

## CStr

### Layout
`db 'h','e','l','l','o',0`

### Scope
- Used by boot-stage code such as `Boot1.asm` and `Boot2.asm`
- Fits BIOS-style print routines that scan for a trailing zero

### Notes
- Not part of the kernel string ABI
- Kernel routines must not assume CStr input unless explicitly documented

---

## Str

### Layout
`Str = [u16 len][bytes...]`

Example payload `"ABC"`:
```asm
dw 3
db 'A','B','C'
```

### Critical definition (LOCKED-IN)
The `u16` length is the payload length in bytes.

So:
- `len = number of payload bytes`
- The 2-byte length field is not included in `len`

This matches the current `String` macro and current kernel consumers.

---

## The `String` Macro

The canonical way to define a kernel `Str` at assembly time is the `String` macro in `Macros.asm`.

It:
- writes the payload length as a `dw`
- emits the payload bytes immediately after the length field

All kernel `Str` constants should be created with this macro, or must exactly match its layout.

---

## Kernel Usage

Kernel routines operate on `Str`, not CStr.

Examples:
- `VdPutStr` reads the leading `u16` as payload length
- `StrCopy` copies the length word plus payload
- `StrTrim` updates the stored payload length in place

The payload is not NUL-terminated and must not be treated as though it were.

---

## Standard Rules

### Do
- Use `Str` for kernel-owned strings
- Treat the `u16` length as authoritative
- Keep boot-stage `CStr` usage separate from kernel `Str` usage

### Don't
- Don’t pass a CStr to a kernel routine that expects `Str`
- Don’t assume a `Str` payload ends with NUL
- Don’t store total object size in the `Str` length field

---

## Quick Reference

| Type | Terminator | Length storage | Length meaning |
|------|------------|----------------|----------------|
| CStr | NUL (0)    | none           | inferred by scan |
| Str  | none       | `u16` prefix   | payload bytes |
