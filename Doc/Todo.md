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
