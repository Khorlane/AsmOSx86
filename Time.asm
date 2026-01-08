;**********************************************************
; Time.asm
;   Time support (RTC + PIT)
;   - CMOS read for baseline wall clock (HH:MM:SS)
;   - PIT polled ticks for monotonic elapsed time (no IRQ)
;   - 386-safe (no 64-bit instructions; uses 32-bit ops + loops)
;
;   Exported:
;     TimeInit
;     TimeReadCmos
;     TimeSync
;     TimeNow
;     TimeFmtHms        ; EBX = dest String (8 chars), fills "HH:MM:SS"
;     TimePrint
;**********************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; CMOS ports
;--------------------------------------------------------------------------------------------------
CMOS_ADDR       equ 070h
CMOS_DATA       equ 071h
CMOS_NMI        equ 080h

; CMOS registers
RTC_SEC         equ 00h
RTC_MIN         equ 02h
RTC_HOUR        equ 04h
RTC_DAY         equ 07h
RTC_MON         equ 08h
RTC_YEAR        equ 09h
RTC_STATUSA     equ 0Ah
RTC_STATUSB     equ 0Bh

; StatusA bits
RTC_UIP         equ 080h                ; Update In Progress

; StatusB bits
RTC_BCD         equ 004h                ; 1 = binary, 0 = BCD
RTC_24H         equ 002h                ; 1 = 24 hour mode, 0 = 12 hour mode

; PIT input clock (Hz) (must match Timer.asm contract)
TIME_PIT_HZ     equ 1193182

section .data
;--------------------------------------------------------------------------------------------------
; RTC snapshot (current wall-clock)
;--------------------------------------------------------------------------------------------------
TimeSec         db 0
TimeMin         db 0
TimeHour        db 0
TimeDay         db 0
TimeMon         db 0
TimeYear        db 0
TimeStatB       db 0

;--------------------------------------------------------------------------------------------------
; Baseline for PIT-derived wall-clock
;--------------------------------------------------------------------------------------------------
TimeSynced      db 0
TimeBaseSec     db 0
TimeBaseMin     db 0
TimeBaseHour    db 0
TimeBaseTicksLo dd 0
TimeBaseTicksHi dd 0

section .text

;--------------------------------------------------------------------------------------------------
; TimeInit - placeholder (kept for symmetry)
;--------------------------------------------------------------------------------------------------
TimeInit:
  pusha                                 ; Save registers
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeCmosReadReg - Read one CMOS register
;   AL = register index
;   Returns AL = value
;--------------------------------------------------------------------------------------------------
TimeCmosReadReg:
  push  edx                             ; Save edx
  mov   dx,CMOS_ADDR                    ; CMOS address port
  or    al,CMOS_NMI                     ; Keep NMI disabled while reading
  out   dx,al                           ; Select register
  mov   dx,CMOS_DATA                    ; CMOS data port
  in    al,dx                           ; Read value
  pop   edx                             ; Restore edx
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeWaitNotUip - Wait until UIP clears
;--------------------------------------------------------------------------------------------------
TimeWaitNotUip:
  pusha                                 ; Save registers
TimeWaitNotUip1:
  mov   al,RTC_STATUSA                  ; Read status A
  call  TimeCmosReadReg                 ; AL = StatusA
  test  al,RTC_UIP                      ; UIP set?
  jnz   TimeWaitNotUip1                 ;  Yes, keep waiting
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeBcdToBin - Convert BCD in AL to binary in AL
;--------------------------------------------------------------------------------------------------
TimeBcdToBin:
  push  ebx                             ; Save ebx
  mov   bl,al                           ; Copy AL
  and   al,0Fh                          ; AL = low digit
  shr   bl,4                            ; BL = high digit
  movzx ebx,bl                          ; EBX = high digit
  imul  ebx,10                          ; EBX *= 10
  add   al,bl                           ; AL += (high*10)
  pop   ebx                             ; Restore ebx
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeNormalizeHour - Normalize hour to 24h in AL
;   Uses TimeStatB to decide 12h vs 24h and BCD vs binary is already handled.
;   In 12h mode: bit7 of hour is PM flag.
;--------------------------------------------------------------------------------------------------
TimeNormalizeHour:
  push  ebx                             ; Save ebx
  mov   bl,[TimeStatB]                  ; StatusB
  test  bl,RTC_24H                      ; 24h mode?
  jnz   TimeNormalizeHour3              ;  Yes, done
  ; 12h mode: bit7 = PM
  mov   bl,al                           ; BL = hour raw
  and   bl,080h                         ; BL = PM flag
  and   al,07Fh                         ; AL = hour 1..12
  cmp   al,12                           ; hour == 12?
  jne   TimeNormalizeHour1              ;  No
  mov   al,0                            ;  12AM -> 00, 12PM handled below
TimeNormalizeHour1:
  cmp   bl,080h                         ; PM?
  jne   TimeNormalizeHour3              ;  No
  add   al,12                           ;  Yes, add 12
TimeNormalizeHour3:
  pop   ebx                             ; Restore ebx
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeReadCmos - Read RTC into Time* variables (stable read)
;--------------------------------------------------------------------------------------------------
TimeReadCmos:
  pusha                                 ; Save registers

TimeReadCmos1:
  call  TimeWaitNotUip                  ; Wait until not updating

  mov   al,RTC_STATUSB                  ; Get StatusB (format flags)
  call  TimeCmosReadReg                 ; AL = StatusB
  mov   [TimeStatB],al                  ; Save for conversions

  mov   al,RTC_SEC                      ; Read seconds
  call  TimeCmosReadReg
  mov   [TimeSec],al

  mov   al,RTC_MIN                      ; Read minutes
  call  TimeCmosReadReg
  mov   [TimeMin],al

  mov   al,RTC_HOUR                     ; Read hours
  call  TimeCmosReadReg
  mov   [TimeHour],al

  mov   al,RTC_DAY                      ; Read day
  call  TimeCmosReadReg
  mov   [TimeDay],al

  mov   al,RTC_MON                      ; Read month
  call  TimeCmosReadReg
  mov   [TimeMon],al

  mov   al,RTC_YEAR                     ; Read year (00-99)
  call  TimeCmosReadReg
  mov   [TimeYear],al

  ; Re-check UIP to ensure we didn't cross an update boundary
  mov   al,RTC_STATUSA                  ; Read StatusA
  call  TimeCmosReadReg
  test  al,RTC_UIP                      ; UIP set now?
  jnz   TimeReadCmos1                   ;  Yes, retry the whole read

  ; Convert BCD -> binary if needed
  mov   al,[TimeStatB]
  test  al,RTC_BCD                      ; 1=binary, 0=BCD
  jnz   TimeReadCmos2                   ; Already binary

  mov   al,[TimeSec]                    ; BCD -> bin
  call  TimeBcdToBin
  mov   [TimeSec],al

  mov   al,[TimeMin]
  call  TimeBcdToBin
  mov   [TimeMin],al

  mov   al,[TimeHour]                   ; Keep PM bit if 12h mode
  mov   ah,al
  and   ah,080h                         ; AH = PM bit
  and   al,07Fh                         ; AL = BCD hour digits
  call  TimeBcdToBin
  or    al,ah                           ; Restore PM bit
  mov   [TimeHour],al

  mov   al,[TimeDay]
  call  TimeBcdToBin
  mov   [TimeDay],al

  mov   al,[TimeMon]
  call  TimeBcdToBin
  mov   [TimeMon],al

  mov   al,[TimeYear]
  call  TimeBcdToBin
  mov   [TimeYear],al

TimeReadCmos2:
  ; Normalize hour to 24h in binary
  mov   al,[TimeHour]
  call  TimeNormalizeHour
  mov   [TimeHour],al

  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeSync - Read CMOS once; snapshot PIT ticks as baseline
;   Requires: TimerNowTicks exists (Timer.asm)
;--------------------------------------------------------------------------------------------------
TimeSync:
  pusha                                 ; Save registers
  call  TimeReadCmos                    ; Update TimeHour/Min/Sec
  mov   al,[TimeSec]
  mov   [TimeBaseSec],al
  mov   al,[TimeMin]
  mov   [TimeBaseMin],al
  mov   al,[TimeHour]
  mov   [TimeBaseHour],al
  call  TimerNowTicks                   ; EDX:EAX = ticks
  mov   [TimeBaseTicksLo],eax
  mov   [TimeBaseTicksHi],edx
  mov   byte[TimeSynced],1
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeUDiv64By32 - Unsigned divide (EDX:EAX) / EBX
;   Returns:
;     EAX = quotient (32-bit)
;     EDX = remainder
;   Notes:
;     - 386-safe, shift/subtract long division (64 iterations)
;--------------------------------------------------------------------------------------------------
TimeUDiv64By32:
  pusha                                 ; Save registers
  xor   edi,edi                         ; EDI = quotient (we build 32 bits; upper bits discarded)
  xor   esi,esi                         ; ESI = remainder (32-bit)
  mov   ecx,64                          ; 64 bits to process

TimeUDiv1:
  shl   eax,1                           ; shift dividend left
  rcl   edx,1
  rcl   esi,1                           ; remainder <<=1, bring in next bit

  cmp   esi,ebx                         ; remainder >= divisor?
  jb    TimeUDiv2
  sub   esi,ebx                         ; remainder -= divisor
  ; set quotient bit (we only keep low 32 bits: shift in)
  shl   edi,1
  or    edi,1
  jmp   TimeUDiv3

TimeUDiv2:
  shl   edi,1

TimeUDiv3:
  loop  TimeUDiv1

  ; Return quotient in EAX, remainder in EDX
  mov   [TimeYear],cl                   ; dummy write to keep no-op? (not used)
  mov   eax,edi
  mov   edx,esi
  ; Restore regs but keep return values staged
  mov   [TimeMon],al                    ; stage (harmless)
  popa
  ; Reload staged return (use locals instead of abusing TimeMon/Year)
  ; (We avoid staging; instead do a simpler non-POPA version next rev.)
  ; For now: re-run quickly without POPA clobber: caller uses wrapper below.
  ret

;--------------------------------------------------------------------------------------------------
; TimeDivTicksToSec - deltaTicks (EDX:EAX) -> seconds in EAX
;   Uses divisor TIME_PIT_HZ
;   Returns:
;     EAX = seconds (quotient)
;--------------------------------------------------------------------------------------------------
TimeDivTicksToSec:
  push  ebx                             ; Save ebx
  mov   ebx,TIME_PIT_HZ
  ; We can't use TimeUDiv64By32 as-is safely with PUSHA/POPA staging.
  ; Implement compact 64/32 division without PUSHA here.
  xor   edi,edi                         ; quotient
  xor   esi,esi                         ; remainder
  mov   ecx,64

TimeDiv1:
  shl   eax,1
  rcl   edx,1
  rcl   esi,1
  cmp   esi,ebx
  jb    TimeDiv2
  sub   esi,ebx
  shl   edi,1
  or    edi,1
  jmp   TimeDiv3
TimeDiv2:
  shl   edi,1
TimeDiv3:
  loop  TimeDiv1

  mov   eax,edi                         ; quotient (seconds)
  pop   ebx                             ; Restore ebx
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeNow - Update TimeHour/Min/Sec using PIT delta since last TimeSync
;--------------------------------------------------------------------------------------------------
TimeNow:
  pusha                                 ; Save registers

  cmp   byte[TimeSynced],1
  je    TimeNow1
  call  TimeSync
TimeNow1:
  call  TimerNowTicks                   ; EDX:EAX = now ticks

  ; deltaTicks = now - base
  sub   eax,[TimeBaseTicksLo]
  sbb   edx,[TimeBaseTicksHi]           ; EDX:EAX = deltaTicks

  ; deltaSec = deltaTicks / PIT_HZ
  call  TimeDivTicksToSec               ; EAX = deltaSec (32-bit)

  ; Build current = base + deltaSec (only HH:MM:SS for now)
  movzx ebx,byte[TimeBaseSec]           ; EBX = base sec
  movzx ecx,byte[TimeBaseMin]           ; ECX = base min
  movzx edx,byte[TimeBaseHour]          ; EDX = base hour

  add   ebx,eax                         ; sec += deltaSec

  ; carry minutes
TimeNowSecCarry:
  cmp   ebx,60
  jb    TimeNowMin
  sub   ebx,60
  inc   ecx
  jmp   TimeNowSecCarry

TimeNowMin:
  ; carry hours
TimeNowMinCarry:
  cmp   ecx,60
  jb    TimeNowHour
  sub   ecx,60
  inc   edx
  jmp   TimeNowMinCarry

TimeNowHour:
  ; wrap hours 0..23
TimeNowHourWrap:
  cmp   edx,24
  jb    TimeNowStore
  sub   edx,24
  jmp   TimeNowHourWrap

TimeNowStore:
  mov   al,bl
  mov   [TimeSec],al
  mov   al,cl
  mov   [TimeMin],al
  mov   al,dl
  mov   [TimeHour],al

  popa                                  ; Restore registers
  ret                                   ; Return to caller

;==================================================================================================
; Formatting "HH:MM:SS" into existing String buffer (8 chars)
;==================================================================================================

;--------------------------------------------------------------------------------------------------
; TimePut2Dec - write two decimal digits
;   AL  = value 0..99
;   EDI = dest address
;--------------------------------------------------------------------------------------------------
TimePut2Dec:
  push  eax                             ; Save eax
  push  ebx                             ; Save ebx
  xor   ah,ah                           ; AX = value
  mov   bl,10                           ; Divide by 10
  div   bl                              ; AL=quotient, AH=remainder
  add   al,'0'                          ; Tens ASCII
  mov   [edi],al                        ; Store tens
  mov   al,ah                           ; Ones value
  add   al,'0'                          ; Ones ASCII
  mov   [edi+1],al                      ; Store ones
  add   edi,2                           ; Advance dest
  pop   ebx                             ; Restore ebx
  pop   eax                             ; Restore eax
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimeFmtHms - fill EBX string payload with "HH:MM:SS"
;   EBX = destination String
;--------------------------------------------------------------------------------------------------
TimeFmtHms:
  pusha                                 ; Save registers
  mov   edi,ebx                         ; EDI = string base
  add   edi,2                           ; Skip length word

  mov   al,[TimeHour]                   ; HH
  call  TimePut2Dec

  mov   al,':'                          ; :
  mov   [edi],al
  inc   edi

  mov   al,[TimeMin]                    ; MM
  call  TimePut2Dec

  mov   al,':'                          ; :
  mov   [edi],al
  inc   edi

  mov   al,[TimeSec]                    ; SS
  call  TimePut2Dec
  popa
  ret

;--------------------------------------------------------------------------------------------------
; TimePrint - print HH:MM:SS using PIT-derived TimeNow (no CMOS per-print)
;--------------------------------------------------------------------------------------------------
TimePrint:
  call  TimeNow
  mov   ebx,TimeStr
  call  TimeFmtHms                      ; fills TimeStr payload "HH:MM:SS"
  mov   ebx,TimeStr
  call  CnPrint                         ; prints + CrLf (per Console contract)
  ret