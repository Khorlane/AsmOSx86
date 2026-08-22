# Ring 3

AsmOSx86 has a working ring 3 userland path for loaded user programs.

## Current State

User programs are raw flat binaries loaded from the ASMF filesystem and mapped
at the fixed user virtual base `00200000h`.

Loaded user tasks enter through an `iretd` frame with:

```text
CS = USER_CODE_SEL = 001Bh
DS = USER_DATA_SEL = 0023h
SS = USER_DATA_SEL = 0023h
```

User programs enter the kernel through `int 80h`. The old fixed gateway address
`00100005h` is reserved and denied. Ring 3 attempts to call that address page
fault before reaching the ring 0 diagnostic guard.

## Kernel Calls

User programs exchange arguments and results through the current task's KcBlock.
`KcUserInterruptEntry` is the user/kernel entry point. `KcBlockDispatch` copies
KcBlock values into the kernel-call globals, dispatches the service, and copies
results back when the same task resumes.

Switching and blocking calls use interrupt-aware paths:

```text
KcTsYield
KcTsExit
KcTmSleep
KcKbRead
```

`KcTsLoadProgram` is kernel-originated only. Userland program loading goes
through the console `Run` command for now.

## Fault Policy

Kernel faults halt the system.

User faults terminate the current task and return to the scheduler:

```text
general protection fault -> 0F0D
page fault               -> 0F0E
```

User fault diagnostics print:

```text
fault vector
faulting CS
faulting EIP
CR2 linear address for page faults
```

## Smoke Tests

Expected ring 3 proof results:

```text
run prog4.bin -- cpl     -> 001B
run prog4.bin -- info    -> 0101
run prog4.bin -- priv    -> fault line + 0F0D
run prog4.bin -- mem     -> fault line + 0F0E
run prog4.bin -- load    -> 0048
run prog4.bin -- legacy  -> fault at 00100005 + 0F0E
run prog4.bin            -> 0000
run prog1.bin | prog2.bin | prog3.bin
run prog4.bin -- sleep | prog1.bin | prog4.bin -- bad
```

