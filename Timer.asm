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

section .data
;--------------------------------------------------------------------------------------------------
; Working storage (kept local to Timer.asm)
;--------------------------------------------------------------------------------------------------
TimerReload     dw 0                     ; PIT divisor (0 means 65536)
TimerLastCnt    dw 0                     ; last latched counter value
TimerInitDone   db 0                     ; 0=not initialized,1=initialized
TimerFirstRead  db 1                     ; first TimerNowTicks read after init
TimerTicksLo    dd 0                     ; 64-bit accumulated ticks (low)
TimerTicksHi    dd 0                     ; 64-bit accumulated ticks (high)
TimerRetLo      dd 0                     ; return staging (low)
TimerRetHi      dd 0                     ; return staging (high)

section .text
;--------------------------------------------------------------------------------------------------
; TimerInit - initialize PIT channel 0 for stable polling
;   Programs PIT ch0 mode 2 with divisor = 0 (65536).
;--------------------------------------------------------------------------------------------------
TimerInit:
  pusha                                 ; Save registers
  mov   al,PIT_MODE2_CH0                ; PIT ch0 mode2
  mov   dx,PIT_CMD                      ; Command port
  out   dx,al                           ; Program PIT
  xor   eax,eax                         ; Divisor = 0 => 65536
  mov   dx,PIT_CH0                      ; Channel 0 data port
  out   dx,al                           ; Low byte
  out   dx,al                           ; High byte
  mov   word[TimerReload],0             ; Store divisor (0=65536)
  mov   byte[TimerInitDone],1           ; Mark init done
  mov   byte[TimerFirstRead],1          ; Force first-read behavior
  xor   eax,eax                         ; Clear accumulator
  mov   [TimerTicksLo],eax              ;  low
  mov   [TimerTicksHi],eax              ;  high
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerLatchCount0 - latch and read PIT channel 0 count into AX
;   Returns AX = current down-counter value (latched)
;--------------------------------------------------------------------------------------------------
TimerLatchCount0:
  push  edx                             ; Save edx
  mov   dx,PIT_CMD                      ; PIT command port
  mov   al,PIT_LATCH0                   ; Latch ch0 count
  out   dx,al                           ; Issue latch
  mov   dx,PIT_CH0                      ; PIT ch0 data port
  in    al,dx                           ; Read low byte
  mov   ah,al                           ; Save low in AH temporarily
  in    al,dx                           ; Read high byte
  xchg  ah,al                           ; AX = hi:lo
  pop   edx                             ; Restore edx
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerNowTicks - get monotonic tick counter
;   Returns:
;     EDX:EAX = 64-bit accumulated PIT input ticks
;--------------------------------------------------------------------------------------------------
TimerNowTicks:
  pusha                                 ; Save registers

  ; Ensure initialized (safe no-op if caller forgot)
  cmp   byte[TimerInitDone],1           ; Init done?
  je    TimerNowTicks1                  ;  Yes
  call  TimerInit                       ;  No, init now

TimerNowTicks1:
  call  TimerLatchCount0                ; AX = current count
  mov   bx,ax                           ; BX = curr

  cmp   byte[TimerFirstRead],1          ; First read?
  jne   TimerNowTicks2                  ;  No
  mov   [TimerLastCnt],bx               ;  Yes: seed last count
  mov   byte[TimerFirstRead],0          ;  Clear flag
  jmp   TimerNowTicksDone               ;  Return 0 ticks so far

TimerNowTicks2:
  ; Compute delta = (last - curr) with wrap handling on down-counter.
  mov   ax,[TimerLastCnt]               ; AX = last
  mov   [TimerLastCnt],bx               ; Save curr as new last
  cmp   ax,bx                           ; last >= curr ?
  jae   TimerNowTicks3                  ;  Yes (no wrap)

  ; Wrap case: delta = last + reload - curr
  ; reload = 65536 if TimerReload == 0
  movzx ecx,word[TimerReload]           ; ECX = reload (0..65535)
  test  ecx,ecx                         ; reload==0?
  jne   TimerNowTicks2a                 ;  No
  mov   ecx,65536                       ;  Yes: treat as 65536
TimerNowTicks2a:
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

TimerNowTicksDone:
  ; Stage return so POPA can't clobber it
  mov   eax,[TimerTicksLo]              ; lo
  mov   edx,[TimerTicksHi]              ; hi
  mov   [TimerRetLo],eax                ; stage lo
  mov   [TimerRetHi],edx                ; stage hi
  popa                                  ; Restore registers
  mov   eax,[TimerRetLo]                ; return lo
  mov   edx,[TimerRetHi]                ; return hi
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; TimerDelayMs - busy-wait delay using TimerNowTicks
;   EAX = milliseconds
;   Uses: ticks = round(ms*1193182/1000)
;   Note: clamps very large ms to avoid DIV overflow on 386.
;--------------------------------------------------------------------------------------------------
TimerDelayMs:
  pusha                                 ; Save registers

  ; Clamp ms to avoid div overflow (ms <= ~3,598,000 is safe)
  cmp   eax,3600000                     ; Cap at ~1 hour
  jbe   TimerDelayMs0                   ;  ok
  mov   eax,3600000                     ;  clamp
TimerDelayMs0:

  ; ticks = round(ms*1193182/1000)
  mov   ebx,1193182                     ; PIT Hz
  mul   ebx                             ; EDX:EAX=ms*1193182
  add   eax,500                         ; +500 for rounding
  adc   edx,0                           ; carry into high
  mov   ecx,1000                        ; /1000
  div   ecx                             ; EAX=ticks (32-bit),EDX=remainder

  mov   esi,eax                         ; ticks lo
  xor   edi,edi                         ; ticks hi = 0

  ; start = TimerNowTicks
  call  TimerNowTicks                   ; EDX:EAX=start
  mov   ebx,eax                         ; start lo
  mov   ecx,edx                         ; start hi

  ; deadline = start + ticks
  add   ebx,esi                         ; deadline lo
  adc   ecx,edi                         ; deadline hi

TimerDelayMs1:
  call  TimerNowTicks                   ; EDX:EAX=now
  cmp   edx,ecx                         ; compare hi
  jb    TimerDelayMs1                   ; now.hi < deadline.hi
  ja    TimerDelayMsDone                ; now.hi > deadline.hi
  cmp   eax,ebx                         ; hi equal: compare lo
  jb    TimerDelayMs1                   ; now.lo < deadline.lo

TimerDelayMsDone:
  popa                                  ; Restore registers
  ret                                   ; Return to caller