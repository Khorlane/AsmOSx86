;**************************************************************************************************
; Timer.asm
;   PIT timer (channel 0) - polled, no interrupts
;
;   Kernel-facing contract:
;     TimerInit
;     TimerNowTicks        ; returns EDX:EAX = monotonic PIT input ticks (1/1193182s)
;     TimerDelayMs         ; EAX = ms, busy-wait using TimerNowTicks
;
;   Notes:
;     - 386-safe (no 64-bit instructions; 64-bit values returned in EDX:EAX)
;     - Uses PIT ch0 down-counter + wrap tracking to build a monotonic tick counter.
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
TimerReload     dw 0                     ; PIT divisor (0 means 65536)
TimerLastCnt    dw 0                     ; last latched counter value
TimerFirstRead  db 1                     ; first TimerNowTicks read after init
TimerTicksLo    dd 0                     ; 64-bit accumulated ticks (low)
TimerTicksHi    dd 0                     ; 64-bit accumulated ticks (high)
TimerRetLo      dd 0                     ; return staging (low)
TimerRetHi      dd 0                     ; return staging (high)
TimerStartLo    dd 0                     ; delay: start ticks (low)
TimerStartHi    dd 0                     ; delay: start ticks (high)
TimerDeadLo     dd 0                     ; delay: deadline ticks (low)
TimerDeadHi     dd 0                     ; delay: deadline ticks (high)
TimerTmpTicks   dd 0                     ; delay: delta ticks (32-bit)

;--------------------------------------------------------------------------------------------------
; TimerInit - initialize PIT channel 0 for stable polling
;   Programs PIT ch0 mode 2 with divisor = 0 (65536).
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
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerLatchCount0 - latch and read PIT channel 0 count into AX
;   Returns AX = current down-counter value (latched)
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
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerNowTicks - get monotonic tick counter
;   Returns:
;     EDX:EAX = 64-bit accumulated PIT input ticks
;--------------------------------------------------------------------------------------------------
TimerNowTicks:
  call  TimerLatchCount0                ; AX = current count
  mov   bx,ax                           ; BX = curr
  cmp   byte[TimerFirstRead],1          ; First read?
  jne   TimerNowTicks1                  ;  No
  mov   [TimerLastCnt],bx               ;  Yes: seed last count
  mov   byte[TimerFirstRead],0          ;  Clear flag
  xor   eax,eax
  xor   edx,edx
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
  mov   eax,[TimerTicksLo]              ; return lo
  mov   edx,[TimerTicksHi]              ; return hi
TimerNowTicks5:
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerDelayMs - busy-wait delay using TimerNowTicks
;   EAX = milliseconds
;   Uses: ticks = round(ms*1193182/1000)
;   Note: clamps very large ms to avoid DIV overflow on 386.
;--------------------------------------------------------------------------------------------------
TimerDelayMs:
  ; Clamp ms to avoid div overflow (ms <= ~3,598,000 is safe)
  cmp   eax,3600000                     ; Cap at ~1 hour
  jbe   TimerDelayMs1                   ;  ok
  mov   eax,3600000                     ;  clamp
TimerDelayMs1:
  ; ticks = round(ms*1193182/1000)
  mov   ebx,1193182                     ; PIT Hz
  mul   ebx                             ; EDX:EAX=ms*1193182
  add   eax,500                         ; +500 for rounding
  adc   edx,0                           ; carry into high
  mov   ecx,1000                        ; /1000
  div   ecx                             ; EAX=ticks (32-bit),EDX=remainder
  mov   [TimerTmpTicks],eax             ; ticks lo (persist across calls)
  ; start = TimerNowTicks
  call  TimerNowTicks                   ; EDX:EAX=start
  mov   [TimerStartLo],eax
  mov   [TimerStartHi],edx
  ; deadline = start + ticks
  mov   eax,[TimerStartLo]
  mov   edx,[TimerStartHi]
  add   eax,[TimerTmpTicks]
  adc   edx,0
  mov   [TimerDeadLo],eax
  mov   [TimerDeadHi],edx
TimerDelayMs2:
  call  TimerNowTicks                   ; EDX:EAX=now
  mov   ecx,[TimerDeadHi]               ; deadline hi
  cmp   edx,ecx                         ; compare hi
  jb    TimerDelayMs2                   ; now.hi < deadline.hi
  ja    TimerDelayMs3                   ; now.hi > deadline.hi
  mov   ebx,[TimerDeadLo]               ; deadline lo
  cmp   eax,ebx                         ; hi equal: compare lo
  jb    TimerDelayMs2                   ; now.lo < deadline.lo
TimerDelayMs3:
  ret                                   ; Return to caller