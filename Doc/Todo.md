# ToDo

[x] TD-001 Align `Doc/String.md` with the actual kernel `Str` layout and `String` macro behavior.
[x] TD-002 Align `Doc/Abi.md` string-format section with the actual kernel `Str` length semantics.
[x] TD-003 Reconcile `Doc/Abi.md` register-preservation rules with the current exported kernel routines.
[x] TD-004 Reconcile `Doc/Initialize.md` with the current kernel initialization flow in `Kernel.asm`.
[x] TD-005 Reconcile `Doc/Initialize.md` lazy-init rules with the current `Time.asm` behavior.
[x] TD-006 Update `Doc/KernelCtx.md` to match current module-local globals and current kernel-owned shared state.
[x] TD-007 Update `Doc/Utility.md` to match the routines that actually exist in `Utility.asm`.
[ ] TD-008 Replace the `Doc/CallGraph.md` placeholder with a current call graph or a scoped initial version.
[ ] TD-009 Decide whether wall time should remain lazily initialized or be explicitly initialized during kernel boot.
[ ] TD-010 Refactor `Uptime.asm` to follow the project memory-based interface model instead of register-based contracts and `pusha`/`popa` preservation.
[ ] TD-011 Resolve the wall-time midnight rollover inconsistency so `Time.asm` keeps date and time coherent between RTC resyncs.
[x] TD-012 Reconcile `Doc/TimeDesign.md` RTC-read guidance with the actual `TimeReadCmos` implementation, or strengthen the implementation to match the documented double-read approach.
[x] TD-013 Update `Doc/Time.md` to reflect the full wall-time callable surface, including date formatting/printing routines, or explicitly mark those routines as internal.
[x] TD-014 Clarify in `Doc/TimeDesign.md` that the current wall-time model interpolates time-of-day between resyncs but does not currently advance the calendar date independently of RTC resync.
[ ] TD-015 Align `Time.asm` and `Timer.asm` code comments with the actual implementation and current time architecture docs.
[x] TD-016 Decide how to remove or formalize `Uptime.asm`'s dependency on `TimePut2Dec` so low-level formatting ownership is explicit.
