;**************************************************************************************************
; Uptime.asm
;   Monotonic uptime reporting for AsmOSx86.
;
; Purpose
;   Report elapsed monotonic time since UptimeInit using Timer.asm ticks.
;
; Display Format
;   - UP YY:DDD:HH:MM:SS
;
; Contains
;   - Uptime baseline initialization
;   - Current uptime calculation in seconds
;   - YY:DDD:HH:MM:SS formatting
;   - Console uptime printing
;
; Public API
;   - UptimeInit
;   - UptimeNow
;   - UptimeFmtYdhms
;   - UptimePrint
;
; Contracts
;   - UptimeInit captures UptimeBaseLo:UptimeBaseHi from TimerNowTicks.
;   - UptimeNow returns UptimeOutSec = seconds since UptimeInit.
;   - UptimeFmtYdhms reads UptimeFmtSec and updates UptimeStr.
;   - UptimePrint updates and prints UptimeStr through VdPutStr plus CnCrLf.
;
; Semantics
;   - Uptime measures monotonic elapsed time since UptimeInit.
;   - Uptime is based only on TimerNowTicks / TimerOutTicksLo/Hi.
;   - Uptime is unaffected by wall-time resync or CMOS changes.
;
; Notes
;   - UptimeNow lazily calls UptimeInit if needed.
;   - Uptime code is 386-safe: no 64-bit instructions.
;   - Registers are scratch only.
;   - Persistent inputs/outputs use Uptime* globals.
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; Constants
;--------------------------------------------------------------------------------------------------
UP_PIT_HZ       equ 1193182
UP_SEC_MIN      equ 60
UP_SEC_HOUR     equ 3600
UP_SEC_DAY      equ 86400
UP_SEC_YEAR     equ 31536000

String  UptimeStr,"UP YY:DDD:HH:MM:SS"
UptimeBaseLo       dd 0                 ; baseline ticks low
UptimeBaseHi       dd 0                 ; baseline ticks high
UptimeOutSec       dd 0                 ; output: uptime seconds
UptimeFmtSec       dd 0                 ; input: seconds to format
UptimeYears        dd 0                 ; work: total years
UptimeDays         dd 0                 ; work: day-of-year 0..364
UptimeHours        db 0                 ; work: hour 0..23
UptimeMinutes      db 0                 ; work: minute 0..59
UptimeSeconds      db 0                 ; work: second 0..59
UptimeInitDone     db 0                 ; 1 once baseline is captured
UptimePad0         db 0                 ; alignment padding
UptimePut3DecVal   dd 0                 ; input: value 0..999
pUptimePut3DecDst  dd 0                 ; input/output: destination payload pointer

;--------------------------------------------------------------------------------------------------
; External Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; UptimeInit
;   Output:
;     UptimeBaseLo/UptimeBaseHi = current monotonic tick baseline.
;     UptimeInitDone = 1.
;   Notes:
;     Calls TimerNowTicks twice: first to prime, second for baseline.
;--------------------------------------------------------------------------------------------------
UptimeInit:
  call  TimerNowTicks                   ; Prime TimerNowTicks
  call  TimerNowTicks                   ; Stable baseline read
  mov   eax,[TimerOutTicksLo]
  mov   edx,[TimerOutTicksHi]
  mov   [UptimeBaseLo],eax
  mov   [UptimeBaseHi],edx
  mov   byte[UptimeInitDone],1
  ret

;--------------------------------------------------------------------------------------------------
; UptimeNow
;   Output:
;     UptimeOutSec = uptime seconds since UptimeInit.
;   Notes:
;     Lazily calls UptimeInit if no baseline has been captured yet.
;--------------------------------------------------------------------------------------------------
UptimeNow:
  cmp   byte[UptimeInitDone],1
  je    UptimeNow1
  call  UptimeInit
UptimeNow1:
  call  TimerNowTicks
  mov   eax,[TimerOutTicksLo]
  mov   edx,[TimerOutTicksHi]
  sub   eax,[UptimeBaseLo]
  sbb   edx,[UptimeBaseHi]              ; delta ticks in local scratch
  mov   ecx,UP_PIT_HZ
  div   ecx                             ; quotient seconds, remainder ticks
  mov   [UptimeOutSec],eax
  ret

;--------------------------------------------------------------------------------------------------
; UptimeFmtYdhms
;   Input:
;     UptimeFmtSec = uptime seconds to format.
;   Output:
;     UptimeStr payload updated to "UP YY:DDD:HH:MM:SS".
;   Notes:
;     Years are displayed modulo 100.
;     Days are day-of-year style 000..364 using 365-day years.
;     Uses Put2Dec and UptimePut3Dec through memory-contract variables.
;--------------------------------------------------------------------------------------------------
UptimeFmtYdhms:
  mov   eax,[UptimeFmtSec]
  xor   edx,edx
  mov   ebx,UP_SEC_YEAR
  div   ebx                             ; quotient years_total, remainder year
  mov   [UptimeYears],eax
  mov   eax,edx
  xor   edx,edx
  mov   ebx,UP_SEC_DAY
  div   ebx                             ; quotient DDD, remainder day
  mov   [UptimeDays],eax
  mov   eax,edx
  xor   edx,edx
  mov   ebx,UP_SEC_HOUR
  div   ebx                             ; quotient HH, remainder hour
  mov   [UptimeHours],al
  mov   eax,edx
  xor   edx,edx
  mov   ebx,UP_SEC_MIN
  div   ebx                             ; quotient MM, remainder SS
  mov   [UptimeMinutes],al
  mov   [UptimeSeconds],dl
  mov   edi,UptimeStr
  add   edi,5                           ; payload + 3, points to YY
  mov   eax,[UptimeYears]
  xor   edx,edx
  mov   ebx,100
  div   ebx                             ; EDX=YY
  mov   al,dl
  mov   [Put2DecVal],al
  mov   [pPut2DecDst],edi
  call  Put2Dec
  mov   edi,[pPut2DecDst]
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   eax,[UptimeDays]
  mov   [UptimePut3DecVal],eax
  mov   [pUptimePut3DecDst],edi
  call  UptimePut3Dec
  mov   edi,[pUptimePut3DecDst]
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   al,[UptimeHours]
  mov   [Put2DecVal],al
  mov   [pPut2DecDst],edi
  call  Put2Dec
  mov   edi,[pPut2DecDst]
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   al,[UptimeMinutes]
  mov   [Put2DecVal],al
  mov   [pPut2DecDst],edi
  call  Put2Dec
  mov   edi,[pPut2DecDst]
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   al,[UptimeSeconds]
  mov   [Put2DecVal],al
  mov   [pPut2DecDst],edi
  call  Put2Dec
  ret

;--------------------------------------------------------------------------------------------------
; UptimePrint
;   Output:
;     Updates UptimeStr and prints it through VdPutStr plus CnCrLf.
;--------------------------------------------------------------------------------------------------
UptimePrint:
  call  UptimeNow
  mov   eax,[UptimeOutSec]
  mov   [UptimeFmtSec],eax
  call  UptimeFmtYdhms
  mov   eax,UptimeStr
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret

;--------------------------------------------------------------------------------------------------
; Internal Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; UptimePut3Dec
;   Input:
;     UptimePut3DecVal  = value 0..999
;     pUptimePut3DecDst = destination payload pointer
;   Output:
;     [pUptimePut3DecDst original..original+2] = three ASCII decimal digits.
;     pUptimePut3DecDst += 3.
;   Notes:
;     Internal helper for UptimeFmtYdhms.
;--------------------------------------------------------------------------------------------------
UptimePut3Dec:
  mov   edi,[pUptimePut3DecDst]
  mov   eax,[UptimePut3DecVal]
  xor   edx,edx
  mov   ebx,100
  div   ebx                             ; quotient hundreds, remainder
  add   al,'0'
  mov   [edi],al
  inc   edi
  mov   eax,edx
  xor   edx,edx
  mov   ebx,10
  div   ebx                             ; quotient tens, remainder ones
  add   al,'0'
  mov   [edi],al
  mov   al,dl
  add   al,'0'
  mov   [edi+1],al
  add   edi,2
  mov   [pUptimePut3DecDst],edi
  ret
