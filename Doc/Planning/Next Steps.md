# Next Steps

These are near-term implementation notes for AsmOSx86. They intentionally keep
hardware interrupts and preemptive scheduling near the bottom of the list for
now.

## Guiding Bias

Keep changes small, concrete, and useful immediately.

Prefer work that:

- strengthens existing boundaries
- makes current scaffolding real
- keeps `Fs.asm`, `Task.asm`, `Kc.asm`, `Paging.asm`, and `Config.asm` ready for
  later growth
- avoids large rewrites
- keeps interrupts out of the critical path for now

## Current Checkpoint

Storage and boot:

```text
Boot.asm is the single-stage boot loader.
The floppy uses the ASMF manifest layout, not FAT12.
BuildCopy.ps1 writes KERNEL.BIN, PROG*.BIN, and DATA.TXT into the image.
BuildCopy.ps1 also reserves LOG.TXT for the kernel-owned console mirror.
```

Device and filesystem path:

```text
Config.asm owns the static DevRegistry.
DevRegistryFloppyA has FloppyReadSectorTo in its read slot.
Fs.asm routes sector reads through DevReadSector and DevFindById.
Fs.asm routes the internal LOG.TXT writer through DevWriteSector.
Floppy A: is still the only working block device.
FsOpen/FsRead/FsClose provide the current read-only file service.
LOG.TXT is the only current kernel-owned write path.
```

User program launch:

```text
Run exists as:
  run <program> [-- <arg>] [| <program> [-- <arg>]] [| <program> [-- <arg>]]
Run loads 1..3 named programs, creates task slots 1..N, copies each optional
argument into that task's startup argument area, starts cooperative dispatch only
after all requested programs are loaded, prints task exit information, and
returns to the console.
Run rejects malformed launch specs and reports the task slot and status when a
program load fails.
```

Console log mirror:

```text
The kernel clears LOG.TXT during startup.
VdPutStr mirrors console output into LOG.TXT after logging is initialized.
After Bochs shuts down, Scripts\ExtractFile.ps1 LOG.TXT extracts the test log.
```

Current userland smoke tests:

```text
run prog4.bin
  opens DATA.TXT
  reads DATA.TXT
  prints through KcVdWriteStr
  closes DATA.TXT
  exits 0000

run prog4.bin -- bad
  runs the normal DATA.TXT path
  deliberately passes a bad pointer to KcVdWriteStr
  expects KC_STATUS_BAD_ARG
  exits 0042 when validation works

run prog4.bin -- bad-print
  explicit alias for the same bad KcVdWriteStr pointer validation path
  exits 0042 when validation works

run prog4.bin -- bad-open
  runs the normal DATA.TXT path
  deliberately passes a bad filename pointer to KcFsOpen
  expects KC_STATUS_BAD_ARG
  exits 0043 when validation works

run prog4.bin -- bad-read
  runs the normal DATA.TXT path
  deliberately passes a bad destination pointer to KcFsRead
  expects KC_STATUS_BAD_ARG
  exits 0044 when validation works

run prog4.bin -- bad-zero-call
  runs the normal DATA.TXT path
  deliberately requests Kc call number 0
  expects KC_STATUS_INVALID
  exits 0045 when validation works

run prog4.bin -- bad-call-number
  runs the normal DATA.TXT path
  deliberately requests an unknown Kc call number
  expects KC_STATUS_INVALID
  exits 0046 when validation works

run prog4.bin -- sleep
  runs the normal DATA.TXT path
  calls KcTmSleep
  wakes through cooperative scheduler checks
  exits 0007

run prog4.bin -- key
  runs the normal DATA.TXT path
  calls KcKbRead
  blocks until a key event is available
  exits 0047 when the user task resumes

run prog4.bin -- int80
  runs the normal DATA.TXT path
  calls KcVdWriteStr through int 80h
  exits 0080 when the software interrupt path works

run prog4.bin -- cpl
  runs the normal DATA.TXT path
  exits with the user code selector
  expects 001B when the task is actually running in ring 3

run prog4.bin -- info
  runs the normal DATA.TXT path
  asks KcTsGetInfo for current task identity and mode
  exits 0101 when task 1 reports user mode

run prog4.bin -- priv
  runs the normal DATA.TXT path
  deliberately executes privileged CLI from user code
  expects the kernel to terminate the task with 0F0D

run prog4.bin -- mem
  runs the normal DATA.TXT path
  deliberately reads supervisor-only kernel memory from user code
  expects the kernel to terminate the task with 0F0E

run prog4.bin -- load
  runs the normal DATA.TXT path
  deliberately requests KcTsLoadProgram from user code
  expects KC_STATUS_BAD_ARG
  exits 0048 when program loading is kernel-owned

run prog1.bin | prog2.bin | prog3.bin
  loads three named programs from one console command line
  proves file-loaded multi-task cooperative scheduling without hard-coded names
  prints task 1..3 exit codes

run prog4.bin -- sleep | prog1.bin | prog4.bin -- bad
  loads mixed user programs with independent startup arguments
  runs them together through the cooperative scheduler
```

Prog4 mode summary:

```text
mode              proof                                      exit
normal            file open/read/print/close                 0000
bad               bad KcVdWriteStr pointer                  0042
bad-print         bad KcVdWriteStr pointer                  0042
bad-open          bad KcFsOpen filename pointer             0043
bad-read          bad KcFsRead destination pointer          0044
bad-zero-call     KcValidate rejects call number 0          0045
bad-call-number   KcLookup rejects unknown call number      0046
sleep             KcTmSleep blocks and wakes cooperatively  0007
key               KcKbRead blocks until keyboard input      0047
int80             KcVdWriteStr through int 80h              0080
cpl               user CS selector proof                    001B
info              KcTsGetInfo task/mode proof               0101
priv              privileged instruction fault              0F0D
mem               supervisor-only kernel memory fault       0F0E
load              user KcTsLoadProgram denied               0048
```

Kernel-call boundary:

```text
KcDispatch rejects call number zero.
KcLookup rejects unknown service numbers.
KcUserDispatch requires a current task and KcBlock before dispatching.
File and video Kc handlers reject basic null/zero arguments.
TaskValidateUserRange checks user-provided ranges against the user virtual
program area and the KcBlock page.
KcVdWriteStr and KcFsOpen validate full Str ranges for user-originated calls.
KcFsRead validates destination buffer ranges for user-originated calls.
Prog4 has denial modes for bad print, bad open, and bad read user pointers.
Prog4 has dispatch denial modes for zero and unknown Kc call numbers.
KcKbRead blocks user tasks until a keyboard event is available.
Kc interrupt vector 80h handles userland service calls.
Yield, exit, sleep, and keyboard-read calls use interrupt-aware task switching.
KcTsLoadProgram is kernel-originated only; userland Run requests still go
through the console.
KcTsGetInfo returns the current task index and user-mode tag.
Legacy gateway address 00100005h is reserved and denied.
```

Tasking and scheduling:

```text
The scheduler is cooperative.
Task states include Free, Ready, Running, Blocked, and Exited.
TaskSetReady, TaskBlock, and TaskWake exist.
Task records contain future user-mode EIP, ESP, CS, DS, SS, and EFLAGS fields.
Loaded user tasks have prepared iretd frames.
TaskEnterUserMode validates its frame and enters ring 3 with iretd.
Task records carry a kernel/user execution-mode tag.
TaskIsUserMode exposes that tag for fault/transition code.
KcTmSleep is the first real cooperative blocking service.
TaskYield wakes blocked sleep tasks whose deadlines have expired.
Timer wake checks happen only when the cooperative scheduler runs.
User programs enter the kernel with int 80h.
Interrupt-aware yield, exit, sleep, and keyboard-read paths save/restore
ring 3 frames.
```

Paging:

```text
Paging is enabled.
User programs share a fixed virtual base.
Ring 3 GDT code/data selectors are defined:
  USER_CODE_SEL
  USER_DATA_SEL
Loaded user tasks enter with USER_CODE_SEL/USER_DATA_SEL.
TSS selector and storage are defined:
  TSS_SEL
  Tss32
TR is loaded during kernel startup.
TSS ESP0 tracks the selected task's kernel stack top.
The selected user task's stack page is mapped user-accessible.
Fault IDT gates are installed for:
  general protection fault vector 13
  page fault vector 14
Kernel faults halt forever.
User faults terminate the current task and return to the scheduler.
Fault handlers classify user faults from the CPU-pushed CS selector.
User fault diagnostics print vector, CS, EIP, and CR2 before task exit.
Paging flag names express intent:
  PG_KERNEL_FLAGS
  PG_USER_FLAGS
  PG_KCBLOCK_FLAGS
Future page flags are named separately:
  PG_FUTURE_KERNEL_FLAGS
  PG_FUTURE_USER_FLAGS
  PG_FUTURE_KCBLOCK_FLAGS
Loaded user program and KcBlock mappings are user-accessible.
Kernel identity mappings remain supervisor-only.
```

## Near-Term Candidates

1. Keep `Prog4` as the main userland smoke test.

```text
normal mode proves file I/O and print calls
bad mode proves user pointer validation
bad-open and bad-read prove file-service pointer validation
sleep mode proves cooperative blocking and waking
```

2. Tighten service-specific kernel-call validation as new calls appear.

```text
validate only what current callers need
keep kernel-originated KcDispatch paths working
avoid large validation frameworks for now
```

3. Add another real blocking service when useful.

```text
possible candidates:
  file/device wait
  cooperative timer sleep variants
```

4. Improve `Run` only when a caller needs it.

```text
possible future improvements:
  clearer process/session identity
  optional current-working-device or file context
```

5. Keep hardening privilege separation.

```text
ring 3 GDT selectors are active for loaded user tasks
TSS selector/storage are named and TR is loaded
ring-transition stack pointer tracks the selected task
user-mode task frame fields are consumed by TaskEnterUserMode
iretd frames are prepared and consumed by the scheduler
task execution-mode tags classify faults
Kc interrupt gate handles user service calls
fault handlers terminate user tasks and halt on kernel faults
keep kernel mappings supervisor-only
keep tightening user pointer validation
keep adding denial tests for privileged operations and invalid memory
```

## Standard Smoke-Test Loop

Run a test session in Bochs, shut down AsmOSx86 cleanly, close Bochs, then
extract the captured console log:

```powershell
Scripts\ExtractFile.ps1 LOG.TXT
```

Use `Extracted\LOG.TXT` as the test artifact.

## Preferred Next Move

Run the three `Prog4` modes as a regular smoke test before the next code step:

```text
run prog4.bin
run prog4.bin -- bad
run prog4.bin -- bad-open
run prog4.bin -- bad-read
run prog4.bin -- bad-zero-call
run prog4.bin -- bad-call-number
run prog4.bin -- sleep
run prog4.bin -- key
run prog4.bin -- cpl
run prog4.bin -- info
run prog4.bin -- priv
run prog4.bin -- mem
run prog4.bin -- load
run prog1.bin | prog2.bin | prog3.bin
run prog4.bin -- sleep | prog1.bin | prog4.bin -- bad
```

After that, choose the next feature based on what feels most useful:

```text
another blocking service
more filesystem behavior
more precise kernel-call validation
```
