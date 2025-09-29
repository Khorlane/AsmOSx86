;**********************************************************
; Keyboard.asm
;   Keyboard routines for kernel
;   Provides basic keyboard input functions
;   such as reading scancodes and handling key events.
;**********************************************************

;--------------------------------------------------------------------------------------------------
; Keyboard Routines
;--------------------------------------------------------------------------------------------------

; Read scancode
KbRead:
    mov   ecx,2FFFFh                    ; Set count for loop
KbWait:
    in    al,064h                       ; Read 8042 Status Register (bit 1 is input buffer status (0=empty, 1=full)
    test  al,1                          ; If bit 1
    jnz   KbGetIt                       ;  go get scancode
    loop  KbWait                        ; Keep looping
    mov   al,0FFh                       ; No scan
    mov   [KbChar],al                   ;  code received
    ret                                 ; All done!
KbGetIt:
    in    al,060h                       ; Obtain scancode from
    mov   [KbChar],al                   ;  Keyboard I/O Port
    ret                                 ; All done!

; Translate scancode to ASCII character
KbXlate:
    xor   eax,eax
    xor   esi,esi
    mov   ecx,ScancodeSz
    mov   al,[KbChar]                   ; Put scancode in AL
KbXlateLoop1:
    cmp   al,[Scancode+esi]             ; Compare to Scancode
    je    KbXlateFound                  ; Match!
    inc   esi                           ; Bump ESI
    loop  KbXlateLoop1                  ; Check next
    mov   al,'?'                        ; Not found defaults to ? for now
    jmp   KbXlateDone                   ; Jump to done
KbXlateFound:
    mov   al,[CharCode+esi]             ; Put ASCII character matching the Scancode in AL
KbXlateDone:
    mov   [KbChar],al                   ; Put translated char in KbChar
    ret     