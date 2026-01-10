;**************************************************************************************************
; Time.asm
;   Time support (RTC + PIT)
;   - CMOS read for baseline wall clock (HH:MM:SS)
;   - PIT polled ticks for monotonic elapsed time (no IRQ)
;   - 386-safe (no 64-bit instructions; uses EDX:EAX pairs)
;===================================================================================================
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
;   - ALL timekeeping logic lives in Time.asm.
;   - The kernel MUST NOT read CMOS or PIT directly.
;   - CMOS,PIT,resync,and future IRQ handling are internal details.
;
; Dependencies
;   - Requires Timer.asm contract:
;       TimerInit
;       TimerNowTicks     ; returns EDX:EAX ticks (PIT input ticks)
;   - Requires Console.asm contract:
;       CnPrint           ; EBX=String,prints+CrLf
;   - Requires Kernel working storage:
;       String  TimeStr,"XXXXXXXX"   ; payload 8 chars
;
; Resync Policy (B,locked-in for now)
;   - TimeNow will resync wall baseline every 60 seconds of monotonic time.
;   - Resync reads CMOS once and snaps wall baseline (wall may jump).
;
; Exported
;   TimeInit
;   TimeSync
;   TimeNow
;   TimeFmtHms
;   TimePrint
;   TimeUptimeFmtHms      ; formats uptime "HH:MM:SS" (hours mod 100)
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

section .data
;---------------------------------------------------------------------------------------------------
; Raw CMOS fields (binary,24h after TimeReadCmos)
;---------------------------------------------------------------------------------------------------
TimeSec         db 0
TimeMin         db 0
TimeHour        db 0
TimeStatB       db 0

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

section .text
;---------------------------------------------------------------------------------------------------
; TimeInit - capture boot baseline for uptime
;---------------------------------------------------------------------------------------------------
TimeInit:
  pusha                                 ; Save registers
  call  TimerInit                       ; Ensure PIT programmed
  call  TimerNowTicks                   ; EDX:EAX = now
  mov   [BootLo],eax                    ; Boot tick baseline
  mov   [BootHi],edx
  mov   byte[BootValid],1
  popa
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
; TimeReadCmos - reads HH:MM:SS into TimeHour/Min/Sec (binary,24h)
;---------------------------------------------------------------------------------------------------
TimeReadCmos:
  pusha
TimeReadCmos1:
  call  TimeWaitNotUip
  mov   al,RTC_STATUSB
  call  TimeCmosReadReg
  mov   [TimeStatB],al
  mov   al,RTC_SEC
  call  TimeCmosReadReg
  mov   [TimeSec],al
  mov   al,RTC_MIN
  call  TimeCmosReadReg
  mov   [TimeMin],al
  mov   al,RTC_HOUR
  call  TimeCmosReadReg
  mov   [TimeHour],al
  mov   al,RTC_STATUSA
  call  TimeCmosReadReg
  test  al,RTC_UIP
  jnz   TimeReadCmos1
  mov   al,[TimeStatB]
  test  al,RTC_BCD
  jnz   TimeReadCmos2
  mov   al,[TimeSec]
  call  TimeBcdToBin
  mov   [TimeSec],al
  mov   al,[TimeMin]
  call  TimeBcdToBin
  mov   [TimeMin],al
  mov   al,[TimeHour]
  mov   ah,al
  and   ah,080h                         ; PM bit
  and   al,07Fh
  call  TimeBcdToBin
  or    al,ah
  mov   [TimeHour],al
TimeReadCmos2:
  mov   al,[TimeHour]
  call  TimeNormalizeHour
  mov   [TimeHour],al
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
; TimeNow - advance wall time using monotonic ticks (policy B resync)
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
; TimePrint - prints wall time (HH:MM:SS) via TimeStr + CnPrint
;---------------------------------------------------------------------------------------------------
TimePrint:
  call  TimeNow
  mov   ebx,TimeStr
  call  TimeFmtHms
  mov   ebx,TimeStr
  call  CnPrint
  ret

;---------------------------------------------------------------------------------------------------
; TimeUptimeFmtHms - EBX=String,formats uptime "HH:MM:SS" (hours mod 100)
;---------------------------------------------------------------------------------------------------
TimeUptimeFmtHms:
  pusha                                 ; Save registers
  mov   ebp,ebx                         ; Save dest String
  cmp   byte[BootValid],1
  je    TimeUptimeFmtHms1
  call  TimeInit
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