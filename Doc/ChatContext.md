# Chat Context

Purpose: keep Codex and the project owner aligned across chat sessions.

Use:
- Update this file when a project-level decision changes.
- Keep entries short and concrete.
- Prefer facts and active decisions over speculation.
- Treat this as resume context, not full documentation.

## Current Source Of Truth
- Kernel source of truth: `Kernel.asm` plus the separately included module files.
- `Kernel.All.asm` is not part of the active workflow and should be ignored.
- `Floppy.asm` contains partial standalone code but is not part of the active workflow and is not ready for inclusion.
- `Doc/Todo.md` is the active tracker for doc/code alignment and follow-up design items.

## Current Architecture Notes
- `Boot1.asm` and `Boot2.asm` use null-terminated BIOS-style strings.
- Kernel code uses `Str = [u16 len][bytes...]` as the internal string ABI.
- The boot-stage string format difference is intentional.
- Active kernel interfaces prefer documented memory-based contracts over register-based contracts.
- Registers are treated as scratch unless a routine explicitly documents otherwise.
- `Doc/Time.md` is the authoritative current time contract; `Doc/TimeDesign.md` preserves design rationale and decision history.
- `Doc/Console.md` is the authoritative console-command behavior doc; shutdown semantics are defined real-hardware-first, with controlled halt as the core contract.
- `Put2Dec` is now owned by `Utility.asm` as a generic formatting helper instead of `Time.asm`.

## Collaboration Notes
- Review for alignment is useful even when no fixes are needed.
- Short confirmations of intentional design differences are worth recording here.
- If a file is declared stub / inactive / deleted from workflow, record it here.

## Active Working Agreements
- Keep kernel-facing comments and docs consistent with current source behavior.
- Treat project consistency as important, even when subsystem boundaries differ.
- When docs drift from code, update the docs to match current behavior unless a deliberate refactor is planned.
- Future-state ideas should be documented as intended direction, not described as current implementation.
- Prefer repo-level tool/config policy over machine-local defaults when environment drift has already caused issues.

## Next Resume Checklist
- Confirm which files are active source of truth.
- Check whether any documented assumptions changed since the last session.
- Review this file before making architectural assumptions.
- Check `Doc/Todo.md` before starting new cleanup work.

## Session Notes
- 2026-03-12: `Kernel.All.asm` explicitly removed from consideration.
- 2026-03-12: `Floppy.asm` marked as inactive/non-integrated, not ready for inclusion.
- 2026-03-12: Confirmed kernel string ABI is length-prefixed `Str`; boot loaders intentionally use null-terminated BIOS strings.
- 2026-03-12: Added `Doc/Todo.md` to track doc/code inconsistencies and follow-up design work.
- 2026-03-12: Completed `TD-001` and `TD-002`; `Doc/String.md` and the string section in `Doc/Abi.md` now match the real kernel `Str` contract.
- 2026-03-12: Completed `TD-003`; `Doc/Abi.md` now reflects the current memory-based interface model and volatile register expectations.
- 2026-03-12: Completed `TD-004` and `TD-005`; `Doc/Initialize.md` now matches the real boot sequence and current lazy wall-time initialization behavior.
- 2026-03-12: Completed `TD-006`; `Doc/KernelCtx.md` now treats `KernelCtx` as an early/future task-switch context concept rather than the active owner of subsystem state.
- 2026-03-12: Completed `TD-007`; removed stale `CStrToStr`-oriented language from `Doc/Utility.md`.
- 2026-03-12: Added `TD-009` to revisit whether wall time should stay lazily initialized or be explicitly initialized during boot.
- 2026-03-12: Added `TD-010` for future `Uptime.asm` cleanup so it follows the project memory-based interface model.
- 2026-03-13: Reviewed `Doc/Time.md`, `Doc/TimeDesign.md`, `Time.asm`, and `Timer.asm` for inconsistencies before changing behavior.
- 2026-03-13: Reworked `Doc/TimeDesign.md` into a design-record style document that preserves discussion history while clearly marking current decisions.
- 2026-03-13: Completed `TD-012`, `TD-013`, and `TD-014`; the time docs now distinguish authoritative spec vs design record, describe the current wall-time API, and explicitly document the current midnight/date limitation.
- 2026-03-13: Completed `TD-011`; `Time.asm` now advances day rollover so wall date/time stays coherent between RTC resyncs.
- 2026-03-13: Added `.gitattributes` with `* text=auto eol=lf` so line-ending behavior is defined at the repo level instead of relying on local Git defaults.
- 2026-03-13: Completed `TD-016` by moving `Put2Dec` from `Time.asm` to `Utility.asm`; `Uptime.asm` now uses the generic helper directly.
- 2026-03-13: Completed `TD-017`; standardized the repo on Bochs 3.0 by updating `AsmOSx86.bxrc` and the PowerShell run scripts, and verified that build/run succeeds with the current installation.
- 2026-03-13: Completed `TD-018`; added `Doc/Console.md` as the authoritative console-command behavior doc and defined shutdown semantics real-hardware-first, with emulator power-off treated as optional convenience.
- 2026-03-13: Completed `TD-020`; aligned `Console.asm` shutdown strings/comments with the documented real-hardware-first contract while keeping emulator power-off requests as optional pre-halt attempts.
