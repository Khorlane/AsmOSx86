;**************************************************************************************************
; Uptime.asm
;   Uptime reporting (monotonic / TimeMono)
;
;   Display Format:
;     "UP YY:DDD:HH:MM:SS"
;
;   Semantics (LOCKED-IN):
;     - Uptime measures monotonic time since UptimeInit.
;     - The uptime baseline is captured exactly when UptimeInit
;       is called (not at boot by default).
;     - This allows the kernel to define “uptime start” explicitly.
;
;   Initialization Rules:
;     - Kernel MUST call TimerInit before UptimeInit.
;     - Kernel SHOULD call UptimeInit during early boot.
;     - If UptimeNow / UptimePrint is called before UptimeInit,
;       the uptime subsystem will lazily initialize itself
;       using the current monotonic tick as the baseline.
;
;   Kernel-Facing Contract:
;     UptimeInit
;       - Captures the monotonic tick baseline.
;       - Defines the start of uptime measurement.
;
;     UptimeNow
;       - Returns EAX = uptime seconds since UptimeInit.
;       - Uses monotonic time only (never wall time).
;
;     UptimePrint
;       - Formats and prints uptime as "UP YY:DDD:HH:MM:SS".
;       - Always prints via CnPrint (thus always ends with CrLf).
;
;   Requires:
;     TimerNowTicks      ; EDX:EAX = monotonic PIT ticks
;     CnPrint            ; EBX = String, prints + CrLf
;     UptimeStr          ; String  UptimeStr,"UP 00:000:00:00:00"
;
;   Design Guarantees:
;     - Uptime never goes backward.
;     - Uptime is unaffected by wall-time resync or CMOS changes.
;     - Formatting limits and rollover policy are local to Uptime.asm.
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

section .data
String  UptimeStr,"UP YY:DDD:HH:MM:SS"
UptimeBaseLo    dd 0
UptimeBaseHi    dd 0
UptimeRetSec    dd 0                    ; staged return (seconds)

section .text
;--------------------------------------------------------------------------------------------------
; UptimeInit - capture baseline ticks (uptime starts here)
;--------------------------------------------------------------------------------------------------
UptimeInit:
  pusha                                 ; Save registers
  call  TimerNowTicks                   ; Prime TimerNowTicks
  call  TimerNowTicks                   ; Stable read
  mov   [UptimeBaseLo],eax              ; Save baseline ticks
  mov   [UptimeBaseHi],edx
  popa                                  ; Restore registers
  ret

;--------------------------------------------------------------------------------------------------
; UptimeNow - returns uptime seconds since UptimeInit
;   Returns:
;     EAX=seconds
;--------------------------------------------------------------------------------------------------
UptimeNow:
  pusha                                 ; Save registers
  call  TimerNowTicks                   ; EDX:EAX=now ticks
  sub   eax,[UptimeBaseLo]
  sbb   edx,[UptimeBaseHi]              ; EDX:EAX=delta ticks
  mov   ecx,UP_PIT_HZ
  div   ecx                             ; EAX=seconds,EDX=remainder
  mov   [UptimeRetSec],eax              ; stage return (POPA will clobber regs)
  popa
  mov   eax,[UptimeRetSec]
  ret

;--------------------------------------------------------------------------------------------------
; UptimePut2Dec - write two decimal digits
;   AL=value 0..99
;   EDI=dest
;--------------------------------------------------------------------------------------------------
UptimePut2Dec:
  push  eax                             ; Save eax
  push  ebx                             ; Save ebx
  xor   ah,ah
  mov   bl,10
  div   bl                              ; AL=tens,AH=ones
  add   al,'0'
  mov   [edi],al
  mov   al,ah
  add   al,'0'
  mov   [edi+1],al
  add   edi,2
  pop   ebx
  pop   eax
  ret

;--------------------------------------------------------------------------------------------------
; UptimePut3Dec - write three decimal digits
;   EAX=value 0..999
;   EDI=dest
;--------------------------------------------------------------------------------------------------
UptimePut3Dec:
  push  eax                             ; Save eax
  push  ebx                             ; Save ebx
  push  edx                             ; Save edx
  xor   edx,edx
  mov   ebx,100
  div   ebx                             ; EAX=hundreds,EDX=rem
  add   al,'0'
  mov   [edi],al
  inc   edi
  mov   eax,edx
  xor   edx,edx
  mov   ebx,10
  div   ebx                             ; EAX=tens,EDX=ones
  add   al,'0'
  mov   [edi],al
  mov   al,dl
  add   al,'0'
  mov   [edi+1],al
  add   edi,2
  pop   edx
  pop   ebx
  pop   eax
  ret

;--------------------------------------------------------------------------------------------------
; UptimeFmtYdhms - fill UptimeStr payload with "UP YY:DDD:HH:MM:SS"
;   Input:
;     EAX=uptime seconds
;--------------------------------------------------------------------------------------------------
UptimeFmtYdhms:
  pusha                                 ; Save registers
  mov   esi,eax                         ; ESI=total seconds
  mov   eax,esi
  xor   edx,edx
  mov   ebx,UP_SEC_YEAR
  div   ebx                             ; EAX=years_total,EDX=rem_year
  mov   ebp,eax                         ; EBP=years_total
  mov   esi,edx                         ; ESI=rem_year
  mov   eax,ebp
  xor   edx,edx
  mov   ebx,100
  div   ebx                             ; EDX=YY
  mov   ebp,edx                         ; EBP=YY (0..99)
  mov   eax,esi
  xor   edx,edx
  mov   ebx,UP_SEC_DAY
  div   ebx                             ; EAX=DDD,EDX=rem_day
  mov   ecx,eax                         ; ECX=DDD
  mov   esi,edx                         ; ESI=rem_day
  mov   eax,esi
  xor   edx,edx
  mov   ebx,UP_SEC_HOUR
  div   ebx                             ; EAX=HH,EDX=rem_hour
  mov   esi,eax                         ; ESI=HH
  mov   edi,edx                         ; EDI=rem_hour
  mov   eax,edi
  xor   edx,edx
  mov   ebx,UP_SEC_MIN
  div   ebx                             ; EAX=MM,EDX=SS
  mov   ebx,eax                         ; EBX=MM
  ; EDX=SS
  mov   edi,UptimeStr
  add   edi,5                           ; Payload+3 ("UP ")
  mov   eax,ebp                         ; YY
  mov   al,al
  call  UptimePut2Dec
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   eax,ecx                         ; DDD
  call  UptimePut3Dec
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   eax,esi                         ; HH
  mov   al,al
  call  UptimePut2Dec
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   eax,ebx                         ; MM
  mov   al,al
  call  UptimePut2Dec
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   eax,edx                         ; SS
  mov   al,al
  call  UptimePut2Dec
  popa
  ret

;--------------------------------------------------------------------------------------------------
; UptimePrint - print uptime string (always +CrLf via CnPrint)
;--------------------------------------------------------------------------------------------------
UptimePrint:
  pusha
  call  UptimeNow                       ; EAX=seconds
  call  UptimeFmtYdhms                  ; Fill UptimeStr payload
  mov   ebx,UptimeStr
  call  CnPrint
  popa
  ret

;---------------------------------------------------------------------------------------------------
; TimeUptimeFmtHms - EBX=String,formats uptime "HH:MM:SS" (hours mod 100)
;---------------------------------------------------------------------------------------------------
TimeUptimeFmtHms:
  pusha                                 ; Save registers
  mov   ebp,ebx                         ; Save dest String
  cmp   byte[BootValid],1
  je    TimeUptimeFmtHms1
TimeUptimeFmtHms1:
  call  TimerNowTicks                   ; EDX:EAX = now
  sub   eax,[BootLo]
  sbb   edx,[BootHi]                    ; EDX:EAX = uptime_ticks
  mov   ecx,TIME_PIT_HZ
  div   ecx                             ; EAX=uptime_seconds,EDX=rem
  xor   edx,edx
  mov   ecx,3600
  div   ecx                             ; EAX=hours_total,EDX=rem3600
  mov   esi,eax                         ; hours_total
  mov   edi,edx                         ; rem3600
  mov   eax,edi
  xor   edx,edx
  mov   ecx,60
  div   ecx                             ; EAX=minutes,EDX=seconds
  mov   ebx,eax                         ; minutes
  mov   ecx,edx                         ; seconds
  mov   eax,esi
  xor   edx,edx
  mov   edi,100
  div   edi                             ; EDX=hours_mod100
  mov   al,dl                           ; AL=hours (0..99)
  mov   edi,ebp                         ; EDI = String base
  add   edi,2                           ; Skip length word
  call  TimePut2Dec                     ; HH
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   eax,ebx
  mov   al,al
  call  TimePut2Dec                     ; MM
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   eax,ecx
  mov   al,al
  call  TimePut2Dec                     ; SS
  popa
  ret