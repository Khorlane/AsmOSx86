# 🛠️ Kernel Initialization Sequence (AsmOSx86)

This document defines the **authoritative** kernel initialization sequence for AsmOSx86.
All initialization order dependencies are explicit and **owned by `Kernel.asm`**.

Once a rule is marked **LOCKED-IN**, callers may rely on it permanently.

---

## 1) Ownership Rule (LOCKED-IN)

**`Kernel.asm` is the single owner of initialization order.**

- `Kernel.asm` MUST call all `*Init` / `*Sync` routines in the required order.
- No module MAY call another module’s `*Init` / `*Sync` internally.
- No subsystem may “lazy init” itself on first use.
- If a routine requires prior initialization and is called too early, that is a kernel bug.

This eliminates hidden coupling and makes boot behavior deterministic.

---

## 2) Required Initialization Steps (LOCKED-IN)

### Step 1 — Video / KernelCtx Baseline
`Kernel.asm` MUST establish the initial console-visible state before any printing:

- Screen cleared (or otherwise defined)
- `Row`, `Col` set to a valid starting position
- `ColorBack`, `ColorFore`, and derived `ColorAttr` set

This step MUST occur before any routine that prints to the screen.

---

### Step 2 — `TimerInit`
`Kernel.asm` MUST call `TimerInit` exactly once during boot.

`TimerInit` programs PIT channel 0 for polled timing and establishes the monotonic tick baseline.

After this step:
- `TimerNowTicks` and `TimerDelayMs` are valid to call.

---

### Step 3 — `UptimeInit`
`Kernel.asm` MUST call `UptimeInit` after `TimerInit`.

`UptimeInit` captures the monotonic baseline tick that defines “uptime start”.

After this step:
- `UptimeNow` and `UptimePrint` are valid to call.

---

### Step 4 — `TimeSync`
`Kernel.asm` MUST call `TimeSync` after `TimerInit` and before any timestamped logging.

`TimeSync` reads CMOS once and pins the wall-clock baseline to a monotonic tick.

After this step:
- Wall time is considered initialized.
- The first log line can safely include a real timestamp.

---

### Step 5 — `CnInit`
`Kernel.asm` MUST call `CnInit` after the timing subsystems are initialized.

`CnInit` establishes console policy/state (even if currently minimal).  
After this step:
- `CnPrint`, `CnBoot`, and `CnLog` are valid to call.

---

## 3) Dependency Rules (LOCKED-IN)

- `TimerInit` MUST run before any routine that relies on monotonic ticks:
  - `TimerNowTicks`
  - `TimerDelayMs`
  - `UptimeInit`, `UptimeNow`, `UptimePrint`
  - `TimeSync`, `TimeNow`, wall-clock interpolation/advance

- `UptimeInit` MUST run after `TimerInit`.

- `TimeSync` MUST run after `TimerInit` and MUST occur before the first call to `CnLog`.

- Video/KernelCtx Baseline MUST occur before any screen output routine (`PutStr`, `Cn*`, etc.).

---

## 4) Allowed Early-Use Exceptions

None.

There are no “safe to call before init” routines in the kernel ABI.
Calling a routine before its required init step is a kernel bug.

---

## 5) Extensibility

New subsystems MUST be added to this document by:

- Defining their `*Init` routine(s)
- Stating exact dependencies (what must be initialized first)
- Adding them to the required initialization steps in the correct order

Hidden initialization or undocumented dependencies are forbidden.

---

## Summary (LOCKED-IN)

Required boot order in `Kernel.asm`:

1. Video / KernelCtx Baseline
2. `TimerInit`
3. `UptimeInit`
4. `TimeSync`
5. `CnInit`