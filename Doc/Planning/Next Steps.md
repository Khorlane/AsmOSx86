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
DevReadSector still effectively knows it is reading from floppy A:.
```

Next step:

```text
add a small device lookup/routing path
resolve selected block device through DevRegistry
keep floppy A: as the only working block device
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

Next step:

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
```

Next step:

```text
validate KcNumber
validate current task exists
validate current task has a KcBlock
validate user pointers are inside expected user virtual ranges
validate read/write buffer ranges before services use them
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

## Preferred First Move

Start with the device registry read path:

```text
make DevRegistryFloppyA's read slot point to FloppyReadSectorTo
make DevReadSector call through that slot
keep the rest of the system behavior unchanged
```

This is small, concrete, and directly supports the current filesystem/device
layering direction.
