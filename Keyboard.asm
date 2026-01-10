;**************************************************************************************************
; Keyboard.asm
;   Keyboard routines for kernel
;   Provides basic keyboard input functions
;   such as reading scancodes and handling key events.
;**************************************************************************************************

;--------------------------------------------------------------------------------------------------
; Read a scancode from the keyboard
;--------------------------------------------------------------------------------------------------
KbRead:
  mov   ecx,2FFFFh                      ; Set count for loop
KbRead1:
  in    al,064h                         ; Read 8042 Status Register (bit 1 is input buffer status (0=empty, 1=full)
  test  al,1                            ; If bit 1
  jnz   KbRead2                         ; go get scancode
  loop  KbRead1                         ; Keep looping
  mov   al,0FFh                         ; No scan
  mov   [KbChar],al                     ; code received
  ret                                   ; All done!
KbRead2:
  in    al,060h                         ; Obtain scancode from
  mov   [KbChar],al                     ; Keyboard I/O Port
  ret                                   ; All done!

 ;--------------------------------------------------------------------------------------------------
; Translate scancode to ASCII character
;--------------------------------------------------------------------------------------------------
KbXlate:
  xor   eax,eax
  xor   esi,esi
  mov   ecx,IgnoreSz
  mov   al,[KbChar]
KbXlate1:
  cmp   al,[IgnoreCode+esi]
  je    KbXlate2
  inc   esi
  loop  KbXlate1
  jmp   KbXlate3
KbXlate2:
  mov   al,'?'
  jmp   KbXlate6
KbXlate3:
  xor   eax,eax
  xor   esi,esi
  mov   ecx,ScancodeSz
  mov   al,[KbChar]
KbXlate4:
  cmp   al,[Scancode+esi]
  je    KbXlate5
  inc   esi
  loop  KbXlate4
  mov   al,'?'
  jmp   KbXlate6
KbXlate5:
  mov   al,[CharCode+esi]
KbXlate6:
  mov   [KbChar],al
  ret