# 🧠 Kernel Context + Shared Globals (AsmOSx86)

This document describes the shared mutable state and shared buffers
that multiple modules rely on.

---

## 1) KernelCtx memory block (mutable globals)

Defined in: `Kernel.asm` under `KernelCtx:`.

### Fields

- `Char`        (db)  : scratch character for Video
- `Byte1`       (db)  : generic scratch
- `KbChar`      (db)  : keyboard scancode or ASCII depending on stage
- `ColorBack`   (db)  : background color 0..15
- `ColorFore`   (db)  : foreground color 0..15
- `ColorAttr`   (db)  : packed attribute (back<<4 | fore)
- `Row`         (db)  : 1..25
- `Col`         (db)  : 1..80
- `Byte2`       (dw)  : generic scratch
- `Byte4`       (dd)  : generic scratch / debug value
- `TvRowOfs`    (dd)  : video row offset scratch
- `VidAdr`      (dd)  : current video address

### Alignment rule

`KernelCtxSz` must be divisible by 4.
(Required by future `rep movsd` usage; enforced by NASM check.)

---

## 2) Shared string buffers / constants

Defined in: `Kernel.asm` String section.

- `Buffer`      : general purpose 8-char payload string
- `CrLf`        : 0Dh,0Ah
- `CnBannerStr` : console banner
- `CnBootMsg`   : boot message
- `TimeStr`     : "HH:MM:SS" buffer
- `UptimeStr`   : "UP YY:DDD:HH:MM:SS" buffer

String format is defined in `Doc/Abi.md`.

---

## 3) Keyboard translation tables (current placement)

Defined in: `Kernel.asm` (current canonical placement)

- `Scancode`, `ScancodeSz`
- `CharCode`, `CharCodeSz`
- `IgnoreCode`, `IgnoreSz`

`Keyboard.asm` depends on these being present.

Ownership note:
- Tables currently live in `Kernel.asm` for simplicity.
- If/when Keyboard becomes fully self-owned, these may move into `Keyboard.asm`
  without changing the calling contract.

---

## 4) Ownership summary

- `Kernel.asm` owns KernelCtx + shared buffers/strings.
- `Video.asm` owns screen I/O primitives but uses KernelCtx fields.
- `Console.asm` owns Session 0 console policy and uses `PutStr`.
- `Keyboard.asm` owns keyboard polling + translation logic and uses tables.
- `Timer.asm` owns monotonic ticks.
- `Uptime.asm` owns uptime semantics + formatting.
- `Time.asm` owns wall clock (RTC baseline + PIT interpolation policy).