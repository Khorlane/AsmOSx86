;**************************************************************************************************
; Keyboard.asm
;   Keyboard input (polled, no IRQ) — early-stage ASCII-only service
;
; Purpose
;   Provide deterministic keyboard input during early boot / kernel bring-up
;   without interrupts, without BIOS, and without scan-code consumers.
;
; Design (LOCKED-IN for early stage)
;   - Polled 8042 controller (PS/2) using ports 064h (status) and 060h (data).
;   - ASCII-only output. Scancodes are an internal detail.
;   - Internal ring buffer holds the produced ASCII stream.
;     - Size: 32 bytes
;     - Overflow policy: overwrite oldest
;   - Unknown scancodes are dropped (no placeholder characters).
;   - Break/release scancodes are ignored (no enqueue).
;   - No extended scancodes (E0/E1), no modifiers, no key-repeat handling (yet).
;
; Exported (Kernel-facing ABI)
;   KbInit
;     - Initializes keyboard service state.
;     - Clears ring buffer and indices.
;
;   KbPoll
;     - Non-blocking. Polls 8042 ONCE.
;     - If a scancode is available and maps to ASCII, enqueues it.
;     - If no scancode is available, returns immediately.
;
;   KbGetChar
;     - Non-blocking dequeue.
;     - Returns: AL = ASCII character, or AL = 0 if buffer empty.
;
;   KbWaitChar
;     - Blocking wait for one ASCII character.
;     - Internally loops: KbPoll then KbGetChar until AL != 0.
;     - Returns: AL = ASCII character.
;
; Register Discipline (LOCKED-IN)
;   - All exported routines preserve all general registers (pusha/popa).
;   - Any return value in a clobbered register (AL/EAX) is staged to memory and
;     restored after popa (see Doc/Abi.md).
;
; Hardware (8042 / PS/2 controller)
;   - Status port  064h: bit0=1 => output buffer full (data ready).
;   - Data port    060h: read scancode when status bit0 indicates ready.
;
; Ownership
;   - This module owns:
;       - Translation tables (scancode -> ASCII)
;       - Ring buffer (ASCII stream)
;       - All keyboard-related mutable state
;   - No KernelCtx globals are required by this module.
;**************************************************************************************************

[bits 32]

section .data
;--------------------------------------------------------------------------------------------------
; Translation tables (Set 1 make codes -> ASCII)
;
; Contract
;   - Scancode[] and CharCode[] are same size and index-aligned.
;   - IgnoreCode[] lists scancodes that must never produce ASCII.
;
; Coverage (current)
;   - Lowercase a-z and digits 0-9 only.
;   - Everything else is either ignored (break/release) or dropped (unknown).
;--------------------------------------------------------------------------------------------------
Scancode    db 01Eh, 030h, 02Eh, 020h, 012h, 021h, 022h, 023h, 017h, 024h, 025h, 026h
            db 032h, 031h, 018h, 019h, 010h, 013h, 01Fh, 014h, 016h, 02Fh, 011h, 02Dh
            db 015h, 02Ch, 00Bh, 002h, 003h, 004h, 005h, 006h, 007h, 008h, 009h, 00Ah
ScancodeEnd:
ScancodeSz  equ ScancodeEnd - Scancode

CharCode    db 061h, 062h, 063h, 064h, 065h, 066h, 067h, 068h, 069h, 06Ah, 06Bh, 06Ch
            db 06Dh, 06Eh, 06Fh, 070h, 071h, 072h, 073h, 074h, 075h, 076h, 077h, 078h
            db 079h, 07Ah, 030h, 031h, 032h, 033h, 034h, 035h, 036h, 037h, 038h, 039h
CharCodeEnd:
CharCodeSz  equ CharCodeEnd - CharCode

IgnoreCode  db 09Eh, 0B0h, 0AEh, 0A0h, 092h, 0A1h, 0A2h, 0A3h, 097h, 0A4h, 0A5h, 0A6h
            db 0B2h, 0B1h, 098h, 099h, 090h, 093h, 09Fh, 094h, 096h, 0BFh, 091h, 0ADh
            db 095h, 0ACh, 08Bh, 082h, 083h, 084h, 085h, 086h, 087h, 088h, 089h, 08Ah
IgnoreEnd:
IgnoreSz    equ IgnoreEnd - IgnoreCode

;--------------------------------------------------------------------------------------------------
; ASCII ring buffer (internal)
;
; Contract (LOCKED-IN)
;   - Size is 32 bytes.
;   - Overflow overwrites oldest: when full, advance Tail before writing.
;
; State
;   Head = next write index
;   Tail = next read index
;   Count = number of bytes currently stored (0..32)
;--------------------------------------------------------------------------------------------------
KB_BUF_SZ   equ 32

KbBuf       times KB_BUF_SZ db 0
KbHead      db 0
KbTail      db 0
KbCount     db 0

; Return staging (ABI: POPA clobbers EAX/AL)
KbRetChar   db 0

section .text
;--------------------------------------------------------------------------------------------------
; KbInit — initialize keyboard service state
;--------------------------------------------------------------------------------------------------
KbInit:
  pusha
  mov   byte[KbHead],0
  mov   byte[KbTail],0
  mov   byte[KbCount],0
  mov   byte[KbRetChar],0
  popa
  ret

;--------------------------------------------------------------------------------------------------
; KbPoll — poll 8042 ONCE; translate+enqueue if possible (non-blocking)
;--------------------------------------------------------------------------------------------------
KbPoll:
  pusha
  in    al,064h                         ; 8042 status port
  test  al,1                            ; bit0=1 => data ready at 060h
  jz    KbPoll2                         ; no data => return
  in    al,060h                         ; scancode byte
  call  KbScancodeToAscii               ; AL = ASCII, or 0 if ignored/unknown
  test  al,al
  jz    KbPoll2                         ; drop if 0
  call  KbEnqueueAscii                  ; enqueue AL (overwrite oldest if full)
KbPoll2:
  popa
  ret

;--------------------------------------------------------------------------------------------------
; KbGetChar — dequeue one ASCII byte (non-blocking)
;   Returns:
;     AL = ASCII character, or 0 if buffer empty
;--------------------------------------------------------------------------------------------------
KbGetChar:
  pusha
  call  KbDequeueAscii                  ; AL = char or 0
  mov   [KbRetChar],al                  ; stage return
  popa
  mov   al,[KbRetChar]                  ; restore return after POPA
  ret

;--------------------------------------------------------------------------------------------------
; KbWaitChar — blocking wait for one ASCII byte
;   Returns:
;     AL = ASCII character
;--------------------------------------------------------------------------------------------------
KbWaitChar:
  pusha
KbWaitChar1:
  call  KbPoll
  call  KbDequeueAscii                  ; AL = char or 0
  test  al,al
  jz    KbWaitChar1
  mov   [KbRetChar],al                  ; stage return
  popa
  mov   al,[KbRetChar]
  ret

;--------------------------------------------------------------------------------------------------
; KbScancodeToAscii — translate one Set1 make scancode to ASCII (private)
;   Input:
;     AL = scancode
;   Output:
;     AL = ASCII if mapped
;     AL = 0 if ignored (break/release) or unknown
;--------------------------------------------------------------------------------------------------
KbScancodeToAscii:
  push  ecx
  push  esi

  ; Ignore break/release scancodes
  xor   esi,esi
  mov   ecx,IgnoreSz
KbScancodeToAscii1:
  cmp   al,[IgnoreCode+esi]
  je    KbScancodeToAsciiDrop
  inc   esi
  loop  KbScancodeToAscii1

  ; Translate make scancodes
  xor   esi,esi
  mov   ecx,ScancodeSz
KbScancodeToAscii2:
  cmp   al,[Scancode+esi]
  je    KbScancodeToAscii3
  inc   esi
  loop  KbScancodeToAscii2
  jmp   KbScancodeToAsciiDrop           ; unknown => drop

KbScancodeToAscii3:
  mov   al,[CharCode+esi]               ; mapped ASCII
  jmp   KbScancodeToAsciiDone

KbScancodeToAsciiDrop:
  xor   eax,eax                         ; AL=0

KbScancodeToAsciiDone:
  pop   esi
  pop   ecx
  ret

;--------------------------------------------------------------------------------------------------
; KbEnqueueAscii — enqueue AL into ring buffer (private)
;   Input:
;     AL = ASCII byte (non-zero)
;   Policy:
;     - if full, advance Tail first (overwrite oldest), keep Count at 32
;--------------------------------------------------------------------------------------------------
KbEnqueueAscii:
  push  ebx
  push  edx

  mov   bl,[KbCount]
  cmp   bl,KB_BUF_SZ
  jne   KbEnqueueAscii1

  ; Full: drop oldest by advancing Tail (Count stays 32)
  mov   dl,[KbTail]
  inc   dl
  and   dl,(KB_BUF_SZ-1)                ; KB_BUF_SZ must be power of 2 (32)
  mov   [KbTail],dl
  jmp   KbEnqueueAscii2

KbEnqueueAscii1:
  inc   bl
  mov   [KbCount],bl

KbEnqueueAscii2:
  ; Write at Head
  mov   dl,[KbHead]                     ; DL = head index
  mov   [KbBuf+edx],al                  ; store ASCII
  inc   dl
  and   dl,(KB_BUF_SZ-1)
  mov   [KbHead],dl

  pop   edx
  pop   ebx
  ret

;--------------------------------------------------------------------------------------------------
; KbDequeueAscii — dequeue one byte from ring buffer (private)
;   Output:
;     AL = ASCII byte, or 0 if empty
;--------------------------------------------------------------------------------------------------
KbDequeueAscii:
  push  ebx
  push  edx

  mov   bl,[KbCount]
  test  bl,bl
  jnz   KbDequeueAscii1
  xor   eax,eax                         ; AL=0 (empty)
  jmp   KbDequeueAscii2

KbDequeueAscii1:
  ; Read at Tail
  mov   dl,[KbTail]
  mov   al,[KbBuf+edx]
  inc   dl
  and   dl,(KB_BUF_SZ-1)
  mov   [KbTail],dl
  dec   bl
  mov   [KbCount],bl

KbDequeueAscii2:
  pop   edx
  pop   ebx
  ret