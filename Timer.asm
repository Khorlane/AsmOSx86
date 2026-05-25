;**************************************************************************************************
; Timer.asm
;   PIT timer (channel 0) - polled, no interrupts
;
;   Kernel-facing contract:
;     TimerInit
;     TimerLatchCount0     ; TimerLatchCnt = current PIT down-counter
;     TimerNowTicks        ; TimerOutTicksHi:TimerOutTicksLo = monotonic PIT input ticks
;     TimerSpinDelayMs     ; TimerDelayMs = delay duration in milliseconds
;
;   Notes:
;     - 386-safe (no 64-bit instructions; 64-bit values stored as Hi/Lo dwords)
;     - Uses PIT ch0 down-counter + wrap tracking to build a monotonic tick counter.
;     - Registers are scratch only; persistent inputs/outputs use Timer* globals.
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; PIT I/O ports
;--------------------------------------------------------------------------------------------------
PIT_CH0         equ 040h
PIT_CMD         equ 043h

; Command: latch count value for channel 0
PIT_LATCH0      equ 00000000b

; Program: channel 0, lobyte/hibyte, mode 2 (rate generator), binary
PIT_MODE2_CH0   equ 00110100b            ; ch0,lo/hi,mode2,binary

; PIT input clock (Hz)
PIT_HZ          equ 1193182

;--------------------------------------------------------------------------------------------------
; Working storage (kept local to Timer.asm)
;--------------------------------------------------------------------------------------------------
TimerReload     dw 0                     ; PIT reload value used for wrap math
TimerLastCnt    dw 0                     ; last latched counter value
TimerLatchCnt   dw 0                     ; output: current latched PIT count
TimerFirstRead  db 1                     ; first TimerNowTicks read after init
TimerPad0       db 0                     ; keep dword alignment friendly
TimerDelayMs    dd 0                     ; input: delay duration in milliseconds
TimerTicksLo    dd 0                     ; 64-bit accumulated ticks (low)
TimerTicksHi    dd 0                     ; 64-bit accumulated ticks (high)
TimerOutTicksLo dd 0                     ; output: monotonic ticks low dword
TimerOutTicksHi dd 0                     ; output: monotonic ticks high dword
TimerStartLo    dd 0                     ; delay: start ticks (low)
TimerStartHi    dd 0                     ; delay: start ticks (high)
TimerDeadLo     dd 0                     ; delay: deadline ticks (low)
TimerDeadHi     dd 0                     ; delay: deadline ticks (high)
TimerTmpTicks   dd 0                     ; delay: delta ticks (32-bit)

;--------------------------------------------------------------------------------------------------
; TimerInit - initialize PIT channel 0 for stable polling
;   Programs PIT ch0 mode 2 and loads reload value 0xFFFF.
;--------------------------------------------------------------------------------------------------
TimerInit:
  mov   al,PIT_MODE2_CH0                ; PIT ch0 mode2
  mov   dx,PIT_CMD                      ; Command port
  out   dx,al                           ; Program PIT
  mov   dx,PIT_CH0                      ; Channel 0 data port
  mov   al,0FFh                         ; Divisor low  = 0xFF
  out   dx,al
  mov   al,0FFh                         ; Divisor high = 0xFF  (0xFFFF)
  out   dx,al
  mov   word[TimerReload],0FFFFh        ; Store divisor
  mov   byte[TimerFirstRead],1          ; Force first-read behavior
  xor   eax,eax                         ; Clear accumulator
  mov   [TimerTicksLo],eax              ;  low
  mov   [TimerTicksHi],eax              ;  high
  mov   [TimerOutTicksLo],eax           ; Clear output low
  mov   [TimerOutTicksHi],eax           ; Clear output high
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerLatchCount0 - latch and read PIT channel 0 count
;   Output:
;     TimerLatchCnt = current down-counter value
;--------------------------------------------------------------------------------------------------
TimerLatchCount0:
  mov   dx,PIT_CMD                      ; PIT command port
  mov   al,PIT_LATCH0                   ; Latch ch0 count
  out   dx,al                           ; Issue latch
  mov   dx,PIT_CH0                      ; PIT ch0 data port
  in    al,dx                           ; Read low byte
  mov   ah,al                           ; Save low in AH temporarily
  in    al,dx                           ; Read high byte
  xchg  ah,al                           ; AX = hi:lo
  mov   [TimerLatchCnt],ax              ; Store latched count
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerNowTicks - get monotonic tick counter
;   Output:
;     TimerOutTicksLo = low 32 bits of accumulated PIT input ticks
;     TimerOutTicksHi = high 32 bits of accumulated PIT input ticks
;   Notes:
;     First call after TimerInit seeds the baseline and returns zero in TimerOutTicksLo/Hi.
;--------------------------------------------------------------------------------------------------
TimerNowTicks:
  call  TimerLatchCount0                ; TimerLatchCnt = current count
  mov   bx,[TimerLatchCnt]              ; BX = curr
  cmp   byte[TimerFirstRead],1          ; First read?
  jne   TimerNowTicks1                  ;  No
  mov   [TimerLastCnt],bx               ;  Yes: seed last count
  mov   byte[TimerFirstRead],0          ;  Clear flag
  xor   eax,eax
  mov   [TimerOutTicksLo],eax           ; output lo = 0
  mov   [TimerOutTicksHi],eax           ; output hi = 0
  jmp   TimerNowTicks5                  ; Return zero ticks
TimerNowTicks1:
  ; Compute delta = (last - curr) with wrap handling on down-counter.
  mov   ax,[TimerLastCnt]               ; AX = last
  mov   [TimerLastCnt],bx               ; Save curr as new last
  cmp   ax,bx                           ; last >= curr ?
  jae   TimerNowTicks3                  ;  Yes (no wrap)
  ; Wrap case: delta = last + reload - curr
  movzx ecx,word[TimerReload]           ; ECX = reload (1..65535)
TimerNowTicks2:
  movzx edx,ax                          ; EDX = last
  add   edx,ecx                         ; EDX = last + reload
  movzx eax,bx                          ; EAX = curr
  sub   edx,eax                         ; EDX = delta (wrap)
  jmp   TimerNowTicks4                  ; Accumulate
TimerNowTicks3:
  ; No wrap: delta = last - curr
  movzx edx,ax                          ; EDX = last
  movzx eax,bx                          ; EAX = curr
  sub   edx,eax                         ; EDX = delta
TimerNowTicks4:
  ; Accumulate delta into 64-bit ticks
  mov   eax,[TimerTicksLo]              ; EAX = lo
  add   eax,edx                         ; lo += delta
  mov   [TimerTicksLo],eax              ; store lo
  mov   eax,[TimerTicksHi]              ; EAX = hi
  adc   eax,0                           ; hi += carry
  mov   [TimerTicksHi],eax              ; store hi
  mov   eax,[TimerTicksLo]              ; load lo
  mov   [TimerOutTicksLo],eax           ; output lo
  mov   eax,[TimerTicksHi]              ; load hi
  mov   [TimerOutTicksHi],eax           ; output hi
TimerNowTicks5:
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerSpinDelayMs - busy-wait delay using TimerNowTicks
;   Input:
;     TimerDelayMs = milliseconds
;   Uses: ticks = round(ms*1193182/1000)
;   Notes:
;     - Busy-waits until the deadline is reached.
;     - Clamps very large ms to avoid DIV overflow on 386.
;--------------------------------------------------------------------------------------------------
TimerSpinDelayMs:
  ; Clamp ms to avoid div overflow (ms <= ~3,598,000 is safe)
  mov   eax,[TimerDelayMs]              ; milliseconds
  cmp   eax,3600000                     ; Cap at ~1 hour
  jbe   TimerSpinDelayMs1               ;  ok
  mov   eax,3600000                     ;  clamp
TimerSpinDelayMs1:
  ; ticks = round(ms*1193182/1000)
  mov   ebx,1193182                     ; PIT Hz
  mul   ebx                             ; EDX:EAX=ms*1193182
  add   eax,500                         ; +500 for rounding
  adc   edx,0                           ; carry into high
  mov   ecx,1000                        ; /1000
  div   ecx                             ; EAX=ticks (32-bit),EDX=remainder
  mov   [TimerTmpTicks],eax             ; ticks lo (persist across calls)
  ; start = TimerNowTicks
  call  TimerNowTicks                   ; TimerOutTicksHi:TimerOutTicksLo=start
  mov   eax,[TimerOutTicksLo]
  mov   edx,[TimerOutTicksHi]
  mov   [TimerStartLo],eax
  mov   [TimerStartHi],edx
  ; deadline = start + ticks
  mov   eax,[TimerStartLo]
  mov   edx,[TimerStartHi]
  add   eax,[TimerTmpTicks]
  adc   edx,0
  mov   [TimerDeadLo],eax
  mov   [TimerDeadHi],edx
TimerSpinDelayMs2:
  call  TimerNowTicks                   ; TimerOutTicksHi:TimerOutTicksLo=now
  mov   eax,[TimerOutTicksLo]
  mov   edx,[TimerOutTicksHi]
  mov   ecx,[TimerDeadHi]               ; deadline hi
  cmp   edx,ecx                         ; compare hi
  jb    TimerSpinDelayMs2               ; now.hi < deadline.hi
  ja    TimerSpinDelayMs3               ; now.hi > deadline.hi
  mov   ebx,[TimerDeadLo]               ; deadline lo
  cmp   eax,ebx                         ; hi equal: compare lo
  jb    TimerSpinDelayMs2               ; now.lo < deadline.lo
TimerSpinDelayMs3:
  ret                                   ; Return to caller
