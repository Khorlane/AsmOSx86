# Next Steps

These are near-term implementation steps that fit the current AsmOSx86 direction
without pulling hardware interrupts, ring 3, or preemptive scheduling to the top
of the list.

## Guiding Bias

Keep the next changes small, concrete, and useful immediately.

Prefer work that:

- strengthens existing boundaries
- makes current scaffolding real
- keeps `Fs.asm`, `Task.asm`, `Kc.asm`, `Paging.asm`, and `Config.asm` ready for
  later growth
- avoids large rewrites
- keeps interrupts near the bottom of the list for now

## 1. Use The Device Registry For Real Routing

Current reality:

```text
Config.asm has DevRegistry records.
Fs.asm has a tiny block-device layer.
DevReadSector now resolves DevBlockDevice through DevRegistry.
Floppy A: is still the only working block device.
```

Done:

```text
DevFindById scans DevRegistry by device id.
DevReadSector uses the selected registry record.
```

Useful shape:

```text
DevFindById
DevGetBlockDevice
DevReadSector
```

Goal:

```text
filesystem asks block layer
block layer resolves device
device record identifies the backing driver
driver reads the sector
```

This makes the Advanced Device Model more real without adding a hard disk yet.

## 2. Make Device Read Slots Meaningful

Current registry records already reserve:

```text
Read entry point
Write entry point
Control entry point
```

Done:

```text
DevRegistryFloppyA.Read = FloppyReadSectorTo
DevReadSector calls through the registry read slot
```

For now, write/control can remain zero.

Goal:

```text
the block layer no longer hardcodes the floppy read routine
future hard disk support has an obvious place to plug in
```

## 3. Strengthen Kernel Call Validation

Current reality:

```text
User programs use KcUserDispatch and KcBlock by convention.
There is not yet ring 3 enforcement.
KcDispatch rejects call number zero and KcLookup rejects unknown service numbers.
KcUserDispatch requires a current task and KcBlock before dispatching.
File and video kernel-call handlers reject basic null/zero arguments.
```

Next step:

```text
validate user pointers are inside expected user virtual ranges
validate read/write buffer ranges before services use them
define useful bad-call behavior for Prog4-style privilege-boundary tests
```

Goal:

```text
kernel code starts treating user-provided data as untrusted
future ring 3 transition becomes less dramatic
```

This does not require actual ring 3 yet.

## 4. Add Explicit Task Block/Wake Helpers

Current reality:

```text
TASK_STATE_BLOCKED exists.
The scheduler currently mostly uses Ready, Running, and Exited.
```

Next step:

```text
TaskBlock
TaskWake
TaskSetReady
```

Possible later cooperative test:

```text
KcTmSleep records a wake deadline
scheduler checks deadlines when tasks yield
```

Goal:

```text
make blocked task state real before adding interrupt-driven wakeups
```

This keeps scheduling cooperative while preparing for real wait states.

## 5. Prepare Paging Permission Names

Current reality:

```text
Paging is enabled.
User programs are mapped at a shared virtual base.
Pages are not yet using user/supervisor permission separation.
```

Next step:

```text
PG_KERNEL_FLAGS
PG_USER_FLAGS
PG_SUPERVISOR_FLAGS
```

Current mappings can still remain effectively supervisor-only until ring 3 work
begins.

Goal:

```text
kernel pages are conceptually kernel-only
user program pages are conceptually user-accessible
KcBlock page is conceptually user-accessible
```

This is groundwork for privilege separation, not the enforcement step itself.

## 6. Run Command For User Programs

Current reality:

```text
UserTest loads and runs PROG1.BIN, PROG2.BIN, and PROG3.BIN through a hard-coded
test path.
Run exists as a console command shaped like: run <program>
Run loads the named program from the filesystem, creates task slot 1, runs it
through the existing cooperative scheduler, and returns to the console after
the task exits.
Prog4.asm opens DATA.TXT, reads it, prints it through KcVdWriteStr, closes it,
and exits through the kernel-call path.
```

Done:

```text
run prog4.bin
single-program task launch
open/read/print/close through real kernel service calls
clean return to the console after task exit
```

Still useful to improve:

```text
missing file handling
bad filename handling
clearer load/run status reporting
repeatable Prog4 smoke-test expectations
```

Future privilege-boundary test:

```text
Prog4 can intentionally try an illegal userland action once the kernel has
enough validation or hardware enforcement to catch it.
```

Goal:

```text
move from hard-coded user program demos toward an actual console-launched
userland session model
```

## Preferred First Move

With the first device registry routing milestone complete, continue kernel-call
validation:

```text
define user pointer range helpers
validate KcVdWriteStr string pointers
validate KcFsOpen filename pointers
validate KcFsRead destination buffer ranges
```

This keeps userland filesystem tests useful while preparing for stricter
privilege separation later.
