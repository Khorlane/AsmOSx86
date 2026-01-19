;**************************************************************************************************
; Time.asm
;   Time support (RTC + PIT)
;   - CMOS read for baseline wall clock (YYYY-MM-DD HH:MM:SS)
;   - PIT polled ticks for monotonic elapsed time (no IRQ)
;   - 386-safe (no 64-bit instructions; uses EDX:EAX pairs)
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
;   - All wall time logic lives in Time.asm; monotonic lives in Timer/Uptime” (or similar).
;   - The kernel MUST NOT read CMOS or PIT directly.
;   - CMOS,PIT,resync,and future IRQ handling are internal details.
;
; Dependencies
;   - Requires Timer.asm contract:
;       TimerInit
;       TimerNowTicks     ; returns EDX:EAX ticks (PIT input ticks)
;   - Requires Kernel working storage:
;       String  TimeStr,"XXXXXXXX"   ; payload 8 chars
;
; Resync Policy (B,locked-in for now)
;   - TimeNow will resync wall baseline every 60 seconds of monotonic time.
;   - Resync reads CMOS once and snaps wall baseline (wall may jump).
;
; Exported
;   TimeSync
;   TimeNow
;   TimeFmtHms
;   TimeTmPrint
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
; Uptime baseline (boot ticks)
;---------------------------------------------------------------------------------------------------
BootLo          dd 0
BootHi          dd 0
BootValid       db 0

;---------------------------------------------------------------------------------------------------
; TimeNow - advance wall time using monotonic ticks and sync with CMOS as needed
;---------------------------------------------------------------------------------------------------
TimeNow:
  pusha
  cmp   byte[WallSyncValid],1
  je    TimeNow1
  call  TimeSync
  jmp   TimeNow4
TimeNow1:
  call  TimerNowTicks                   ; EDX:EAX = mono_now
  mov   esi,eax                         ; now_lo
  mov   edi,edx                         ; now_hi
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
  ; WallSecDay = (WallSecDay + seconds_add) % 86400
  mov   ebx,[WallSecDay]
  add   ebx,eax
  mov   eax,ebx
  xor   edx,edx
  mov   ecx,TIME_DAY_SEC
  div   ecx                             ; EDX=sec_of_day
  mov   [WallSecDay],edx
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
  popa
  ret

;---------------------------------------------------------------------------------------------------
; TimeSync - read CMOS once and pin wall baseline to a monotonic tick
;---------------------------------------------------------------------------------------------------
TimeSync:
  pusha
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
  call  TimerNowTicks                   ; EDX:EAX = now
  mov   [WallSyncLo],eax
  mov   [WallSyncHi],edx
  mov   [WallLastLo],eax
  mov   [WallLastHi],edx
  mov   dword[WallRemTicks],0
  mov   byte[WallSyncValid],1
  popa
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
;     - Reads CMOS twice-stable: waits for UIP=0, reads fields, verifies UIP still 0.
;---------------------------------------------------------------------------------------------------
TimeReadCmos:
  pusha                                 ; Save registers
TimeReadCmos1:
  call  TimeWaitNotUip                  ; Wait until RTC not updating (UIP=0)
  mov   al,RTC_STATUSB                  ; Read Status B (format flags)
  call  TimeCmosReadReg
  mov   [TimeStatB],al
  mov   al,RTC_SEC                      ; Read seconds
  call  TimeCmosReadReg
  mov   [TimeSec],al
  mov   al,RTC_MIN                      ; Read minutes
  call  TimeCmosReadReg
  mov   [TimeMin],al
  mov   al,RTC_HOUR                     ; Read hours (may include PM bit in 12h mode)
  call  TimeCmosReadReg
  mov   [TimeHour],al
  mov   al,RTC_DAY                      ; Read day of month
  call  TimeCmosReadReg
  mov   [TimeDay],al
  mov   al,RTC_MON                      ; Read month
  call  TimeCmosReadReg
  mov   [TimeMon],al
  mov   al,RTC_YEAR                     ; Read year (00..99)
  call  TimeCmosReadReg
  mov   [TimeCent],al                   ; Temporarily stash YY in TimeCent (byte)
  mov   al,RTC_CENTURY                  ; Read century (e.g. 20)
  call  TimeCmosReadReg
  mov   [TimeTmp],al                    ; TEMP byte storage (see note below)
  mov   al,RTC_STATUSA                  ; Verify UIP didn't flip during reads
  call  TimeCmosReadReg
  test  al,RTC_UIP
  jnz   TimeReadCmos1                   ; If updating started, retry
  ; If RTC provides BCD (RTC_BCD bit == 0), convert fields BCD->binary.
  mov   al,[TimeStatB]
  test  al,RTC_BCD
  jnz   TimeReadCmos2                   ; If RTC_BCD=1 => already binary
  mov   al,[TimeSec]                    ; SEC
  call  TimeBcdToBin
  mov   [TimeSec],al
  mov   al,[TimeMin]                    ; MIN
  call  TimeBcdToBin
  mov   [TimeMin],al
  mov   al,[TimeHour]                   ; HOUR (preserve PM bit if present)
  mov   ah,al
  and   ah,080h                         ; PM bit
  and   al,07Fh
  call  TimeBcdToBin
  or    al,ah
  mov   [TimeHour],al
  mov   al,[TimeDay]                    ; DAY
  call  TimeBcdToBin
  mov   [TimeDay],al
  mov   al,[TimeMon]                    ; MON
  call  TimeBcdToBin
  mov   [TimeMon],al
  mov   al,[TimeCent]                   ; YY (stored in TimeCent temporarily)
  call  TimeBcdToBin
  mov   [TimeCent],al                   ; TimeCent now holds YY in binary
  mov   al,[TimeTmp]                     ; CENTURY
  call  TimeBcdToBin
  mov   [TimeTmp],al                     ; temp now holds CC in binary
TimeReadCmos2:
  ; Normalize hour to 24h if needed
  mov   al,[TimeHour]
  call  TimeNormalizeHour
  mov   [TimeHour],al
  ; Build full year: TimeYear = (CC*100 + YY) if CC present, else 19/20 pivot + YY
  xor   eax,eax
  mov   al,[TimeCent]                   ; AL = YY (0..99)
  movzx ebx,al                          ; EBX = YY
  xor   eax,eax
  mov   al,[TimeTmp]                    ; AL = CC (0 if not present / unreadable)
  test  al,al
  jz    TimeReadCmos3                   ; No century => use pivot
  movzx eax,al                          ; EAX = CC
  imul  eax,100                         ; EAX = CC*100
  add   eax,ebx                         ; EAX = CC*100 + YY
  mov   [TimeYear],ax                   ; store full year
  jmp   TimeReadCmos5
TimeReadCmos3:
  ; No century register: pick 19xx vs 20xx using YY pivot
  ; Pivot policy: YY >= 80 => 19YY, else 20YY
  cmp   bl,80                           ; YY >= 80 ?
  jb    TimeReadCmos4                   ;  No -> 20YY
  mov   eax,1900
  add   eax,ebx                         ; 1900 + YY
  mov   [TimeYear],ax
  jmp   TimeReadCmos5
TimeReadCmos4:
  mov   eax,2000
  add   eax,ebx                         ; 2000 + YY
  mov   [TimeYear],ax
TimeReadCmos5:
  popa
  ret

;---------------------------------------------------------------------------------------------------
; Time print functions
;---------------------------------------------------------------------------------------------------

;---------------------------------------------------------------------------------------------------
; TimeTmPrint - prints wall time (HH:MM:SS)
;---------------------------------------------------------------------------------------------------
TimeTmPrint:
  pusha
  call  TimeNow
  mov   ebx,TimeStr
  call  TimeFmtHms
  mov   eax,TimeStr
  mov   [VdStrPtr],eax
  call  VdPutStr
  popa
  ret

;---------------------------------------------------------------------------------------------------
; TimeDtPrint - prints wall time (YYYY-MM-DD)
;---------------------------------------------------------------------------------------------------
TimeDtPrint:
  pusha
  call  TimeNow
  mov   ebx,DateStr
  call  TimeFmtYmd
  mov   eax,DateStr
  mov   [VdStrPtr],eax
  call  VdPutStr
  popa
  ret

;---------------------------------------------------------------------------------------------------
; TimeFmtHms - EBX=String,formats current TimeHour/Min/Sec as "HH:MM:SS"
;---------------------------------------------------------------------------------------------------
TimeFmtHms:
  pusha
  mov   edi,ebx
  add   edi,2
  mov   al,[TimeHour]
  call  TimePut2Dec
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   al,[TimeMin]
  call  TimePut2Dec
  mov   al,':'
  mov   [edi],al
  inc   edi
  mov   al,[TimeSec]
  call  TimePut2Dec
  popa
  ret

;---------------------------------------------------------------------------------------------------
; TimeFmtYmd - Formats DateStr with current date/time as "YYYY-MM-DD"
;---------------------------------------------------------------------------------------------------
TimeFmtYmd:
  mov   ebx,DateStr
  mov   edi,ebx
  add   edi,2                           ; Skip length word
  mov   ax,[TimeYear]                   ; YYYY
  call  TimePut4Dec
  mov   al,'-'
  mov   [edi],al
  inc   edi
  mov   al,[TimeMon]                    ; MM
  call  TimePut2Dec
  mov   al,'-'
  mov   [edi],al
  inc   edi
  mov   al,[TimeDay]                    ; DD
  call  TimePut2Dec
  ret

;---------------------------------------------------------------------------------------------------
; Helper functions
;---------------------------------------------------------------------------------------------------

;---------------------------------------------------------------------------------------------------
; TimeBcdToBin - AL=BCD,returns AL=binary
;---------------------------------------------------------------------------------------------------
TimeBcdToBin:
  push  ebx
  mov   bl,al
  and   al,0Fh
  shr   bl,4
  movzx ebx,bl
  imul  ebx,10
  add   al,bl
  pop   ebx
  ret

;---------------------------------------------------------------------------------------------------
; TimeCmosReadReg - AL=register,returns AL=value
;---------------------------------------------------------------------------------------------------
TimeCmosReadReg:
  push  edx
  mov   dx,CMOS_ADDR
  or    al,CMOS_NMI                     ; NMI off while reading
  out   dx,al
  mov   dx,CMOS_DATA
  in    al,dx
  pop   edx
  ret

;---------------------------------------------------------------------------------------------------
; TimeNormalizeHour - AL=hour (maybe PM bit in 12h),returns AL=0..23
;---------------------------------------------------------------------------------------------------
TimeNormalizeHour:
  push  ebx
  mov   bl,[TimeStatB]
  test  bl,RTC_24H
  jnz   TimeNormalizeHour1
  mov   bl,al
  and   bl,080h                         ; PM flag
  and   al,07Fh                         ; 1..12
  cmp   al,12
  jne   TimeNormalizeHour2
  mov   al,0                            ; 12AM -> 00
TimeNormalizeHour2:
  cmp   bl,080h
  jne   TimeNormalizeHour1
  add   al,12                           ; PM add 12
TimeNormalizeHour1:
  pop   ebx
  ret

;---------------------------------------------------------------------------------------------------
; TimePut2Dec - AL=0..99,EDI=dest,writes two digits,EDI+=2
;---------------------------------------------------------------------------------------------------
TimePut2Dec:
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
; TimePut4Dec - AX=0..9999,EDI=dest,writes four digits,EDI+=4
;---------------------------------------------------------------------------------------------------
TimePut4Dec:
  push  eax
  push  ebx
  push  edx
  movzx eax,ax                          ; IMPORTANT: use only AX (clear upper bits)
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
  pop   edx
  pop   ebx
  pop   eax
  ret

;---------------------------------------------------------------------------------------------------
; TimeWaitNotUip - wait until RTC not updating
;---------------------------------------------------------------------------------------------------
TimeWaitNotUip:
  pusha
TimeWaitNotUip1:
  mov   al,RTC_STATUSA
  call  TimeCmosReadReg
  test  al,RTC_UIP
  jnz   TimeWaitNotUip1
  popa
  ret