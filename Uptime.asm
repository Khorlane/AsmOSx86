;**********************************************************
; Uptime.asm
;   Uptime reporting (monotonic / TimeMono)
;
;   Display policy (locked-in for now)
;     - Prints: "UP HH:MM:SS"
;     - HH is (total_hours % 100)
;
;   Kernel-facing contract
;     UptimeInit
;     UptimeNow              ; EAX=uptime seconds since UptimeInit
;     UptimePrint            ; prints via UptimeStr + CnPrint
;**********************************************************

[bits 32]

;---------------------------------------------------------------------------------------------------
; PIT clock constants (must match Timer.asm)
;---------------------------------------------------------------------------------------------------
UP_PIT_HZ       equ 1193182
UP_SEC_HOUR     equ 3600
UP_SEC_MIN      equ 60

section .data
UptimeBaseLo    dd 0
UptimeBaseHi    dd 0
UptimeInitDone  db 0
UptimeRetSec    dd 0

section .text

;---------------------------------------------------------------------------------------------------
; UptimeInit - capture baseline ticks (uptime starts here)
;---------------------------------------------------------------------------------------------------
UptimeInit:
  pusha                                 ; Save registers
  call  TimerNowTicks                   ; Prime internal last-count (may return 0)
  call  TimerNowTicks                   ; Second read is stable
  mov   [UptimeBaseLo],eax              ; Save baseline ticks
  mov   [UptimeBaseHi],edx
  mov   byte[UptimeInitDone],1
  popa
  ret

;---------------------------------------------------------------------------------------------------
; UptimeNow - compute uptime seconds since baseline
;   Returns:
;     EAX = seconds since UptimeInit (floor)
;---------------------------------------------------------------------------------------------------
UptimeNow:
  pusha                                 ; Save registers
  cmp   byte[UptimeInitDone],1
  je    .HaveInit
  call  UptimeInit
.HaveInit:
  call  TimerNowTicks                   ; EDX:EAX = now ticks

  sub   eax,[UptimeBaseLo]              ; delta lo
  sbb   edx,[UptimeBaseHi]              ; delta hi

  mov   ecx,UP_PIT_HZ
  div   ecx                             ; EAX=seconds,EDX=remainder

  mov   [UptimeRetSec],eax              ; Stage return (POPA-safe)
  popa
  mov   eax,[UptimeRetSec]
  ret

;---------------------------------------------------------------------------------------------------
; UptimePut2DecAt - write two decimal digits
;   AL  = value 0..99
;   EDI = dest address
;   Writes: tens,ones. Advances EDI by 2.
;---------------------------------------------------------------------------------------------------
UptimePut2DecAt:
  push  eax
  push  ebx
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

;---------------------------------------------------------------------------------------------------
; UptimeFmtHmsAt - format uptime into an existing buffer
;   Input:
;     EAX = uptime seconds (0..)
;     EBX = dest pointer to first digit of HH (tens)
;   Output:
;     Writes 8 chars: "HH:MM:SS"
;---------------------------------------------------------------------------------------------------
UptimeFmtHmsAt:
  pusha
  mov   edi,ebx                         ; Dest

  xor   edx,edx
  mov   ecx,UP_SEC_HOUR
  div   ecx                             ; EAX=hours_total,EDX=rem3600
  mov   esi,eax                         ; hours_total
  mov   eax,edx                         ; rem3600

  xor   edx,edx
  mov   ecx,UP_SEC_MIN
  div   ecx                             ; EAX=minutes,EDX=seconds
  mov   ebx,eax                         ; minutes
  mov   ecx,edx                         ; seconds

  mov   eax,esi
  xor   edx,edx
  mov   esi,100
  div   esi                             ; EDX=hours_mod100

  mov   al,dl                           ; HH
  call  UptimePut2DecAt

  mov   al,':'
  mov   [edi],al
  inc   edi

  mov   eax,ebx                         ; MM
  mov   al,al
  call  UptimePut2DecAt

  mov   al,':'
  mov   [edi],al
  inc   edi

  mov   eax,ecx                         ; SS
  mov   al,al
  call  UptimePut2DecAt

  popa
  ret

;---------------------------------------------------------------------------------------------------
; UptimePrint - print "UP HH:MM:SS" (always + CrLf via CnPrint)
;---------------------------------------------------------------------------------------------------
UptimePrint:
  pusha
  call  UptimeNow                       ; EAX=uptime seconds

  mov   ebx,UptimeStr
  add   ebx,5                           ; Base+2 payload +3 ("UP ") => HH tens
  call  UptimeFmtHmsAt                  ; Fill HH:MM:SS in-place

  mov   ebx,UptimeStr
  call  CnPrint
  popa
  ret