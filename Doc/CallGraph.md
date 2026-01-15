# AsmOSx86 Call Graph (complete from provided codebase)

This call graph is generated **only** from the files shown in this chat (treated as authoritative).

---

## Legend

- **A → B** means **A calls B**
- “(private)” indicates an internal helper (not intended as an exported kernel contract)

---

## Top-level entry and boot flow

### Kernel.asm
- **Stage3**
  - → SetColorAttr (Video.asm)
  - → ClrScr (Video.asm)
  - → TimerInit (Timer.asm)
  - → UptimeInit (Uptime.asm)
  - → TimeSync (Time.asm)
  - → CnInit (Console.asm)
  - → KbInit (Keyboard.asm)
  - → UptimePrint (Uptime.asm)
  - → TimePrint (Time.asm)
  - → TimerDelayMs (Timer.asm)
  - → TimePrint (Time.asm)
  - → UptimePrint (Uptime.asm)
  - → FloppyTest (Utility.asm)
  - → DebugIt (Utility.asm)   *(multiple times)*
  - → ConsoleLoop (Console.asm)

---

## Console subsystem

### Console.asm
- **ConsoleLoop**
  - → PutStrRaw (Video.asm)
  - → CnReadLine (Console.asm)
  - → MoveCursor (Video.asm)
  - → PutStr (Video.asm)      *(TypedPrefixStr)*
  - → PutStr (Video.asm)      *(LineLStr)*
  - → PutStr (Video.asm)      *(CrLf)*

- **CnInit**
  - → CnLog *(x3)*

- **CnCrLf**
  - → PutStr (Video.asm)

- **CnPrint**
  - → PutStr (Video.asm)
  - → CnCrLf

- **CnLog**
  - → TimeNow (Time.asm)
  - → TimeFmtYmdHms (Time.asm)
  - → PutStr (Video.asm)      *(timestamp)*
  - → PutStr (Video.asm)      *(space)*
  - → PutStr (Video.asm)      *(message)*
  - → CnCrLf

- **CnCmdSave**
  - *(no calls)*

- **CnCmdRestore**
  - → MoveCursor (Video.asm)

- **CnReadLine**
  - → KbWaitChar (Keyboard.asm)
  - → PutStrRaw (Video.asm)   *(echo char / backspace seq)*

---

## Keyboard subsystem (polled)

### Keyboard.asm
- **KbInit**
  - *(no calls)*

- **KbPoll**
  - → KbScancodeToAscii (private)
  - → KbEnqueueAscii (private)

- **KbGetChar**
  - → KbDequeueAscii (private)

- **KbWaitChar**
  - → KbPoll
  - → KbDequeueAscii (private)

- **KbReadLine**
  - → KbWaitChar

Private helpers:
- **KbScancodeToAscii (private)**
  - *(no calls)*

- **KbEnqueueAscii (private)**
  - *(no calls)*

- **KbDequeueAscii (private)**
  - *(no calls)*

- **KbEchoChar (private)** *(currently unused by KbReadLine in shown code)*
  - → PutStrRaw (Video.asm)

- **KbEchoCrlf (private)** *(currently unused)*
  - → PutStrRaw (Video.asm)

- **KbEchoBackspace (private)** *(currently unused)*
  - → PutStrRaw (Video.asm)

---

## Time (wall clock) subsystem

### Time.asm
- **TimeSync**
  - → TimeReadCmos (private)
  - → TimerNowTicks (Timer.asm)

- **TimeNow**
  - → TimeSync *(when baseline invalid or resync interval reached)*
  - → TimerNowTicks (Timer.asm)

- **TimeFmtHms**
  - → TimePut2Dec (private)

- **TimePrint**
  - → TimeNow
  - → TimeFmtHms
  - → CnPrint (Console.asm)

- **TimeUptimeFmtHms**
  - → TimerNowTicks (Timer.asm)
  - → TimePut2Dec (private)

- **TimeFmtYmdHms**
  - → TimePut4Dec (private)
  - → TimePut2Dec (private)

Private helpers:
- **TimeCmosReadReg (private)**
  - *(no calls)*

- **TimeWaitNotUip (private)**
  - → TimeCmosReadReg (private)

- **TimeBcdToBin (private)**
  - *(no calls)*

- **TimeNormalizeHour (private)**
  - *(no calls)*

- **TimeReadCmos (private)**
  - → TimeWaitNotUip (private)
  - → TimeCmosReadReg (private) *(many times)*
  - → TimeBcdToBin (private) *(many times, when RTC is BCD)*
  - → TimeNormalizeHour (private)

- **TimePut2Dec (private)**
  - *(no calls)*

- **TimePut4Dec (private)**
  - *(no calls)*

---

## Timer (monotonic PIT ticks)

### Timer.asm
- **TimerInit**
  - *(no calls)*

- **TimerNowTicks**
  - → TimerLatchCount0 (private)

- **TimerDelayMs**
  - → TimerNowTicks *(looping until deadline)*

Private helper:
- **TimerLatchCount0 (private)**
  - *(no calls)*

---

## Uptime subsystem (monotonic seconds)

### Uptime.asm
- **UptimeInit**
  - → TimerNowTicks (Timer.asm) *(twice)*

- **UptimeNow**
  - → TimerNowTicks (Timer.asm)

- **UptimePrint**
  - → UptimeNow
  - → UptimeFmtYdhms (private)
  - → CnPrint (Console.asm)

Private helpers:
- **UptimeFmtYdhms (private)**
  - → UptimePut2Dec (private)
  - → UptimePut3Dec (private)

- **UptimePut2Dec (private)**
  - *(no calls)*

- **UptimePut3Dec (private)**
  - *(no calls)*

---

## Floppy subsystem (motor control only)

### Floppy.asm
- **FloppyInit**
  - *(no calls)*

- **FloppySetDrive**
  - *(no calls)*

- **FloppyMotorOn**
  - → FlpDelay1ms (private)

- **FloppyMotorOff**
  - *(no calls)*

Private helper:
- **FlpDelay1ms (private)**
  - *(no calls)*

---

## Utility helpers

### Utility.asm
- **CStrToLStr**
  - *(no calls)*

- **FloppyTest**
  - → FloppyInit (Floppy.asm)
  - → FloppyMotorOn (Floppy.asm)
  - → FlpDelay1ms (Floppy.asm) *(loop)*
  - → FloppyMotorOff (Floppy.asm)

- **DebugIt**
  - → HexDump (Utility.asm)
  - → PutStr (Video.asm)
  - → PutStr (Video.asm)

- **HexDump**
  - *(no calls)*

---

## Video subsystem

### Video.asm
- **CalcVideoAddr**
  - → ScrollUpMain (Video.asm)

- **CalcVideoAddrRaw**
  - *(no calls)*

- **PutChar**
  - *(no calls)*

- **PutStr**
  - → CalcVideoAddr
  - → ScrollUpMain *(on LF at row 24)*
  - → PutChar
  - → MoveCursor

- **PutStrRaw**
  - → CalcVideoAddrRaw
  - → PutChar
  - → MoveCursor

- **MoveCursor**
  - *(no calls)*

- **ClrScr**
  - *(no calls)*

- **SetColorAttr**
  - *(no calls)*

- **ScrollUp**
  - *(no calls)*

- **ScrollUpMain**
  - *(no calls)*

---

## Mermaid overview (high-level)

```mermaid
flowchart TD
  Stage3[Kernel.Stage3] --> TimerInit
  Stage3 --> UptimeInit
  Stage3 --> TimeSync
  Stage3 --> CnInit
  Stage3 --> KbInit
  Stage3 --> UptimePrint
  Stage3 --> TimePrint
  Stage3 --> TimerDelayMs
  Stage3 --> FloppyTest
  Stage3 --> DebugIt
  Stage3 --> ConsoleLoop

  ConsoleLoop --> CnReadLine
  ConsoleLoop --> PutStr
  ConsoleLoop --> PutStrRaw
  ConsoleLoop --> MoveCursor

  CnReadLine --> KbWaitChar
  CnReadLine --> PutStrRaw

  CnLog --> TimeNow
  CnLog --> TimeFmtYmdHms
  CnLog --> PutStr

  TimeNow --> TimerNowTicks
  TimeNow --> TimeSync
  TimeSync --> TimeReadCmos
  TimeSync --> TimerNowTicks
  TimePrint --> CnPrint
  UptimePrint --> CnPrint

  TimerDelayMs --> TimerNowTicks
  TimerNowTicks --> TimerLatchCount0

  FloppyTest --> FloppyInit
  FloppyTest --> FloppyMotorOn
  FloppyTest --> FlpDelay1ms
  FloppyTest --> FloppyMotorOff

  PutStr --> CalcVideoAddr
  PutStr --> PutChar
  PutStr --> MoveCursor
  CalcVideoAddr --> ScrollUpMain