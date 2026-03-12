# Kernel Context

This document describes `KernelCtx` as it exists today and the role it is intended to play later.

---

## Overview

`KernelCtx` is defined in `Kernel.asm`.

At present, it should be viewed as an early kernel-owned context/state block, not as the active owner of all subsystem runtime state.

Its longer-term purpose is to support task-switching and related saved-context work.

---

## Current Reality

Most active subsystem state in the current kernel does **not** live in `KernelCtx`.

Instead, subsystem state is currently owned locally by the module that uses it. Examples:
- `Console.asm`
- `Keyboard.asm`
- `Video.asm`
- `Timer.asm`
- `Time.asm`

This is the current source reality and should not be obscured by documentation.

---

## Current `KernelCtx` Block

Defined in `Kernel.asm` under `KernelCtx:`.

Current fields:
- `Char`
- `Byte1`
- `KbChar`
- `ColorBack`
- `ColorFore`
- `ColorAttr`
- `Row`
- `Col`
- `Byte2`
- `Byte4`
- `TvRowOfs`
- `VidAdr`

These fields exist in the source, but they should not be interpreted as the current ownership model for the active kernel subsystems.

Some are legacy scratch/state fields and may later be repurposed, reduced, or replaced as the task/context model becomes more explicit.

---

## Alignment Rule

`KernelCtxSz` must be divisible by 4.

This is enforced in `Kernel.asm` and exists to preserve compatibility with future `rep movsd` style context copy operations.

---

## Intended Direction

`KernelCtx` is intended to evolve into a shared kernel context block used for:
- saved execution context
- task-switch related state
- other kernel-owned context data that benefits from block copy / structured save-restore behavior

That design is not fully fleshed out yet.

Until it is, documentation must distinguish between:
- the current implementation
- the intended architectural direction

---

## Ownership Notes

Current ownership model:
- `Kernel.asm` owns the `KernelCtx` definition
- active subsystem runtime state is mostly module-local
- strings, tables, and working storage are generally owned by the module that uses them

This means `KernelCtx` should not currently be described as the central home for shared strings, keyboard tables, or all mutable kernel state.

---

## Summary

- `KernelCtx` exists today in `Kernel.asm`
- it is not yet the active center of subsystem state ownership
- its likely long-term role is task/context switching support
- documentation must reflect both the current code and that intended direction without conflating them
