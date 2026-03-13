# Time Design Record

This document preserves the time-design discussion and records the chosen direction.
It is not the authoritative behavior spec; that lives in `Doc/Time.md`.

Use this file for:
- design rationale
- rejected or superseded options
- hardware caveats
- discussion history with explicit outcomes

Use `Time.md` for:
- current contracts
- exported interfaces
- locked-in behavior
- implementation-facing semantics

## Topic 1 - CMOS RTC Read Pitfalls

### Status
Decided guidance. Relevant when reading CMOS in `Time.asm`.

### Discussion
Common RTC failure modes identified during early design:
- Update-In-Progress (UIP): CMOS updates once per second, so values can be inconsistent during rollover. Check Register A bit 7 and read only when UIP = 0.
- Double-read safety: wait for UIP = 0, read all fields, wait for UIP = 0 again, read again, and retry on mismatch.
- BCD vs binary: Register B bit 2 determines whether conversion is required.
- 12-hour vs 24-hour: Register B bit 1 determines hour format; 12-hour mode requires PM-bit handling.
- Century register unreliability: some BIOSes expose it, some do not, and some hardcode it incorrectly.
- NMI masking: port `0x70` bit 7 disables NMI during indexed CMOS access.
- Local time storage: RTC should be treated as wall clock without timezone semantics at this stage.

### Decision
Current direction is:
- treat the RTC as a wall-clock source only
- normalize RTC data immediately after reading
- handle UIP, BCD/binary, and 12h/24h correctly inside the time subsystem
- keep CMOS access isolated to timekeeping code

### Notes
The earlier discussion included a stronger "read once at boot, then never touch CMOS again" position. That is no longer the current design direction. The current architecture in `Time.md` allows periodic RTC resynchronization for wall time while keeping monotonic time independent.

## Topic 2 - Epoch Choice And Internal Representation

### Status
Partly superseded.

### Discussion
Three internal representations were considered:
1. Unix epoch (`1970-01-01 00:00:00`)
   - Pros: standard, easy to compare, future-proof, works well with 64-bit counters.
   - Cons: requires calendar-to-seconds conversion.
2. Seconds since boot only
   - Pros: simple and ideal for scheduler, delays, and timeouts.
   - Cons: cannot represent wall-clock time.
3. Raw calendar struct (`Y/M/D H:M:S`)
   - Pros: easy to print initially.
   - Cons: poor for arithmetic and comparisons, likely technical debt.

The design discussion concluded that real kernels need two clocks:
- monotonic time for scheduling and measurement
- wall-clock time for human-readable timekeeping

The earlier recommended direction was:
- epoch: Unix epoch
- internal wall-clock format: 64-bit epoch seconds
- boot flow: read RTC, convert to epoch seconds, store wall baseline, then derive current wall time from monotonic progress

### Decision
The durable decision is the two-clock model, not the specific epoch-seconds representation.

Current direction:
- monotonic time and wall time are separate domains
- monotonic time is always required
- wall time exists for display/logging and may be resynchronized

### Notes
The current implementation documented in `Time.md` uses wall time as calendar state plus seconds-since-midnight interpolation, not a pure epoch-seconds model. The epoch-seconds approach remains a viable future design option, but it is not the current authoritative representation.

## Topic 3 - Ownership And Layering

### Status
Decided and still current.

### Discussion
The core architectural rule established in the discussion was:
- timekeeping is a kernel service
- timer hardware produces ticks
- console code does not own time

Layering discussed during design:
1. Timer hardware layer
   - PIT early, HPET/APIC later
   - responsible only for producing a tick source
2. Kernel time core
   - owns monotonic state, wall state, and tick-to-time conversion
   - provides time queries and sleep/timeout semantics
3. RTC access
   - used to seed or refresh wall time
4. Formatting layer
   - human-readable formatting should stay outside low-level time ownership where practical

The discussion also highlighted failure modes to avoid:
- console owning time
- RTC or unrelated drivers doing global time math
- multiple competing current-time sources
- time moving backward in subsystems that require monotonic behavior

### Decision
This topic remains aligned with the current system:
- kernel timekeeping owns policy
- hardware timer code owns raw tick production
- RTC access belongs to the time subsystem, not arbitrary kernel code
- monotonic and wall time must remain separate domains

### Notes
`Time.md` is now the authoritative place for exported interfaces and ownership rules. This section exists to preserve the rationale behind those rules.

## Topic 4 - 386 Compatibility And 64-Bit Time State

### Status
Open design guidance, with current preference recorded.

### Discussion
Concern raised: AsmOSx86 must run on a 386-class machine, including a Tandy 2500 386.

Key point from the discussion:
- a 386 can store 64-bit values just fine
- the limitation is instruction support, not representation
- 64-bit math must be expressed as pairs of 32-bit operations using `add/adc`, `sub/sbb`, and hi-then-lo compares

Three implementation options were discussed:
1. 32-bit tick counter plus wrap counter
   - simple and efficient
   - presents 64-bit semantics through `{wraps, ticks}`
2. 32-bit epoch seconds for now
   - sufficient for a long time horizon
   - can be extended later
3. Full 64-bit hi/lo state
   - most general
   - requires disciplined encapsulation

The follow-up discussion asked whether full 64-bit state would leak complexity across the kernel. The answer was that it can mostly be hidden if the kernel does not manipulate hi/lo storage directly.

Suggested encapsulation model from the discussion:
- keep hi/lo globals private to the time subsystem
- expose narrow routines such as increment, read, compare, and diff helpers
- treat `EDX:EAX` as the public register-level time value
- avoid direct timestamp arithmetic outside scheduler/time code

### Decision
No final architecture-wide lock-in was made here, but the current preference is:
- keep 386 compatibility explicit
- hide multiword time math inside time-related modules
- do not let arbitrary kernel code manipulate 64-bit time state directly

### Notes
This remains guidance rather than a current contract. `Time.md` should define the public semantics; this section preserves the reasoning behind how those semantics can remain 386-safe.
