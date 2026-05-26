;**************************************************************************************************
; Time.asm
;   Time support (RTC + PIT)
;   - CMOS read for baseline wall clock (YYYY-MM-DD HH:MM:SS)
;   - PIT polled ticks for monotonic elapsed time (no IRQ)
;   - 386-safe (no 64-bit instructions; uses Hi/Lo dword pairs)
;
; TIME CONTRACTS — MONOTONIC (UPTIME) vs WALL (CALENDAR)
;
; Purpose
;   AsmOSx86 treats “time” as TWO separate services:
;     (A) TimeMono  = monotonic uptime time (never goes backward,never jumps)
;     (B) TimeWall  = wall/calendar time (human-readable; may jump/correct)
;
; Rule of Use
;   - Use TimeMono (Timer*) for: delays,timeouts,scheduling,profiling,uptime.
;   - Use TimeWall (Time*)  for: timestamps,logs,human-readable clock display.
;
; Ownership (LOCKED-IN)
;   - All wall time logic lives in Time.asm.
;   - Monotonic time lives in Timer.asm / Uptime.asm.
;   - The kernel MUST NOT read CMOS or PIT directly.
;   - CMOS,PIT,resync,and future IRQ handling are internal details.
;
; Dependencies
;   - Requires Timer.asm contract:
;       TimerInit
;       TimerNowTicks     ; outputs TimerOutTicksHi:TimerOutTicksLo
;
; Resync Policy (B,locked-in for now)
;   - TimeNow will resync wall baseline every 60 seconds of monotonic time.
;   - Resync reads CMOS once and snaps wall baseline (wall may jump).
;
; Public API
;   TimeDtPrint
;   TimeTmPrint
;
; Internal
;   TimeSync
;   TimeNow
;   TimeFmtHms
;   TimeFmtYmd
;**************************************************************************************************

[bits 32]

;---------------------------------------------------------------------------------------------------
; CMOS ports
;---------------------------------------------------------------------------------------------------
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
RTC_CENTURY     equ 32h                 ; If present (common in emulators/BIOS)
RTC_STATUSA     equ 0Ah
RTC_STATUSB     equ 0Bh
; StatusA bits
RTC_UIP         equ 080h
; StatusB bits
RTC_BCD         equ 004h                ; 1=binary,0=BCD
RTC_24H         equ 002h                ; 1=24h,0=12h

;---------------------------------------------------------------------------------------------------
; PIT clock constants
;---------------------------------------------------------------------------------------------------
TIME_PIT_HZ     equ 1193182
TIME_DAY_SEC    equ 86400
TIME_RSYNC_SEC  equ 60
TIME_RSYNC_TLO  equ (TIME_PIT_HZ*TIME_RSYNC_SEC) & 0FFFFFFFFh
TIME_RSYNC_THI  equ (TIME_PIT_HZ*TIME_RSYNC_SEC) >> 32

;---------------------------------------------------------------------------------------------------
; Strings
;---------------------------------------------------------------------------------------------------
String  DateStr,"YYYY-MM-DD"
String  TimeStr,"HH:MM:SS"

;---------------------------------------------------------------------------------------------------
; Raw CMOS fields (binary,24h after TimeReadCmos)
;---------------------------------------------------------------------------------------------------
; TimeYear is stored as a full year (e.g. 2026).
; TimeDay/TimeMon are day-of-month and month.
TimeSec         db 0
TimeMin         db 0
TimeHour        db 0
TimeDay         db 0
TimeMon         db 0
TimeYear        dw 0                    ; full year (e.g., 2026)
TimeCent        db 0
TimeStatB       db 0
TimeTmp         db 0                    ; temp byte for CMOS reads (century, etc.)
TimePmBit       db 0                    ; temp: PM bit staging for hour conversion
TimeCmosReg     db 0                    ; input: CMOS register index
TimeCmosVal     db 0                    ; output: CMOS register value
TimeBcdIn       db 0                    ; input: packed BCD value
TimeBcdOut      db 0                    ; output: binary value
TimeHourRaw     db 0                    ; input: raw RTC hour value
TimeHourNorm    db 0                    ; output: normalized 24-hour value
TimeDaysAdd     dd 0                    ; input/work: number of whole days to add
pTimeFmtDst     dd 0                    ; input: destination Str pointer for TimeFmt* routines
pTimePut4DecDst dd 0                    ; input/output: destination payload pointer
TimePut4DecVal  dw 0                    ; input: value 0..9999
TimeMonthLen    db 0                    ; output: days in current month
TimeLeapOut     db 0                    ; output: 1 if leap year, else 0
TimeMonthDays   db 31,28,31,30,31,30,31,31,30,31,30,31

;---------------------------------------------------------------------------------------------------
; Wall time state
;---------------------------------------------------------------------------------------------------
WallSecDay      dd 0                    ; 0..86399
WallRemTicks    dd 0                    ; 0..TIME_PIT_HZ-1
WallLastLo      dd 0                    ; last mono tick observed by TimeNow
WallLastHi      dd 0
WallSyncLo      dd 0                    ; mono tick at last TimeSync
WallSyncHi      dd 0
WallSyncValid   db 0

;---------------------------------------------------------------------------------------------------
; Legacy time storage
;   Reserved / unused in current wall-time implementation.
;---------------------------------------------------------------------------------------------------
BootLo          dd 0
BootHi          dd 0
BootValid       db 0

;---------------------------------------------------------------------------------------------------
; TimeNow - advance wall date/time from monotonic ticks and resync with CMOS as needed
;---------------------------------------------------------------------------------------------------
TimeNow:
  cmp   byte[WallSyncValid],1
  je    TimeNow1
  call  TimeSync
  jmp   TimeNow4
TimeNow1:
  call  TimerNowTicks                   ; TimerOutTicksHi:TimerOutTicksLo = mono_now
  mov   esi,[TimerOutTicksLo]           ; now_lo
  mov   edi,[TimerOutTicksHi]           ; now_hi
  ; since_sync = mono_now - WallSync
  mov   eax,esi
  mov   edx,edi
  sub   eax,[WallSyncLo]
  sbb   edx,[WallSyncHi]
  cmp   edx,TIME_RSYNC_THI
  jb    TimeNow3
  ja    TimeNow2
  cmp   eax,TIME_RSYNC_TLO
  jb    TimeNow3
TimeNow2:
  call  TimeSync
  jmp   TimeNow4
TimeNow3:
  ; delta = mono_now - WallLast
  mov   eax,esi
  mov   edx,edi
  sub   eax,[WallLastLo]
  sbb   edx,[WallLastHi]
  mov   [WallLastLo],esi
  mov   [WallLastHi],edi
  ; total = delta_lo + WallRemTicks
  add   eax,[WallRemTicks]
  adc   edx,0
  ; seconds_add = total / TIME_PIT_HZ,rem = total % TIME_PIT_HZ
  mov   ecx,TIME_PIT_HZ
  div   ecx                             ; EAX=seconds_add,EDX=rem
  mov   [WallRemTicks],edx
  ; Advance sec-of-day and carry whole-day rollover into the calendar date.
  mov   ebx,[WallSecDay]
  add   ebx,eax
  mov   eax,ebx
  xor   edx,edx
  mov   ecx,TIME_DAY_SEC
  div   ecx                             ; EAX=days_add,EDX=sec_of_day
  mov   [WallSecDay],edx
  test  eax,eax
  jz    TimeNow4
  mov   [TimeDaysAdd],eax
  call  TimeAddDays
TimeNow4:
  ; Derive H:M:S from WallSecDay into TimeHour/Min/Sec
  mov   eax,[WallSecDay]
  xor   edx,edx
  mov   ecx,3600
  div   ecx                             ; EAX=hour,EDX=rem
  mov   [TimeHour],al
  mov   eax,edx
  xor   edx,edx
  mov   ecx,60
  div   ecx                             ; EAX=min,EDX=sec
  mov   [TimeMin],al
  mov   [TimeSec],dl
  ret

;---------------------------------------------------------------------------------------------------
; TimeSync - read CMOS once and pin wall baseline to a monotonic tick
;---------------------------------------------------------------------------------------------------
TimeSync:
  call  TimeReadCmos                    ; updates TimeHour/Min/Sec
  xor   eax,eax
  mov   al,[TimeHour]
  mov   ebx,3600
  mul   ebx                             ; EAX = hour*3600
  mov   ecx,eax
  xor   eax,eax
  mov   al,[TimeMin]
  mov   ebx,60
  mul   ebx                             ; EAX = min*60
  add   ecx,eax
  xor   eax,eax
  mov   al,[TimeSec]
  add   ecx,eax
  mov   [WallSecDay],ecx
  call  TimerNowTicks                   ; TimerOutTicksHi:TimerOutTicksLo = now
  mov   eax,[TimerOutTicksLo]
  mov   edx,[TimerOutTicksHi]
  mov   [WallSyncLo],eax
  mov   [WallSyncHi],edx
  mov   [WallLastLo],eax
  mov   [WallLastHi],edx
  mov   dword[WallRemTicks],0
  mov   byte[WallSyncValid],1
  ret

;---------------------------------------------------------------------------------------------------
; TimeReadCmos - reads RTC date/time into Time* fields (binary,24h)
;   Output (after return):
;     TimeHour/Min/Sec  = 0..23 / 0..59 / 0..59
;     TimeDay           = 1..31
;     TimeMon           = 1..12
;     TimeYear          = full year (e.g. 2026)
;   Notes:
;     - Handles BCD or binary RTC based on RTC_STATUSB (RTC_BCD bit).
;     - Handles 12h vs 24h using TimeNormalizeHour (RTC_24H bit).
;     - Uses a single RTC field read after UIP=0, then verifies UIP stayed clear.
;---------------------------------------------------------------------------------------------------
TimeReadCmos:
  call  TimeWaitNotUip                  ; Wait until RTC not updating (UIP=0)
  mov   al,RTC_STATUSB                  ; Read Status B (format flags)
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  mov   [TimeStatB],al
  mov   al,RTC_SEC                      ; Read seconds
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  mov   [TimeSec],al
  mov   al,RTC_MIN                      ; Read minutes
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  mov   [TimeMin],al
  mov   al,RTC_HOUR                     ; Read hours (may include PM bit in 12h mode)
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  mov   [TimeHour],al
  mov   al,RTC_DAY                      ; Read day of month
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  mov   [TimeDay],al
  mov   al,RTC_MON                      ; Read month
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  mov   [TimeMon],al
  mov   al,RTC_YEAR                     ; Read year (00..99)
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  mov   [TimeCent],al                   ; Temporarily stash YY in TimeCent (byte)
  mov   al,RTC_CENTURY                  ; Read century (e.g. 20)
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  mov   [TimeTmp],al                    ; TEMP byte storage (see note below)
  mov   al,RTC_STATUSA                  ; Verify UIP didn't flip during reads
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  test  al,RTC_UIP
  jnz   TimeReadCmos                    ; If updating started, retry
  ; If RTC provides BCD (RTC_BCD bit == 0), convert fields BCD->binary.
  mov   al,[TimeStatB]
  test  al,RTC_BCD
  jnz   TimeReadCmos1                   ; If RTC_BCD=1 => already binary
  mov   al,[TimeSec]                    ; SEC
  mov   [TimeBcdIn],al
  call  TimeBcdToBin
  mov   al,[TimeBcdOut]
  mov   [TimeSec],al
  mov   al,[TimeMin]                    ; MIN
  mov   [TimeBcdIn],al
  call  TimeBcdToBin
  mov   al,[TimeBcdOut]
  mov   [TimeMin],al
  mov   al,[TimeHour]                   ; HOUR (preserve PM bit if present)
  mov   ah,al
  and   ah,080h                         ; PM bit
  mov   [TimePmBit],ah                  ; stage PM bit (calls clobber regs)
  and   al,07Fh
  mov   [TimeBcdIn],al
  call  TimeBcdToBin
  mov   al,[TimeBcdOut]
  mov   ah,[TimePmBit]
  or    al,ah
  mov   [TimeHour],al
  mov   al,[TimeDay]                    ; DAY
  mov   [TimeBcdIn],al
  call  TimeBcdToBin
  mov   al,[TimeBcdOut]
  mov   [TimeDay],al
  mov   al,[TimeMon]                    ; MON
  mov   [TimeBcdIn],al
  call  TimeBcdToBin
  mov   al,[TimeBcdOut]
  mov   [TimeMon],al
  mov   al,[TimeCent]                   ; YY (stored in TimeCent temporarily)
  mov   [TimeBcdIn],al
  call  TimeBcdToBin
  mov   al,[TimeBcdOut]
  mov   [TimeCent],al                   ; TimeCent now holds YY in binary
  mov   al,[TimeTmp]                     ; CENTURY
  mov   [TimeBcdIn],al
  call  TimeBcdToBin
  mov   al,[TimeBcdOut]
  mov   [TimeTmp],al                     ; temp now holds CC in binary
TimeReadCmos1:
  ; Normalize hour to 24h if needed
  mov   al,[TimeHour]
  mov   [TimeHourRaw],al
  call  TimeNormalizeHour
  mov   al,[TimeHourNorm]
  mov   [TimeHour],al
  ; Build full year: TimeYear = (CC*100 + YY) if CC present, else 19/20 pivot + YY
  xor   eax,eax
  mov   al,[TimeCent]                   ; AL = YY (0..99)
  movzx ebx,al                          ; EBX = YY
  xor   eax,eax
  mov   al,[TimeTmp]                    ; AL = CC (0 if not present / unreadable)
  test  al,al
  jz    TimeReadCmos2                   ; No century => use pivot
  movzx eax,al                          ; EAX = CC
  imul  eax,100                         ; EAX = CC*100
  add   eax,ebx                         ; EAX = CC*100 + YY
  mov   [TimeYear],ax                   ; store full year
  jmp   TimeReadCmos4
TimeReadCmos2:
  ; No century register: pick 19xx vs 20xx using YY pivot
  ; Pivot policy: YY >= 80 => 19YY, else 20YY
  cmp   bl,80                           ; YY >= 80 ?
  jb    TimeReadCmos3                   ;  No -> 20YY
  mov   eax,1900
  add   eax,ebx                         ; 1900 + YY
  mov   [TimeYear],ax
  jmp   TimeReadCmos4
TimeReadCmos3:
  mov   eax,2000
  add   eax,ebx                         ; 2000 + YY
  mov   [TimeYear],ax
TimeReadCmos4:
  ret

;---------------------------------------------------------------------------------------------------
; TimeAddDays
;   Input:
;     TimeDaysAdd = number of whole days to add
;     TimeDay/TimeMon/TimeYear = current calendar date
;   Output:
;     TimeDay/TimeMon/TimeYear advanced by TimeDaysAdd days
;     TimeDaysAdd = 0 after all requested days are applied
;   Clobbers:
;     EAX, AL, BL, CX, DL
;---------------------------------------------------------------------------------------------------
TimeAddDays:
  mov   eax,[TimeDaysAdd]
  test  eax,eax
  jz    TimeAddDays4
TimeAddDays1:
  call  TimeDaysInMonth                 ; TimeMonthLen = days in current month
  mov   al,[TimeMonthLen]
  mov   dl,[TimeDay]
  inc   dl                              ; candidate next day
  cmp   dl,al
  jbe   TimeAddDays3
  mov   dl,1
  mov   bl,[TimeMon]
  inc   bl
  cmp   bl,13
  jb    TimeAddDays2
  mov   bl,1
  mov   cx,[TimeYear]
  inc   cx
  mov   [TimeYear],cx
TimeAddDays2:
  mov   [TimeMon],bl
TimeAddDays3:
  mov   [TimeDay],dl
  mov   eax,[TimeDaysAdd]
  dec   eax
  mov   [TimeDaysAdd],eax
  jnz   TimeAddDays1
TimeAddDays4:
  ret

;---------------------------------------------------------------------------------------------------
; TimeDaysInMonth
;   Input:
;     TimeMon  = month 1..12
;     TimeYear = full year
;   Output:
;     TimeMonthLen = number of days in the current month
;   Clobbers:
;     AL, EBX
;---------------------------------------------------------------------------------------------------
TimeDaysInMonth:
  movzx ebx,byte[TimeMon]
  dec   ebx
  mov   al,[TimeMonthDays+ebx]
  mov   [TimeMonthLen],al
  cmp   byte[TimeMon],2
  jne   TimeDaysInMonth2
  call  TimeIsLeapYear                  ; TimeLeapOut = 1 if leap year
  mov   al,[TimeLeapOut]
  test  al,al
  jz    TimeDaysInMonth1
  mov   al,29
  mov   [TimeMonthLen],al
  ret
TimeDaysInMonth1:
  mov   al,28
  mov   [TimeMonthLen],al
TimeDaysInMonth2:
  ret

;---------------------------------------------------------------------------------------------------
; TimeIsLeapYear
;   Input:
;     TimeYear = full year
;   Output:
;     TimeLeapOut = 1 if leap year, else 0
;   Clobbers:
;     EAX, ECX, EDX
;---------------------------------------------------------------------------------------------------
TimeIsLeapYear:
  movzx eax,word[TimeYear]
  xor   edx,edx
  mov   ecx,4
  div   ecx
  test  edx,edx
  jnz   TimeIsLeapYear1
  movzx eax,word[TimeYear]
  xor   edx,edx
  mov   ecx,100
  div   ecx
  test  edx,edx
  jnz   TimeIsLeapYear2
  movzx eax,word[TimeYear]
  xor   edx,edx
  mov   ecx,400
  div   ecx
  test  edx,edx
  jnz   TimeIsLeapYear1
TimeIsLeapYear2:
  mov   al,1
  mov   [TimeLeapOut],al
  ret
TimeIsLeapYear1:
  xor   al,al
  mov   [TimeLeapOut],al
  ret

;---------------------------------------------------------------------------------------------------
; Time print functions
;---------------------------------------------------------------------------------------------------

;---------------------------------------------------------------------------------------------------
; TimeTmPrint - public wall-time API: prints current wall time (HH:MM:SS)
;---------------------------------------------------------------------------------------------------
TimeTmPrint:
  call  TimeNow
  mov   eax,TimeStr
  mov   [pTimeFmtDst],eax
  call  TimeFmtHms
  mov   eax,TimeStr
  mov   [pVdStr],eax
  call  VdPutStr
  ret

;---------------------------------------------------------------------------------------------------
; TimeDtPrint - public wall-time API: prints current wall date (YYYY-MM-DD)
;---------------------------------------------------------------------------------------------------
TimeDtPrint:
  call  TimeNow
  mov   eax,DateStr
  mov   [pTimeFmtDst],eax
  call  TimeFmtYmd
  mov   eax,DateStr
  mov   [pVdStr],eax
  call  VdPutStr
  ret

;---------------------------------------------------------------------------------------------------
; TimeFmtHms
;   Input:
;     pTimeFmtDst = destination Str
;     TimeHour/TimeMin/TimeSec = current wall clock time
;   Output:
;     Destination payload updated to "HH:MM:SS"
;   Clobbers:
;     AL, EDI
;---------------------------------------------------------------------------------------------------
TimeFmtHms:
  mov   edi,[pTimeFmtDst]
  add   edi,2
  mov   [pPut2DecDst],edi
  mov   al,[TimeHour]
  mov   [Put2DecVal],al
  call  Put2Dec
  mov   edi,[pPut2DecDst]
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   [pPut2DecDst],edi
  mov   al,[TimeMin]
  mov   [Put2DecVal],al
  call  Put2Dec
  mov   edi,[pPut2DecDst]
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   [pPut2DecDst],edi
  mov   al,[TimeSec]
  mov   [Put2DecVal],al
  call  Put2Dec
  ret

;---------------------------------------------------------------------------------------------------
; TimeFmtYmd
;   Input:
;     pTimeFmtDst = destination Str
;     TimeYear/TimeMon/TimeDay = current wall clock date
;   Output:
;     Destination payload updated to "YYYY-MM-DD"
;   Clobbers:
;     AL, AX, EAX, EDX, EDI
;---------------------------------------------------------------------------------------------------
TimeFmtYmd:
  mov   edi,[pTimeFmtDst]
  add   edi,2                           ; Skip length word
  mov   [pTimePut4DecDst],edi
  mov   ax,[TimeYear]                   ; YYYY
  mov   [TimePut4DecVal],ax
  call  TimePut4Dec
  mov   edi,[pTimePut4DecDst]
  mov   al,'-'
  mov   [edi],al
  inc   edi
  mov   [pPut2DecDst],edi
  mov   al,[TimeMon]                    ; MM
  mov   [Put2DecVal],al
  call  Put2Dec
  mov   edi,[pPut2DecDst]
  mov   al,'-'
  mov   [edi],al
  inc   edi
  mov   [pPut2DecDst],edi
  mov   al,[TimeDay]                    ; DD
  mov   [Put2DecVal],al
  call  Put2Dec
  ret

;---------------------------------------------------------------------------------------------------
; Helper functions
;---------------------------------------------------------------------------------------------------

;---------------------------------------------------------------------------------------------------
; TimeBcdToBin
;   Input:
;     TimeBcdIn = packed BCD value
;   Output:
;     TimeBcdOut = binary value
;   Clobbers:
;     AL, BL, EBX
;---------------------------------------------------------------------------------------------------
TimeBcdToBin:
  mov   al,[TimeBcdIn]
  mov   bl,al
  and   al,0Fh
  shr   bl,4
  movzx ebx,bl
  imul  ebx,10
  add   al,bl
  mov   [TimeBcdOut],al
  ret

;---------------------------------------------------------------------------------------------------
; TimeCmosReadReg
;   Input:
;     TimeCmosReg = CMOS register index
;   Output:
;     TimeCmosVal = CMOS register value
;   Clobbers:
;     AL, DX
;---------------------------------------------------------------------------------------------------
TimeCmosReadReg:
  mov   al,[TimeCmosReg]
  mov   dx,CMOS_ADDR
  or    al,CMOS_NMI                     ; NMI off while reading
  out   dx,al
  mov   dx,CMOS_DATA
  in    al,dx
  mov   [TimeCmosVal],al
  ret

;---------------------------------------------------------------------------------------------------
; TimeNormalizeHour
;   Input:
;     TimeHourRaw = RTC hour value, may include PM bit in 12h mode
;     TimeStatB   = RTC status B format flags
;   Output:
;     TimeHourNorm = normalized 24-hour value 0..23
;   Clobbers:
;     AL, BL
;---------------------------------------------------------------------------------------------------
TimeNormalizeHour:
  mov   al,[TimeHourRaw]
  mov   bl,[TimeStatB]
  test  bl,RTC_24H
  jnz   TimeNormalizeHour2
  mov   bl,al
  and   bl,080h                         ; PM flag
  and   al,07Fh                         ; 1..12
  cmp   al,12
  jne   TimeNormalizeHour1
  mov   al,0                            ; 12AM -> 00
TimeNormalizeHour1:
  cmp   bl,080h
  jne   TimeNormalizeHour2
  add   al,12                           ; PM add 12
TimeNormalizeHour2:
  mov   [TimeHourNorm],al
  ret

;---------------------------------------------------------------------------------------------------
; TimePut4Dec
;   Input:
;     TimePut4DecVal  = value 0..9999
;     pTimePut4DecDst = destination payload pointer
;   Output:
;     [pTimePut4DecDst original..original+3] = four ASCII decimal digits
;     pTimePut4DecDst += 4
;   Clobbers:
;     AL, AX, EAX, EDX, BL, EBX, EDI
;---------------------------------------------------------------------------------------------------
TimePut4Dec:
  mov   edi,[pTimePut4DecDst]
  movzx eax,word[TimePut4DecVal]
  xor   edx,edx
  mov   ebx,1000
  div   ebx                             ; EAX=thousands,EDX=rem
  add   al,'0'
  mov   [edi],al
  inc   edi
  mov   eax,edx
  xor   edx,edx
  mov   ebx,100
  div   ebx                             ; EAX=hundreds,EDX=rem
  add   al,'0'
  mov   [edi],al
  inc   edi
  mov   eax,edx
  xor   edx,edx
  mov   bl,10
  div   bl                              ; AL=tens,AH=ones
  add   al,'0'
  mov   [edi],al
  mov   al,ah
  add   al,'0'
  mov   [edi+1],al
  add   edi,2
  mov   [pTimePut4DecDst],edi
  ret

;---------------------------------------------------------------------------------------------------
; TimeWaitNotUip
;   Output:
;     Returns only after RTC UIP flag is observed clear.
;   Clobbers:
;     AL, DX
;---------------------------------------------------------------------------------------------------
TimeWaitNotUip:
  mov   al,RTC_STATUSA
  mov   [TimeCmosReg],al
  call  TimeCmosReadReg
  mov   al,[TimeCmosVal]
  test  al,RTC_UIP
  jnz   TimeWaitNotUip
  ret
