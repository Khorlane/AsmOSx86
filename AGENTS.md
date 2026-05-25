## AsmOSx86 ABI and Register Rules

AsmOSx86 uses a memory-contract ABI, not a normal register-parameter ABI.

All routines must follow this pattern:

1. Read input parameters from named global variables.
2. Load registers only as local scratch/work registers.
3. Perform the routine body.
4. Store results back into named global variables before returning.
5. Return with `ret`.

Registers are caller-volatile and callee-volatile. No routine may depend on any register preserving a value across `call`.

Do not define public routine contracts like:

- `EAX = input`
- `EBX = pointer`
- `EDX:EAX = return value`

Instead, define contracts like:

- `TimerInMs dd 0`
- `TimerOutTicksLo dd 0`
- `TimerOutTicksHi dd 0`

`push`, `pop`, `pusha`, and `popa` are forbidden in kernel routines unless explicitly approved for a special low-level transition case.

If a value must survive a call, store it in a named global variable before the call and reload it afterward.