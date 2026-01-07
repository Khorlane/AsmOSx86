;**********************************************************
; Time.asm
;   CMOS date/time support (RTC)
;   - Safe read (UIP stable)
;   - BCD or binary
;   - 12h or 24h
;   - 386-safe (no 64-bit ops)
;
;   Exported:
;     TimeInit
;     TimeReadCmos
;     TimeFmtHms        ; EBX = dest String (8 chars), fills "HH:MM:SS"
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

;--------------------------------------------------------------------------------------------------
; Working storage (kept local to Time.asm)
;--------------------------------------------------------------------------------------------------
section .data
TimeSec         db 0
TimeMin         db 0
TimeHour        db 0
TimeDay         db 0
TimeMon         db 0
TimeYear        db 0
TimeStatB       db 0

section .text
;--------------------------------------------------------------------------------------------------
; TimeInit - placeholder for later
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

;==================================================================================================
; STEP 1: Format HH:MM:SS into an existing String buffer (8 chars)
;   Contract:
;     - EBX = address of destination String (must have 8 bytes payload)
;     - Writes bytes at [EBX+2 .. EBX+9] as: "HH:MM:SS"
;     - Does NOT print. (Console will print it later.)
;==================================================================================================

;--------------------------------------------------------------------------------------------------
; TimePut2Dec - write two decimal digits
;   AL  = value 0..99
;   EDI = dest address
;   Writes: tens, ones. Advances EDI by 2.
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

  popa                                  ; Restore registers
  ret                                   ; Return to caller

TimePrint:
  call  TimeReadCmos                    ; read RTC into TimeHour/Min/Sec
  mov   ebx,TimeStr
  call  TimeFmtHms                      ; fills TimeStr payload "HH:MM:SS"
  mov   ebx,TimeStr
  call  CnPrint                         ; prints + CrLf (per Console contract)
  ret