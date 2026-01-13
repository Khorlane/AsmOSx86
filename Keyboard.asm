;**************************************************************************************************
; Keyboard.asm
;   Keyboard input (polled, no IRQ) — early-stage ASCII-only service + line input
;
; Big picture
;   - KbPoll is the ONLY routine that touches the 8042 ports (064h/060h).
;   - KbPoll translates ONE scancode (if present) into ASCII and enqueues it.
;   - KbGetChar / KbWaitChar consume the ASCII ring buffer.
;   - KbReadLine builds an editable line using KbWaitChar:
;       - printable chars are appended + echoed
;       - Backspace removes last char + erases on screen
;       - Enter finishes: echoes CRLF, writes a 0-terminated string
;
; Locked-in constraints
;   - ASCII only (a-z, 0-9, plus Space / Backspace / Enter)
;   - No IRQ, no E0/E1 extended keys, no modifiers, no repeat handling
;   - Ring buffer size 32 bytes; overflow overwrites oldest
;   - Unknown scancodes are dropped
;   - Break/release scancodes are ignored
;   - Exported routines preserve all general registers (pusha/popa).
;     Any return value in AL/EAX must be staged and restored after popa.
;**************************************************************************************************

[bits 32]

section .data
;--------------------------------------------------------------------------------------------------
; Translation tables (Set 1 make codes -> ASCII)
;
; Coverage
;   - a-z, 0-9
;   - space
;   - enter
;   - backspace
;--------------------------------------------------------------------------------------------------

; a-z + 0-9 (existing)
Scancode    db 01Eh, 030h, 02Eh, 020h, 012h, 021h, 022h, 023h, 017h, 024h, 025h, 026h
            db 032h, 031h, 018h, 019h, 010h, 013h, 01Fh, 014h, 016h, 02Fh, 011h, 02Dh
            db 015h, 02Ch, 00Bh, 002h, 003h, 004h, 005h, 006h, 007h, 008h, 009h, 00Ah
            ; extras (space, enter, backspace)
            db 039h, 01Ch, 00Eh
ScancodeEnd:
ScancodeSz  equ ScancodeEnd - Scancode

CharCode    db 061h, 062h, 063h, 064h, 065h, 066h, 067h, 068h, 069h, 06Ah, 06Bh, 06Ch
            db 06Dh, 06Eh, 06Fh, 070h, 071h, 072h, 073h, 074h, 075h, 076h, 077h, 078h
            db 079h, 07Ah, 030h, 031h, 032h, 033h, 034h, 035h, 036h, 037h, 038h, 039h
            ; extras (space, enter, backspace)
            db 020h, 00Dh, 08h
CharCodeEnd:
CharCodeSz  equ CharCodeEnd - CharCode

; break/release scancodes for a-z + 0-9 (existing)
IgnoreCode  db 09Eh, 0B0h, 0AEh, 0A0h, 092h, 0A1h, 0A2h, 0A3h, 097h, 0A4h, 0A5h, 0A6h
            db 0B2h, 0B1h, 098h, 099h, 090h, 093h, 09Fh, 094h, 096h, 0BFh, 091h, 0ADh
            db 095h, 0ACh, 08Bh, 082h, 083h, 084h, 085h, 086h, 087h, 088h, 089h, 08Ah
            ; extras (space, enter, backspace) break codes
            db 0B9h, 09Ch, 08Eh
IgnoreEnd:
IgnoreSz    equ IgnoreEnd - IgnoreCode

;--------------------------------------------------------------------------------------------------
; ASCII ring buffer (internal)
;   - Size 32 bytes (power of 2)
;   - Overflow overwrites oldest: advance Tail before writing when full
;--------------------------------------------------------------------------------------------------
KB_BUF_SZ   equ 32

KbBuf       times KB_BUF_SZ db 0
KbHead      db 0
KbTail      db 0
KbCount     db 0

; ABI return staging (POPA restores EAX, so we stage AL here)
KbRetChar   db 0

; KbReadLine state
KbLinePtr   dd 0        ; caller buffer pointer
KbLineMax   dd 0        ; max chars (excluding terminator)
KbLineLen   dd 0        ; current length

section .text
;--------------------------------------------------------------------------------------------------
; Exported: KbInit
;   Big picture: reset all internal keyboard state to "empty"
;--------------------------------------------------------------------------------------------------
KbInit:
  pusha
  mov   byte[KbHead],0                  ; next write index = 0
  mov   byte[KbTail],0                  ; next read index  = 0
  mov   byte[KbCount],0                 ; buffer empty
  mov   byte[KbRetChar],0               ; staged return = 0
  mov   dword[KbLinePtr],0              ; clear line state
  mov   dword[KbLineMax],0
  mov   dword[KbLineLen],0
  popa
  ret

;--------------------------------------------------------------------------------------------------
; Exported: KbPoll
;   Big picture: sample the 8042 once; if a byte is ready, translate and enqueue ASCII
;--------------------------------------------------------------------------------------------------
KbPoll:
  pusha
  in    al,064h                         ; 8042 status port
  test  al,1                            ; bit0=1 => data ready at 060h
  jz    KbPollDone                      ; nothing waiting => return now

  in    al,060h                         ; read one scancode byte
  call  KbScancodeToAscii               ; map scancode -> ASCII (AL) or 0 (drop)
  test  al,al
  jz    KbPollDone                      ; ignored/unknown => drop silently
  call  KbEnqueueAscii                  ; append ASCII into ring buffer
KbPollDone:
  popa
  ret

;--------------------------------------------------------------------------------------------------
; Exported: KbGetChar
;   Big picture: non-blocking "pull" from ASCII ring buffer
;   Returns: AL = char, or 0 if empty
;--------------------------------------------------------------------------------------------------
KbGetChar:
  pusha
  call  KbDequeueAscii                  ; AL = next char or 0
  mov   [KbRetChar],al                  ; stage return value across POPA
  popa
  mov   al,[KbRetChar]                  ; restore return value
  ret

;--------------------------------------------------------------------------------------------------
; Exported: KbWaitChar
;   Big picture: blocking "pull" — keep polling hardware until a char appears in the ring buffer
;   Returns: AL = char (non-zero)
;--------------------------------------------------------------------------------------------------
KbWaitChar:
  pusha
KbWaitCharLoop:
  call  KbPoll                          ; try to bring one new key into the buffer
  call  KbDequeueAscii                  ; try to consume one buffered ASCII char
  test  al,al
  jz    KbWaitCharLoop                  ; still empty => keep polling
  mov   [KbRetChar],al                  ; stage return value across POPA
  popa
  mov   al,[KbRetChar]
  ret

;--------------------------------------------------------------------------------------------------
; Exported: KbReadLine
;   Big picture: build an editable line from KbWaitChar
;
; Calling convention (simple + deterministic)
;   Input:
;     EBX = destination buffer (byte*)
;     ECX = max length (chars, excluding trailing 0)
;   Output:
;     Buffer is 0-terminated
;     AL = 1 (success)   [always 1 in current implementation]
;
; Editing behavior
;   - Printable ASCII (0x20..0x7E): append if space remains; echo
;   - Backspace (0x08): if len>0, delete last char and erase on screen
;   - Enter (0x0D): echo CRLF, terminate buffer with 0, return
;--------------------------------------------------------------------------------------------------
KbReadLine:
  pusha
  mov   [KbLinePtr],ebx                 ; remember caller buffer
  mov   [KbLineMax],ecx                 ; remember max chars
  mov   dword[KbLineLen],0              ; start empty

KbReadLineLoop:
  call  KbWaitChar                      ; AL = next ASCII key

  cmp   al,0Dh                          ; Enter?
  je    KbReadLineEnter

  cmp   al,08h                          ; Backspace?
  je    KbReadLineBackspace

  ; Accept only printable ASCII range (space already maps to 0x20)
  cmp   al,020h
  jb    KbReadLineLoop                  ; control => ignore
  cmp   al,07Eh
  ja    KbReadLineLoop                  ; non-ASCII => ignore

  ; If line is full, ignore extra printable chars
  mov   edx,[KbLineLen]
  mov   ecx,[KbLineMax]
  cmp   edx,ecx
  jae   KbReadLineLoop

  ; Append char into caller buffer at [ptr + len]
  mov   esi,[KbLinePtr]
  mov   [esi+edx],al

  ; Echo typed character
  call  KbEchoChar

  ; len++
  inc   dword[KbLineLen]
  jmp   KbReadLineLoop

KbReadLineBackspace:
  ; If empty, nothing to delete
  mov   edx,[KbLineLen]
  test  edx,edx
  jz    KbReadLineLoop

  ; len--
  dec   dword[KbLineLen]

  ; Optional: clear byte in buffer (not required, but keeps things tidy)
  mov   edx,[KbLineLen]
  mov   esi,[KbLinePtr]
  mov   byte[esi+edx],0

  ; Erase last char visually: BS, space, BS
  call  KbEchoBackspace
  jmp   KbReadLineLoop

KbReadLineEnter:
  ; Terminate buffer with 0 at [ptr + len]
  mov   edx,[KbLineLen]
  mov   esi,[KbLinePtr]
  mov   byte[esi+edx],0

  ; Echo newline (CRLF)
  call  KbEchoCrlf

  ; Return AL=1 (success), staged across POPA
  mov   byte[KbRetChar],1
  popa
  mov   al,[KbRetChar]
  ret

;--------------------------------------------------------------------------------------------------
; Private: KbScancodeToAscii
;   Big picture: filter scancodes (ignore list), then map make-code -> ASCII
;   Input:  AL = scancode
;   Output: AL = ASCII, or 0 if ignored/unknown
;--------------------------------------------------------------------------------------------------
KbScancodeToAscii:
  push  ecx
  push  esi

  ; First, filter out break/release scancodes (never produce ASCII)
  xor   esi,esi
  mov   ecx,IgnoreSz
KbScancodeToAsciiIgnore:
  cmp   al,[IgnoreCode+esi]
  je    KbScancodeToAsciiDrop
  inc   esi
  loop  KbScancodeToAsciiIgnore

  ; Next, map make scancodes to ASCII via index-aligned tables
  xor   esi,esi
  mov   ecx,ScancodeSz
KbScancodeToAsciiScan:
  cmp   al,[Scancode+esi]
  je    KbScancodeToAsciiHit
  inc   esi
  loop  KbScancodeToAsciiScan
  jmp   KbScancodeToAsciiDrop

KbScancodeToAsciiHit:
  mov   al,[CharCode+esi]               ; return mapped ASCII
  jmp   KbScancodeToAsciiDone

KbScancodeToAsciiDrop:
  xor   eax,eax                         ; return 0 (drop)

KbScancodeToAsciiDone:
  pop   esi
  pop   ecx
  ret

;--------------------------------------------------------------------------------------------------
; Private: KbEnqueueAscii
;   Big picture: append one ASCII byte into ring buffer, overwriting oldest when full
;   Input:  AL = ASCII (non-zero)
;--------------------------------------------------------------------------------------------------
KbEnqueueAscii:
  push  ebx
  push  edx

  mov   bl,[KbCount]
  cmp   bl,KB_BUF_SZ
  jne   KbEnqueueNotFull

  ; Buffer full: advance Tail (discard oldest) before writing new byte
  mov   dl,[KbTail]
  inc   dl
  and   dl,(KB_BUF_SZ-1)
  mov   [KbTail],dl
  jmp   KbEnqueueWrite

KbEnqueueNotFull:
  inc   bl
  mov   [KbCount],bl

KbEnqueueWrite:
  mov   dl,[KbHead]                     ; write at Head
  mov   [KbBuf+edx],al
  inc   dl
  and   dl,(KB_BUF_SZ-1)
  mov   [KbHead],dl

  pop   edx
  pop   ebx
  ret

;--------------------------------------------------------------------------------------------------
; Private: KbDequeueAscii
;   Big picture: remove one ASCII byte from ring buffer
;   Output: AL = char, or 0 if empty
;--------------------------------------------------------------------------------------------------
KbDequeueAscii:
  push  ebx
  push  edx

  mov   bl,[KbCount]
  test  bl,bl
  jnz   KbDequeueHasData

  xor   eax,eax                         ; empty => AL=0
  jmp   KbDequeueDone

KbDequeueHasData:
  mov   dl,[KbTail]                     ; read at Tail
  mov   al,[KbBuf+edx]
  inc   dl
  and   dl,(KB_BUF_SZ-1)
  mov   [KbTail],dl
  dec   bl
  mov   [KbCount],bl

KbDequeueDone:
  pop   edx
  pop   ebx
  ret

;--------------------------------------------------------------------------------------------------
; Private: KbEchoChar
;   Big picture: echo one printable ASCII char using Console.PutStr
;   Input: AL = ASCII
;--------------------------------------------------------------------------------------------------
KbEchoChar:
  push  eax
  push  ebx

  mov   [KbEchoBuf+2],al                ; put char into 1-char length-prefixed string
  mov   ebx,KbEchoBuf
  call  PutStr

  pop   ebx
  pop   eax
  ret

;--------------------------------------------------------------------------------------------------
; Private: KbEchoCrlf
;   Big picture: echo CRLF using Console.PutStr
;--------------------------------------------------------------------------------------------------
KbEchoCrlf:
  push  ebx
  mov   ebx,KbEchoCrLf
  call  PutStr
  pop   ebx
  ret

;--------------------------------------------------------------------------------------------------
; Private: KbEchoBackspace
;   Big picture: erase last echoed char on screen: BS, space, BS
;--------------------------------------------------------------------------------------------------
KbEchoBackspace:
  push  ebx
  mov   ebx,KbEchoBsSeq
  call  PutStr
  pop   ebx
  ret

;--------------------------------------------------------------------------------------------------
; Private strings for echo helpers (length-prefixed, Console.PutStr-compatible)
;--------------------------------------------------------------------------------------------------
String  KbEchoBuf,"X"
String  KbEchoCrLf,0Dh,0Ah
String  KbEchoBsSeq,08h,020h,08h