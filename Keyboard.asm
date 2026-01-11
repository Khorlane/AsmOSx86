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