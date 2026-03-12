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
- `Floppy.asm` is a stub only and is not ready for inclusion.

## Current Architecture Notes
- `Boot1.asm` and `Boot2.asm` use null-terminated BIOS-style strings.
- Kernel code uses `Str = [u16 len][bytes...]` as the internal string ABI.
- The boot-stage string format difference is intentional.

## Collaboration Notes
- Review for alignment is useful even when no fixes are needed.
- Short confirmations of intentional design differences are worth recording here.
- If a file is declared stub / inactive / deleted from workflow, record it here.

## Active Working Agreements
- Keep kernel-facing comments and docs consistent with current source behavior.
- Treat project consistency as important, even when subsystem boundaries differ.

## Next Resume Checklist
- Confirm which files are active source of truth.
- Check whether any documented assumptions changed since the last session.
- Review this file before making architectural assumptions.

## Session Notes
- 2026-03-12: `Kernel.All.asm` explicitly removed from consideration.
- 2026-03-12: `Floppy.asm` marked as stub, not ready for inclusion.
- 2026-03-12: Confirmed kernel string ABI is length-prefixed `Str`; boot loaders intentionally use null-terminated BIOS strings.
