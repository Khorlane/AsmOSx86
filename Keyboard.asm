;**************************************************************************************************
; Keyboard.asm
;   Keyboard input (polled, no IRQ)
;
;   Exported:
;     KbRead            ; reads scancode into KbChar (0FFh if none)
;     KbXlate           ; translates KbChar scancode -> ASCII (or '?' / ignored)
;
;   Requires (Kernel-owned globals):
;     KbChar            ; db in KernelCtx
;
;   Requires (Kernel-owned tables in Kernel.asm):
;     Scancode,ScancodeSz
;     CharCode,CharCodeSz
;     IgnoreCode,IgnoreSz
;
;   Register Discipline:
;     - Routines preserve registers unless explicitly documented otherwise.
;
;   Notes:
;     - KbRead polls 8042 status port 064h and reads data port 060h.
;**************************************************************************************************

[bits 32]
section .data
;--------------------------------------------------------------------------------------------------
; Keyboard Scancode/Character Tables
;--------------------------------------------------------------------------------------------------
; Make scancodes
Scancode    db 01Eh, 030h, 02Eh, 020h, 012h, 021h, 022h, 023h, 017h, 024h, 025h, 026h     ; Make Scancodes
            db 032h, 031h, 018h, 019h, 010h, 013h, 01Fh, 014h, 016h, 02Fh, 011h, 02Dh     ;  a-z keys
            db 015h, 02Ch, 00Bh, 002h, 003h, 004h, 005h, 006h, 007h, 008h, 009h, 00Ah     ;  and 0-9 keys
ScancodeEnd:
ScancodeSz  equ ScancodeEnd - Scancode                                                    ; Size of Scancode table
; Corresponding ASCII characters
CharCode    db 061h, 062h, 063h, 064h, 065h, 066h, 067h, 068h, 069h, 06Ah, 06Bh, 06Ch     ; ASCII characters
            db 06Dh, 06Eh, 06Fh, 070h, 071h, 072h, 073h, 074h, 075h, 076h, 077h, 078h     ;  a-z
            db 079h, 07Ah, 030h, 031h, 032h, 033h, 034h, 035h, 036h, 037h, 038h, 039h     ;  and 0-9
CharCodeEnd:
CharCodeSz  equ CharCodeEnd - CharCode                                                    ; Size of CharCode table
; Break scancodes to ignore
IgnoreCode  db 09Eh, 0B0h, 0AEh, 0A0h, 092h, 0A1h, 0A2h, 0A3h, 097h, 0A4h, 0A5h, 0A6h     ; Break Scancodes
            db 0B2h, 0B1h, 098h, 099h, 090h, 093h, 09Fh, 094h, 096h, 0BFh, 091h, 0ADh     ;  a-z
            db 095h, 0ACh, 08Bh, 082h, 083h, 084h, 085h, 086h, 087h, 088h, 089h, 08Ah     ;  and 0-9
IgnoreEnd:
IgnoreSz    equ IgnoreEnd - IgnoreCode                                                    ; Size of IgnoreCode table

section .text
;--------------------------------------------------------------------------------------------------
; KbRead - poll 8042 for a pending scancode
;   Output:
;     [KbChar] = scancode if available, else 0FFh
;--------------------------------------------------------------------------------------------------
KbRead:
  pusha
  mov   ecx,2FFFFh                      ; Timeout loop (keeps polling if no key yet)
KbRead1:
  in    al,064h                         ; 8042 status register
  test  al,1                            ; Bit0=1 => output buffer full (data ready at 060h)
  jnz   KbRead2                         ; If ready, go read the scancode
  loop  KbRead1                         ; Else keep polling until timeout
  mov   al,0FFh                         ; Timeout: sentinel meaning "no key"
  mov   [KbChar],al                     ; Publish "no key" to caller
  popa
  ret                                   ; Return (no key)
KbRead2:
  in    al,060h                         ; Read scancode from 8042 data port
  mov   [KbChar],al                     ; Publish scancode to caller
  popa
  ret                                   ; Return (key read)

;--------------------------------------------------------------------------------------------------
; Translate scancode in KbChar to an ASCII character
;   Input:
;     [KbChar] = scancode
;   Output:
;     [KbChar] = ASCII character if mapped, else '?' (unknown/ignored)
;--------------------------------------------------------------------------------------------------
KbXlate:
  pusha
  xor   eax,eax                         ; Clear EAX (AL will hold the scancode/char)
  xor   esi,esi                         ; ESI = table index
  mov   ecx,IgnoreSz                    ; ECX = number of ignore entries
  mov   al,[KbChar]                     ; AL = current scancode
KbXlate1:
  cmp   al,[IgnoreCode+esi]             ; Is this scancode one we ignore (break/release)?
  je    KbXlate2                        ; Yes -> translate to '?'
  inc   esi                             ; Next ignore entry
  loop  KbXlate1                        ; Scan ignore table (up to IgnoreSz entries)
  jmp   KbXlate3                        ; Not ignored -> try normal translation table
KbXlate2:
  mov   al,'?'                          ; Ignored scancode -> publish '?' as placeholder
  jmp   KbXlate6                        ; Store result and return
KbXlate3:
  xor   eax,eax                         ; Clear AL again before table scan
  xor   esi,esi                         ; Reset index to 0
  mov   ecx,ScancodeSz                  ; ECX = number of make-code entries
  mov   al,[KbChar]                     ; AL = scancode to translate
KbXlate4:
  cmp   al,[Scancode+esi]               ; Match scancode against make-code table entry?
  je    KbXlate5                        ; Yes -> use same index into CharCode table
  inc   esi                             ; Next table entry
  loop  KbXlate4                        ; Scan scancode table (up to ScancodeSz entries)
  mov   al,'?'                          ; Not found -> unknown key -> '?'
  jmp   KbXlate6                        ; Store result and return
KbXlate5:
  mov   al,[CharCode+esi]               ; Found -> AL = mapped ASCII character
KbXlate6:
  mov   [KbChar],al                     ; Publish translated character back to KbChar
  popa
  ret