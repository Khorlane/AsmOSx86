# AsmOSx86 Cross-File Call Map

This document is a curated call map for **cross-source-file calls** in AsmOSx86.

Its purpose is to answer:
- which routines in one source file are called from another source file
- which source files depend on which subsystems

This document does **not** try to list every intra-file helper call.

Use this file for:
- subsystem coupling
- reverse caller lookup across source-file boundaries
- high-level dependency review before refactors

Use the source files themselves for full local control flow.

---

## Scope Rules

- Focus on calls that cross `.asm` source-file boundaries.
- Group by **callee file** so dependency targets are easy to inspect.
- Include indirect cross-file command-handler reachability when it is architecturally important.
- Omit purely local helper-to-helper calls within one file unless needed for context.

---

## Entry Roots

- `Kernel.asm`
  - `Stage3`
    - boot/root entry for the kernel
  - `MainLoop`
    - calls `Console.asm` -> `Console`

These are useful starting points, but the main purpose of this document is the cross-file map below.

---

## Cross-File Calls By Callee File

### `Console.asm`

- `CnInit`
  - called by:
    - `Kernel.asm` -> `Stage3`

- `Console`
  - called by:
    - `Kernel.asm` -> `MainLoop`

### `Keyboard.asm`

- `KbInit`
  - called by:
    - `Kernel.asm` -> `Stage3`

- `KbGetKey`
  - called by:
    - `Console.asm` -> `CnReadLine`

### `Time.asm`

- `TimeDtPrint`
  - called by:
    - `Console.asm` -> `CnLogIt`
    - `Console.asm` -> `CnDoCmdDate`

- `TimeTmPrint`
  - called by:
    - `Console.asm` -> `CnLogIt`
    - `Console.asm` -> `CnDoCmdDelay`
    - `Console.asm` -> `CnDoCmdTime`

### `Timer.asm`

- `TimerInit`
  - called by:
    - `Kernel.asm` -> `Stage3`

- `TimerNowTicks`
  - called by:
    - `Console.asm` -> `CnReadLine`
    - `Time.asm`    -> `TimeNow`
    - `Time.asm`    -> `TimeSync`
    - `Uptime.asm`  -> `UptimeInit`
    - `Uptime.asm`  -> `UptimeNow`
    - `Uptime.asm`  -> `UptimePrint`

- `TimerSpinDelayMs`
  - called by:
    - `Console.asm` -> `CnDoCmdDelay`
    - `Console.asm` -> `CnDoCmdShutdown`

### `Utility.asm`

- `StrTrim`
  - called by:
    - `Console.asm` -> `Console`

- `Put2Dec`
  - called by:
    - `Time.asm`   -> `TimeFmtHms`
    - `Time.asm`   -> `TimeFmtYmd`
    - `Uptime.asm` -> `UptimeFmtYdhms`

### `Video.asm`

- `VdInit`
  - called by:
    - `Kernel.asm` -> `Stage3`

- `VdSetColorAttr`
  - called by:
    - `Console.asm` -> `CnInit`

- `VdClear`
  - called by:
    - `Console.asm` -> `CnInit`

- `VdSetCursor`
  - called by:
    - `Console.asm` -> `CnInit`

- `VdPutStr`
  - called by:
    - `Console.asm` -> `CnCrLf`
    - `Console.asm` -> `CnSpace`
    - `Console.asm` -> `CnLogIt`
    - `Console.asm` -> `CnDoCmdDelay`
    - `Console.asm` -> `CnDoCmdHelp`
    - `Time.asm`    -> `TimeTmPrint`
    - `Time.asm`    -> `TimeDtPrint`

- `VdInClearLine`
  - called by:
    - `Console.asm` -> `CnReadLine`

- `VdInPutChar`
  - called by:
    - `Console.asm` -> `CnReadLine`

- `VdInBackspaceVisual`
  - called by:
    - `Console.asm` -> `CnReadLine`

---

## Indirect Cross-File Reachability

### Console Command Handlers

`Console.asm` dispatches commands through `CnCmdTable`, so handlers are reached indirectly through `CnCmdDispatch`.

Important indirect handler entries:
- `Console.asm` -> `CnDoCmdDate`
- `Console.asm` -> `CnDoCmdDelay`
- `Console.asm` -> `CnDoCmdHelp`
- `Console.asm` -> `CnDoCmdShutdown`
- `Console.asm` -> `CnDoCmdTime`

This matters because command handlers may appear to have no direct textual caller other than the table-driven dispatch path.

---

## Dependency Summary

- `Kernel.asm` depends directly on:
  - `Console.asm`
  - `Keyboard.asm`
  - `Timer.asm`
  - `Video.asm`

- `Console.asm` depends directly on:
  - `Keyboard.asm`
  - `Time.asm`
  - `Timer.asm`
  - `Utility.asm`
  - `Video.asm`

- `Time.asm` depends directly on:
  - `Timer.asm`
  - `Utility.asm`
  - `Video.asm`

- `Uptime.asm` depends directly on:
  - `Timer.asm`
  - `Utility.asm`
  - `Console.asm`

---

## Notes

- This document is intentionally scoped to cross-file relationships because those are the highest-signal architectural couplings in the current codebase.
- If a future subsystem adds many new exported routines, update this file by recording only the meaningful cross-file calls rather than every local helper edge.
