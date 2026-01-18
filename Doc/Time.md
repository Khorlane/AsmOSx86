# ⏱️ Time Architecture (AsmOSx86)

AsmOSx86 treats **time as two distinct services** with different guarantees and use-cases.
This separation is deliberate and permanent.

---

## 1. Time Domains

### 1.1 Monotonic Time (TimeMono / Uptime)

**Purpose**
- Measure elapsed time
- Drive delays, scheduling, profiling, and uptime
- Must never jump backward or forward unexpectedly

**Properties**
- Monotonic
- Never resyncs
- Independent of wall clock
- Immune to CMOS changes

**Implementation**
- Source: PIT channel 0 (polled, no IRQs)
- API owner: `Timer.asm` + `Uptime.asm`

---

### 1.2 Wall Time (TimeWall / Calendar)

**Purpose**
- Human-readable clock
- Logs, timestamps, console display

**Properties**
- May jump forward or backward
- Periodically resynchronized
- Not suitable for scheduling or delays

**Implementation**
- Source: CMOS (RTC) + PIT for interpolation
- API owner: `Time.asm`

---

## 2. Ownership Rules (LOCKED-IN)

- **ALL timekeeping logic lives in `Time.asm`, `Timer.asm`, or `Uptime.asm`.**
- The kernel **must not** read CMOS or PIT registers directly.
- Resync policy, CMOS handling, and PIT math are **internal details**.

---

## 3. Timer Subsystem (`Timer.asm`)

### Exported Interface
- `TimerInit`
- `TimerNowTicks`  
  - Returns `EDX:EAX = monotonic PIT input ticks`
- `TimerDelayMs`
  - Busy-wait delay using monotonic ticks

### Characteristics
- 386-safe
- No interrupts
- 64-bit tick accumulation using `EDX:EAX`
- PIT channel 0 programmed in mode 2

### Delay Accuracy
Delays use:
ticks = round(ms * 1193182 / 1000)  
Implemented using 32-bit math with remainder handling.

---

## 4. Uptime Subsystem (`Uptime.asm`)

### Semantics (LOCKED-IN)
- Uptime starts **exactly when `UptimeInit` is called**
- Not implicitly tied to kernel entry or boot
- Kernel defines what “uptime” means

### Initialization Rules
- Kernel **must call `TimerInit` before `UptimeInit`**
- Kernel **should call `UptimeInit` during early boot**
- If `UptimeNow` or `UptimePrint` is called first:
  - Uptime lazy-initializes safely

### Exported Interface
- `UptimeInit`
- `UptimeNow`
  - Returns `EAX = uptime seconds`
- `UptimePrint`

### Display Format (LOCKED-IN)
UP YY:DDD:HH:MM:SS

Examples:
- 1 second: `UP 00:000:00:00:01`
- 1 year, 120 days, 13:25:35: `UP 01:120:13:25:35`

### Guarantees
- Never goes backward
- Not affected by wall-time resync
- Rollover and formatting policy are local to `Uptime.asm`

---

## 5. Wall Time Subsystem (`Time.asm`)

### Responsibilities
- Read CMOS (RTC)
- Maintain wall clock state
- Periodically resync baseline

### Resync Policy (Current)
- Wall time resyncs every **60 seconds of monotonic time**
- Resync snaps wall baseline to CMOS
- Wall time may jump

### Exported Interface
- `TimeSync`
- `TimeNow`
- `TimeFmtHms`
- `TimeTmPrint`

---

## 6. Rules of Use

| Use Case | Correct API |
|--------|-------------|
| Delays | `Timer*` |
| Scheduling | `Timer*` |
| Profiling | `Timer*` |
| Uptime | `Uptime*` |
| Logs | `Time*` |
| Clock display | `Time*` |

**Never mix domains.**

---

## 7. Future-Proofing

This design allows:
- IRQ-driven timers later
- Higher resolution timekeeping
- Scheduler time slicing
- SMP timebase isolation

Without breaking existing code.

---

## Timekeeping Overview: CMOS Clock, TimeSync, and TimeNow

### CMOS Clock (RTC)
- The CMOS Real-Time Clock is the hardware source of “real” wall time.
- It is accessed via I/O ports `0x70` / `0x71`.
- The RTC updates once per second and may present values as:
  - BCD or binary
  - 12-hour or 24-hour format
- `TimeReadCmos` reads the raw RTC registers, waits for a stable update window (UIP=0),
  converts BCD to binary if needed, normalizes 12h → 24h, and produces clean binary
  values in `TimeHour`, `TimeMin`, and `TimeSec` (plus date fields).

### TimeSync
- `TimeSync` bridges real (wall) time to the system’s monotonic clock.
- It performs a single trusted RTC read via `TimeReadCmos`.
- The current time is collapsed into a single scalar:
  - `WallSecDay` = seconds since midnight (0..86399).
- At the same moment, it reads the monotonic tick counter (`TimerNowTicks`).
- This monotonic tick is stored as the synchronization baseline
  (`WallSyncLo/Hi` and `WallLastLo/Hi`).
- Fractional tick state is reset and `WallSyncValid` is set.

**Conceptually:**  
> “At monotonic tick **T**, wall time was **S** seconds into the day.”

### TimeNow
- `TimeNow` maintains wall time efficiently between RTC reads.
- On each call it:
  1. Ensures a valid baseline exists (calls `TimeSync` if not).
  2. Reads the current monotonic tick count.
  3. Computes elapsed ticks since the previous call.
  4. Accumulates fractional ticks and converts whole ticks into seconds
     using `TIME_PIT_HZ`.
  5. Advances `WallSecDay` modulo 86400.
  6. Derives `TimeHour`, `TimeMin`, and `TimeSec` from `WallSecDay`.

- To limit drift, `TimeNow` enforces a resynchronization policy:
  - If more than `TIME_RSYNC_SEC` seconds have elapsed since the last
    synchronization, it calls `TimeSync` again.
  - This keeps wall time aligned with the RTC without the cost of frequent
    CMOS reads.

### Summary
- **CMOS RTC**: authoritative wall-time source.
- **TimeSync**: snapshots RTC time and pins it to a monotonic tick baseline.
- **TimeNow**: advances wall time using monotonic ticks, periodically
  re-syncing to the RTC to correct drift.

**This document reflects current implementation and is authoritative.**