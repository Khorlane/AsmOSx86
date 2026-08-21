# Next Steps

These are near-term implementation notes for AsmOSx86. They intentionally keep
hardware interrupts, ring 3, and preemptive scheduling near the bottom of the
list for now.

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
```

Device and filesystem path:

```text
Config.asm owns the static DevRegistry.
DevRegistryFloppyA has FloppyReadSectorTo in its read slot.
Fs.asm routes sector reads through DevReadSector and DevFindById.
Floppy A: is still the only working block device.
FsOpen/FsRead/FsClose provide the current read-only file service.
```

User program launch:

```text
Run exists as: run <program> <optional argument text>
Run loads the named program, creates task slot 1, starts cooperative dispatch,
prints the task exit code, and returns to the console.
Run copies optional text after the filename into the task startup argument area.
```

Current userland smoke tests:

```text
run prog4.bin
  opens DATA.TXT
  reads DATA.TXT
  prints through KcVdWriteStr
  closes DATA.TXT
  exits 0000

run prog4.bin bad
  runs the normal DATA.TXT path
  deliberately passes a bad pointer to KcVdWriteStr
  expects KC_STATUS_BAD_ARG
  exits 0042 when validation works

run prog4.bin sleep
  runs the normal DATA.TXT path
  calls KcTmSleep
  wakes through cooperative scheduler checks
  exits 0007
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
```

Tasking and scheduling:

```text
The scheduler is cooperative.
Task states include Free, Ready, Running, Blocked, and Exited.
TaskSetReady, TaskBlock, and TaskWake exist.
KcTmSleep is the first real cooperative blocking service.
TaskYield wakes blocked sleep tasks whose deadlines have expired.
Timer wake checks happen only when the cooperative scheduler runs.
```

Paging:

```text
Paging is enabled.
User programs share a fixed virtual base.
Paging flag names express intent:
  PG_KERNEL_FLAGS
  PG_USER_FLAGS
  PG_KCBLOCK_FLAGS
The actual bits still remain present+writable for now.
Ring 3 and user/supervisor enforcement are future work.
```

## Near-Term Candidates

1. Keep `Prog4` as the main userland smoke test.

```text
normal mode proves file I/O and print calls
bad mode proves user pointer validation
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
  keyboard wait
  file/device wait
  cooperative timer sleep variants
```

4. Improve `Run` only when a caller needs it.

```text
possible future improvements:
  multiple user tasks launched from console
  clearer process/session identity
  richer startup arguments
  optional current-working-device or file context
```

5. Keep paging ready for later privilege separation.

```text
leave flag bits unchanged until ring 3 work begins
later add the x86 user/supervisor bit to user-facing mappings
keep kernel mappings supervisor-only
```

## Preferred Next Move

Run the three `Prog4` modes as a regular smoke test before the next code step:

```text
run prog4.bin
run prog4.bin bad
run prog4.bin sleep
```

After that, choose the next feature based on what feels most useful:

```text
another blocking service
more filesystem behavior
multiple console-launched user tasks
more precise kernel-call validation
```
