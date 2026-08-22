# Privilege Policy

## Current Status

Basic user/kernel privilege separation through ring 3 is complete enough to be
treated as current AsmOSx86 architecture, not future planning.

The current implementation is documented in `Doc/Design.md` under:

```text
Current Ring 3 Userland
Kernel Call Interface
Kernel Call Communication Area
```

Current completed foundation:

```text
kernel runs in ring 0
loaded user programs run in ring 3
user programs enter kernel services through int 80h
kernel identity mappings are supervisor-only
user program pages and KcBlock pages are user-accessible
user #GP terminates the task with 0F0D
user #PF terminates the task with 0F0E
KcTsLoadProgram is kernel-originated only
tasks carry a TASK_AUTH_* authority value
Run can launch trusted/system ring 3 test tasks through launch prefixes
KcMmGetMemory and KcMmFreeMemory are real trusted-only page services
trusted FreeMemory rejects bad pointer arguments after passing the policy gate
legacy gateway address 00100005h is denied
STARTUP.TXT can exercise privilege smoke tests through ordinary console commands
```

That means the basic enforcement milestone is done.

## Remaining Planning Area

The remaining topic is not "can AsmOSx86 run ring 3 user programs?".

The remaining topic is:

```text
What authority should different userland tasks have?
```

In other words:

```text
ring 3 enforcement: done
first privilege policy gate: done
trusted memory service enforcement: done
broader privilege policy model: future
```

## Future Userland Authority Levels

AsmOSx86 may eventually distinguish between ordinary user programs and trusted
or system user programs.

Conceptual authority levels:

```text
normal user task
  ordinary application/user program
  limited Kc service access

trusted user task
  still ring 3
  allowed to use selected privileged Kc services
  similar in spirit to an APF-authorized program

system user task
  still not kernel code
  started by startup policy
  allowed to manage sessions, devices, or services through approved Kc calls
```

This is deliberately not kernel mode. Trusted/system userland should remain
outside the kernel and should still enter through `int 80h`.

## Policy Boundary

The clean split should remain:

```text
Kc layer:
  validate caller authority
  validate user pointers
  decide whether the caller may request the service

Subsystem layer:
  perform the requested operation if the Kc layer allowed it
```

For example, a future device-control call should not let the device layer decide
whether an ordinary task is trusted. The Kc layer should check the task's
authority first, then route the request to the device layer.

The current Kc dispatch table now carries each service's minimum authority, and
user-originated dispatch checks that policy before calling the service handler.
That keeps trusted-only enforcement centralized as new kernel calls are added.

## Task Authority Field

Task records now carry one authority value:

```text
TASK_AUTH_NORMAL
TASK_AUTH_TRUSTED
TASK_AUTH_SYSTEM
```

The console's `Run` command loads ordinary user tasks by default. The same
command can load trusted or system tasks when the launch spec begins with
`/trusted` or `/system`. Kernel task 0 is tagged as system.

Because `STARTUP.TXT` is treated as a trusted boot-policy source, a launch
prefix of `/trusted` or `/system` can raise the task authority during loading.
For example, `run /system prog4.bin` means the trusted command source asked the
kernel to launch that task with system authority. The user program does not
grant this authority to itself.

Future task records may still grow fields such as owner session, allowed service
mask, or flags, but the first authority pattern is now present.

## Future Kernel-Call Policy

Example policy direction:

```text
KcVdWriteStr       normal allowed
KcFsOpen           normal allowed
KcFsRead           normal allowed
KcFsClose          normal allowed
KcTmSleep          normal allowed
KcKbRead           normal allowed
KcTsGetInfo        normal allowed
KcTsGetAuthority   normal allowed

KcTsLoadProgram    kernel-originated only today
KcMmGetMemory      trusted/system only, page-rounded per-task allocation
KcMmFreeMemory     trusted/system only, stack-like page release
future KcDevCtl    trusted/system only
future KcMount     trusted/system only
future KcSession   system only
future KcShutdown  console/system only
```

The exact list can wait until those services exist.

## Validation Work That Remains

Current user-pointer validation is intentionally service-specific.

Future work:

```text
broaden pointer validation as new Kc services are added
keep rejecting kernel pointers from user-originated calls
keep denial probes in Prog4 or later smoke-test programs
add tests for any new privileged service
keep fault handling simple until richer process/session policy exists
```

Completed validation probes:

```text
normal GetMemory denied
trusted GetMemory allowed and returned memory is writable
system GetMemory allowed and returned memory is writable
normal FreeMemory denied
trusted FreeMemory allowed after allocating a block
system FreeMemory allowed after allocating a block
trusted FreeMemory with a bad pointer returns BAD_ARG
```

## Startup Policy Connection

`STARTUP.TXT` is currently an automated console command stream.

Longer term, it can evolve into boot-time policy for starting trusted/system
userland tasks. That future policy should still use the same distinction:

```text
kernel mode             ring 0 kernel code
ordinary userland       ring 3, normal authority
trusted/system userland ring 3, elevated authority granted by kernel policy
```

## Deferred Work

Not needed immediately:

```text
full process/session ownership model
per-task service permission masks
rich user fault reporting
user identity or sign-on integration
preemptive watchdog enforcement
```

The current ring 3 enforcement foundation should remain small and stable while
the policy model grows only when real services need it.
