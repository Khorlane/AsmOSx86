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
- `TimeInit`
- `TimeSync`
- `TimeNow`
- `TimeFmtHms`
- `TimePrint`

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

**This document reflects current implementation and is authoritative.**