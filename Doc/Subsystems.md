# AsmOSx86 Subsystem Contracts

This document consolidates the current implementation-facing subsystem contracts for AsmOSx86.

Use this file for:
- current kernel ABI rules
- current boot/init order
- current subsystem interfaces and ownership
- current string, console, time, utility, and `KernelCtx` behavior

Use `Doc/Design.md` for high-level architecture and future direction.
Use `Doc/Coding.md` for formatting, naming, commenting, and source-style rules.
Use the source files themselves for exact implementation details.

---

## 1. ABI and Calling Conventions

### CPU / Mode

- 32-bit protected mode
- 386-safe unless a routine explicitly documents otherwise
- No 64-bit instructions
- No BIOS usage in kernel code
- Core services are currently polled; interrupts are not required for current core behavior

### Register Discipline

Unless a routine explicitly documents otherwise:

- Registers are scratch working state, not a trusted interface contract.
- Callers must not assume an incoming register contains meaningful data.
- Callers must not assume registers survive a `call`.
- Callees do not promise to preserve general registers.
- `pusha` / `popa` are not the default public routine pattern.
- Stable inputs and outputs must be expressed through documented memory locations.

AsmOSx86 prefers memory-backed contracts over register-backed contracts.

### Parameter Passing

Default rule:

```text
Inputs and outputs are passed through documented memory state.
```

Common patterns:

- module-local variables owned by the subsystem
- shared state such as `KernelCtx` only when explicitly applicable
- documented string pointers or working buffers stored in memory
- documented output variables such as `TimerOutTicksLo`, `TimerOutTicksHi`, or `KbOutHasKey`

Register-based inputs or outputs are exceptions and must be explicitly documented by the routine that uses them.

### Global Working Storage

Modules may rely on kernel-owned globals, buffers, strings, or subsystem-owned memory variables, but the dependency must be documented in the source routine contract or module header.

Hidden coupling is forbidden.

---

## 2. Kernel String Contracts

AsmOSx86 uses two string formats at the project level:

```text
CStr = NUL-terminated byte string
Str  = length-prefixed kernel string
```

This split is intentional.

### CStr

Layout:

```asm
db 'h','e','l','l','o',0
```

Scope:

- Used by boot-stage code such as `Boot1.asm` and `Boot2.asm`
- Fits BIOS-style print routines that scan for a trailing zero
- Not part of the kernel string ABI

Kernel routines must not assume CStr input unless explicitly documented.

### Str

Layout:

```text
[u16 payload length][payload bytes]
```

Example payload `ABC`:

```asm
dw 3
db 'A','B','C'
```

Locked rule:

```text
The u16 length is the payload length in bytes.
The 2-byte length field is not included in the length.
```

### String Macro

The canonical way to define a kernel `Str` at assembly time is the `String` macro in `Macros.asm`.

It:

- writes the payload length as a `dw`
- emits the payload bytes immediately after the length field

All kernel `Str` constants should be created with this macro, or must exactly match its layout.

### Kernel Usage

Kernel routines operate on `Str`, not CStr, unless explicitly documented.

Examples:

- `VdPutStr` reads the leading `u16` as payload length
- `StrCopy` copies the length word plus payload
- `StrTrim` updates the stored payload length in place

The payload is not NUL-terminated and must not be treated as though it were.

### Quick Reference

| Type | Terminator | Length storage | Length meaning |
|------|------------|----------------|----------------|
| CStr | NUL (`0`)  | none           | inferred by scan |
| Str  | none       | `u16` prefix   | payload bytes |

---

## 3. Boot and Initialization

`Kernel.asm` owns the top-level initialization sequence.

It decides which subsystems are initialized explicitly during boot and in what order.

### Current Boot Sequence

Current initialization order in `Kernel.asm`:

1. Load GDT and reload code/data segment state
2. Load an empty IDT
3. `TimerInit`
4. `UptimeInit`
5. `VdInit`
6. `KbInit`
7. `CnInit`
8. Enter the main console loop

This is the active source-of-truth sequence.

### Current Dependency Notes

- `TimerInit` must occur before timer-backed services are used.
- `UptimeInit` must occur after timer initialization.
- `VdInit` must occur before normal kernel screen output is relied on.
- `KbInit` must occur before keyboard polling is used.
- `CnInit` occurs after timer, video, and keyboard initialization.

### Wall-Time Initialization Behavior

Wall time is not explicitly initialized in `Kernel.asm` during boot.

Current behavior:

- `CnInit` emits startup log messages.
- Log output uses wall-time printing.
- Wall time becomes initialized on demand through `TimeNow`.
- `TimeNow` calls `TimeSync` if wall-time state is not yet valid.

This lazy initialization behavior is intentional.

Current design intent:

- `TimerInit` is the only required prerequisite before wall time is used.
- The kernel does not perform a separate boot-time `TimeSync`.
- The console is intended to start as early as practical in boot.
- Early console logging/display is expected to trigger first wall-time use very early in startup.

### Early-Use Rule

Current code allows limited lazy initialization for wall time through `Time.asm`.

Correct rule today:

- some services require explicit init
- wall time currently supports first-use initialization internally

This document should not claim that all subsystems forbid lazy init.

---

## 4. Console Subsystem

### Console Role

The console is the kernel/operator interface for the current system.

It is used for:

- startup messages
- diagnostics
- built-in kernel commands
- command logging
- command dispatch
- controlled shutdown

It should be treated as an operator console, not as the future userland shell or standard user session interface.

Current boot flow brings the console up early in startup, after timer, uptime, video, and keyboard initialization.

### Active Commands

The active command set currently includes:

```text
Date
Delay
Help
Shutdown
Time
Uptime
```

### Command Matching

Current command-dispatch rules:

- exact match only
- case-insensitive
- length must match after input trimming
- no argument parsing

If no command matches, the console currently does nothing and simply returns to the input loop.

### Command Semantics

#### Help

- Prints the current command names from the command table.
- Output order follows the active command table in `Console.asm`.

#### Date

- Prints the current wall date using the wall-time subsystem.
- Output format is defined by the time subsystem contract.

#### Time

- Prints the current wall time using the wall-time subsystem.
- Output format is defined by the time subsystem contract.

#### Delay

- Prints a start message with the current wall time.
- Performs a 2000 ms busy-wait delay through `Timer.asm`.
- Prints an end message with the current wall time.

#### Uptime

- Prints the current monotonic uptime through `UptimePrint`.
- Output format is defined by the uptime subsystem contract.

#### Shutdown

Purpose:

```text
End interactive operation and place the machine into a safe stopped state.
```

Real-hardware-first contract:

- On a real 386-class target, the authoritative shutdown outcome is a controlled CPU halt.
- Manual power-off by the user is expected after shutdown completes.
- Software-controlled power-off is not required for correctness on that target class.

Optional environment-specific enhancement:

- If the runtime environment supports a software power-off request, the shutdown path may attempt it before entering the final halt state.
- Emulator power-off support is a convenience feature, not the core correctness contract.

Current intended semantics:

- Announce shutdown to the user.
- Leave the final shutdown message visible briefly.
- Optionally issue environment-specific power-off requests.
- Enter a non-returning halted state.

Current implementation notes:

- `Console.asm` currently attempts Bochs/ACPI-oriented power-off port writes before halting.

### Console Design Notes

- Console behavior should be truthful for real hardware first.
- Emulator-specific behavior may extend the command outcome, but should not redefine correctness.
- A command should not claim a stronger result than the kernel can guarantee across supported environments.
- Userland should not call `Console.asm` routines directly.

---

## 5. Keyboard Subsystem

`Keyboard.asm` owns physical keyboard polling and scancode translation for the current kernel.

Current exported routines:

- `KbInit`
- `KbGetKey`

### KbInit

Output:

- `KbModShift = 0`
- `KbOutHasKey = 0`
- `KbOutType = KEY_NONE`
- `KbOutChar = 0`

### KbGetKey

Output:

- `KbOutHasKey = 1` if a key event is available, otherwise `0`
- `KbOutType = KEY_CHAR`, `KEY_ENTER`, `KEY_BACKSPACE`, or `KEY_NONE`
- `KbOutChar = ASCII value if KEY_CHAR`, otherwise `0`
- `KbModShift = updated shift state when shift make/break is seen`

Notes:

- Polls the keyboard controller once.
- Handles shift state and translates scancodes to ASCII.
- Registers are scratch only.

Current key event type constants:

```text
KEY_NONE      = 0
KEY_CHAR      = 1
KEY_ENTER     = 2
KEY_BACKSPACE = 3
```

---

## 6. Video Subsystem

`Video.asm` owns physical VGA text output for the current kernel.

### Coordinate Contract

Row/column state is 1-based:

```text
Row 1, Col 1 maps to VGA offset 0
```

Current screen model:

```text
Rows = 25
Cols = 80
Output region = rows 1..24, scrolling
Input-style row = current VdCurRow, currently set by console to row 25
```

Row,Col ordering is used everywhere.

### Current Kernel Text Output Path

```text
pVdStr -> VdPutStr -> VdPutChar -> VGA memory
```

### Core Routines

#### VdInit

Output:

- initializes output cursor
- initializes input cursor
- initializes current cursor position
- initializes default color attribute
- calls `VdClear`

#### VdPutStr

Input:

```text
pVdStr = Str pointer [u16 payload length][payload bytes]
```

Output:

- writes each payload byte through `VdPutChar`

Notes:

- Uses memory-backed loop state because `VdPutChar` may clobber all registers.

#### VdPutChar

Input:

```text
VdInCh = character/control byte to write
```

Output:

- updates output cursor row/column
- writes to output region
- handles CR, LF, BS, printable characters, and output scrolling

#### VdInClearLine

Output:

- clears the current input-style row
- resets `VdInCurCol` and `VdCurCol` to column 1

#### VdInPutChar

Input:

- `VdInCh = character to write`
- `VdCurRow = target input row, 1..25`

Output:

- writes character at `VdCurRow,VdInCurCol`
- advances `VdInCurCol`
- updates `VdCurCol`
- updates the hardware cursor

#### VdInBackspaceVisual

Output:

- if `VdInCurCol > 1`, moves one column left
- overwrites with a space
- leaves the hardware cursor at the erased position

#### VdSetCursor

Input:

- `VdCurRow = desired row, 1..25`
- `VdCurCol = desired column, 1..80`

Output:

- programs the VGA hardware text cursor
- sets `VdInCurCol = VdCurCol`

Invalid row/column enters a halt loop.

---

## 7. Timer, Time, and Uptime

AsmOSx86 treats time as two distinct services with different guarantees and use-cases.

```text
monotonic time
wall/calendar time
```

This separation is deliberate and permanent.

### Monotonic Time

Purpose:

- measure elapsed time
- drive delays, scheduling, profiling, and uptime
- never jump backward or forward unexpectedly

Properties:

- monotonic
- never resyncs
- independent of wall clock
- immune to CMOS changes

Implementation:

- source: PIT channel 0, currently polled
- API owners: `Timer.asm` and `Uptime.asm`

### Wall Time

Purpose:

- human-readable clock
- logs, timestamps, console display

Properties:

- may jump forward or backward
- periodically resynchronized
- not suitable for scheduling or delays

Implementation:

- source: CMOS RTC plus PIT interpolation
- API owner: `Time.asm`

### Ownership Rules

- All timekeeping logic lives in `Time.asm`, `Timer.asm`, or `Uptime.asm`.
- The kernel must not read CMOS or PIT registers directly.
- Resync policy, CMOS handling, and PIT math are internal details.

### Timer Subsystem

Exported interface:

- `TimerInit`
- `TimerNowTicks`
- `TimerSpinDelayMs`

#### TimerInit

- Programs PIT channel 0 for mode 2.
- Loads reload value `0xFFFF`.
- Clears the monotonic tick accumulator and output fields.

#### TimerNowTicks

Output:

```text
TimerOutTicksLo = low 32 bits of accumulated PIT input ticks
TimerOutTicksHi = high 32 bits of accumulated PIT input ticks
```

Notes:

- First call after `TimerInit` seeds the baseline and returns zero in `TimerOutTicksLo/Hi`.
- Uses PIT channel 0 down-counter plus wrap tracking to build a monotonic tick counter.

#### TimerSpinDelayMs

Input:

```text
TimerDelayMs = delay duration in milliseconds
```

Output:

- busy-waits until the computed monotonic deadline is reached

Delay calculation:

```text
ticks = round(ms * 1193182 / 1000)
```

Notes:

- 386-safe.
- 64-bit values are stored as high/low dword pairs.
- Very large millisecond values are clamped to avoid divide overflow.

### Uptime Subsystem

Semantics:

- Uptime starts exactly when `UptimeInit` is called.
- Uptime is not implicitly tied to kernel entry or boot.
- Uptime is based only on monotonic timer ticks.
- Uptime is unaffected by wall-time resync or CMOS changes.

Initialization rules:

- Kernel must call `TimerInit` before `UptimeInit`.
- Kernel currently calls `UptimeInit` during early boot.
- If `UptimeNow` or `UptimePrint` is called first, uptime lazy-initializes safely.

Exported interface:

- `UptimeInit`
- `UptimeNow`
- `UptimeFmtYdhms`
- `UptimePrint`

#### UptimeInit

Output:

```text
UptimeBaseLo/UptimeBaseHi = current monotonic tick baseline
UptimeInitDone = 1
```

#### UptimeNow

Output:

```text
UptimeOutSec = uptime seconds since UptimeInit
```

#### UptimeFmtYdhms

Input:

```text
UptimeFmtSec = seconds to format
```

Output:

```text
UptimeStr payload updated as "UP YY:DDD:HH:MM:SS"
```

#### UptimePrint

Output:

- updates `UptimeStr`
- prints it through `VdPutStr`
- prints CRLF through `CnCrLf`

Display format:

```text
UP YY:DDD:HH:MM:SS
```

Examples:

```text
UP 00:000:00:00:01
UP 01:120:13:25:35
```

### Wall-Time Subsystem

Responsibilities:

- read CMOS RTC
- maintain wall clock state
- periodically resync baseline
- print current wall date and wall time

Exported public API:

- `TimeDtPrint`
- `TimeTmPrint`

Internal `Time.asm` routines:

- `TimeSync`
- `TimeNow`
- `TimeFmtHms`
- `TimeFmtYmd`
- `TimeReadCmos`

#### Resync Policy

Current policy:

- wall time resyncs every 60 seconds of monotonic time
- resync snaps wall baseline to CMOS
- wall time may jump

#### Initialization Policy

Current policy:

- wall time is lazily initialized on first use
- kernel does not perform a dedicated boot-time wall-clock initialization step
- `TimerInit` is the only required prerequisite before wall time is used

#### TimeDtPrint

Output:

- prints current wall date in `YYYY-MM-DD` format through `VdPutStr`

#### TimeTmPrint

Output:

- prints current wall time in `HH:MM:SS` format through `VdPutStr`

#### TimeReadCmos

Output:

- `TimeHour/TimeMin/TimeSec = 0..23 / 0..59 / 0..59`
- `TimeDay = 1..31`
- `TimeMon = 1..12`
- `TimeYear = full year, e.g. 2026`

Notes:

- Handles BCD or binary RTC based on RTC status B.
- Handles 12-hour vs 24-hour RTC format.
- Uses a single RTC field read after UIP is clear, then verifies UIP stayed clear.

#### TimeSync

`TimeSync` bridges wall time to the system monotonic clock.

It:

1. Reads RTC date/time via `TimeReadCmos`.
2. Collapses current time into `WallSecDay`, seconds since midnight.
3. Reads the monotonic tick counter through `TimerNowTicks`.
4. Stores the synchronization baseline in `WallSyncLo/Hi` and `WallLastLo/Hi`.
5. Clears fractional tick state.
6. Sets `WallSyncValid`.

Conceptually:

```text
At monotonic tick T, wall time was S seconds into the day.
```

#### TimeNow

`TimeNow` maintains wall time efficiently between RTC reads.

On each call it:

1. Ensures a valid baseline exists, calling `TimeSync` if needed.
2. Reads the current monotonic tick count.
3. Computes elapsed ticks since the previous call.
4. Accumulates fractional ticks and converts whole ticks into seconds.
5. Advances `WallSecDay` modulo 86400.
6. Advances the calendar date when `WallSecDay` crosses midnight.
7. Derives `TimeHour`, `TimeMin`, and `TimeSec` from `WallSecDay`.
8. Resynchronizes to RTC if the resync interval has elapsed.

Between RTC resynchronizations, wall date and wall time remain coherent across midnight rollover.

### Time Usage Rules

| Use Case | Correct API |
|----------|-------------|
| Delays | `Timer*` |
| Scheduling | `Timer*` |
| Profiling | `Timer*` |
| Uptime | `Uptime*` |
| Logs | `Time*` |
| Clock display | `Time*` |

Never mix monotonic and wall-clock domains.

---

## 8. Utility Module

`Utility.asm` is a neutral helper module.

It exists to hold small, reusable helper routines that are:

- broadly useful across subsystems
- not owned by any single subsystem
- hardware-free
- policy-free
- safe to call from early boot and core kernel code

Utility code should make other code simpler and clearer, not smarter.

### What Belongs in Utility.asm

A routine belongs in `Utility.asm` if all of the following are true:

- it is purely functional or mechanical
- it has no hardware I/O
- it has no hidden state
- it can be reused by multiple subsystems
- it does one small thing

Typical examples:

- string manipulation helpers
- small copy/trim helpers for kernel `Str`
- small formatting helpers
- buffer manipulation helpers
- simple math helpers that do not belong to Timer/Time/etc.

### What Does Not Belong in Utility.asm

The following must not live in `Utility.asm`:

- hardware access: ports, MMIO, BIOS, IRQs
- policy decisions: timeouts, retries, logging behavior
- subsystem-specific logic
- dependencies on console, keyboard, timer, video, or active initialization state
- dependencies on `KernelCtx` internals unless explicitly documented

### Utility ABI Rules

All Utility routines follow the global ABI:

- registers are scratch working state
- callers must not assume registers survive a `call`
- routines must not use `pusha` / `popa` as the default pattern
- stable inputs and outputs must be passed through documented memory variables
- any register-based exception must be explicitly documented

### Current Utility Routines

#### Put2Dec

Input:

```text
Put2DecVal  = value 0..99
pPut2DecDst = destination payload pointer
```

Output:

```text
[pPut2DecDst original]   = tens ASCII digit
[pPut2DecDst original+1] = ones ASCII digit
pPut2DecDst += 2
```

#### StrCopy

Input:

```text
pStr1 = source Str pointer
pStr2 = destination Str pointer
```

Output:

- destination `Str` receives source length word and payload bytes

#### StrTrim

Input:

```text
pStr1 = Str pointer
```

Output:

- leading and trailing spaces removed in-place

Notes:

- calls `StrTrimLead` and `StrTrimTrail`

#### StrTrimLead

Input:

```text
pStr1 = Str pointer
```

Output:

- leading spaces removed in-place
- string length word updated

#### StrTrimTrail

Input:

```text
pStr1 = Str pointer
```

Output:

- trailing spaces removed in-place
- string length word updated

### Utility Growth Rule

`Utility.asm` grows slowly and deliberately.

Before adding a routine, ask:

```text
Would I be annoyed to see this here six months from now?
```

If yes, it belongs somewhere else or should not exist yet.

---

## 9. KernelCtx

`KernelCtx` is defined in `Kernel.asm`.

At present, it should be viewed as an early kernel-owned context/state block, not as the active owner of all subsystem runtime state.

Its longer-term purpose is to support task-switching and related saved-context work.

### Current Reality

Most active subsystem state in the current kernel does not live in `KernelCtx`.

Instead, subsystem state is currently owned locally by the module that uses it.

Examples:

- `Console.asm`
- `Keyboard.asm`
- `Video.asm`
- `Timer.asm`
- `Time.asm`
- `Uptime.asm`

This is the current source reality and should not be obscured by documentation.

### Current KernelCtx Block

Defined in `Kernel.asm` under `KernelCtx:`.

Current fields:

- `Char`
- `Byte1`
- `KbChar`
- `ColorBack`
- `ColorFore`
- `ColorAttr`
- `Row`
- `Col`
- `Byte2`
- `Byte4`
- `TvRowOfs`
- `VidAdr`

These fields exist in the source, but they should not be interpreted as the current ownership model for active kernel subsystems.

Some are legacy scratch/state fields and may later be repurposed, reduced, or replaced as the task/context model becomes more explicit.

### Alignment Rule

`KernelCtxSz` must be divisible by 4.

This is enforced in `Kernel.asm` and exists to preserve compatibility with future `rep movsd` style context copy operations.

### Intended Direction

`KernelCtx` is intended to evolve into a shared kernel context block used for:

- saved execution context
- task-switch related state
- other kernel-owned context data that benefits from block copy / structured save-restore behavior

That design is not fully fleshed out yet.

Until it is, documentation must distinguish between:

- the current implementation
- the intended architectural direction

### Ownership Notes

Current ownership model:

- `Kernel.asm` owns the `KernelCtx` definition.
- Active subsystem runtime state is mostly module-local.
- Strings, tables, and working storage are generally owned by the module that uses them.

This means `KernelCtx` should not currently be described as the central home for shared strings, keyboard tables, or all mutable kernel state.

---

## 10. Current Subsystem Summary

Current major kernel components:

```text
Config.asm
Console.asm
Keyboard.asm
Time.asm
Timer.asm
Uptime.asm
Utility.asm
Video.asm
```

Current explicit boot subsystem order:

```text
TimerInit
UptimeInit
VdInit
KbInit
CnInit
```

Current core contracts:

- memory-backed ABI
- scratch registers
- kernel `Str = [u16 payload length][payload bytes]`
- console is kernel/operator interface
- physical keyboard/video are kernel-owned
- monotonic time and wall time are separate domains
- uptime is monotonic and wall-time independent
- utility routines are boring, small, hardware-free helpers
- `KernelCtx` exists but is not current subsystem-state ownership center
