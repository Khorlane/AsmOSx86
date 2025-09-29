;**********************************************************
; Keyboard.asm
;   Keyboard routines for kernel
;   Provides basic keyboard input functions
;   such as reading scancodes and handling key events.
;**********************************************************

;--------------------------------------------------------------------------------------------------
; Keyboard Routines
;--------------------------------------------------------------------------------------------------
KbRead:
    ; Read scancode
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
    mov   [KbChar],al                   ;   Keyboard I/O Port
    ret                                 ; All done!