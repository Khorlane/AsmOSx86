; Keyboard.asm (Kb) - no sections, no globals

KbInit:
  mov   byte [KbModShift],0             ; Clear shift modifier
  mov   byte [KbOutHasKey],0            ; Clear key output flag
  mov   byte [KbOutType],KEY_NONE       ; Set output type to none
  mov   byte [KbOutChar],0              ; Clear output character
  ret

KbGetKey:
  mov   byte [KbOutHasKey],0            ; Clear key output flag
  mov   byte [KbOutType],KEY_NONE       ; Set output type to none
  mov   byte [KbOutChar],0              ; Clear output character
  in    al,KBD_STATUS_PORT              ; Read keyboard status
  test  al,0x01                         ; Key available?
  jz    KbGetKeyNoKey
  in    al,KBD_DATA_PORT                ; Read key data
  mov   [KbWorkScanCode],al             ; Save scancode
  test  al,0x80                         ; Break code?
  jnz   KbGetKeyOnBreak
  cmp   al,0x2A                         ; Shift down?
  je    KbGetKeyShiftDown
  cmp   al,0x36
  je    KbGetKeyShiftDown
  cmp   al,0x1C                         ; Enter?
  je    KbGetKeyMakeEnter
  cmp   al,0x0E                         ; Backspace?
  je    KbGetKeyMakeBackspace
  movzx esi,byte [KbWorkScanCode]       ; ESI = scancode
  mov   bl,[KbModShift]                 ; BL = shift state
  test  bl,bl
  jz    KbGetKeyUnshifted

KbGetKeyShifted:
  mov   al,[KbScanToAsciiShift+esi]     ; Shifted ASCII
  jmp   KbGetKeyMaybeChar

KbGetKeyUnshifted:
  mov   al,[KbScanToAscii+esi]          ; Unshifted ASCII

KbGetKeyMaybeChar:
  test  al,al
  jz    KbGetKeyNoKey
  mov   byte [KbOutHasKey],1            ; Mark key present
  mov   byte [KbOutType],KEY_CHAR       ; Mark as char
  mov   [KbOutChar],al                  ; Store char
  ret

KbGetKeyOnBreak:
  and   al,0x7F                         ; Remove break bit
  cmp   al,0x2A                         ; Shift up?
  je    KbGetKeyShiftUp
  cmp   al,0x36
  je    KbGetKeyShiftUp
  jmp   KbGetKeyNoKey

KbGetKeyShiftDown:
  mov   byte [KbModShift],1             ; Set shift
  jmp   KbGetKeyNoKey

KbGetKeyShiftUp:
  mov   byte [KbModShift],0             ; Clear shift
  jmp   KbGetKeyNoKey

KbGetKeyMakeEnter:
  mov   byte [KbOutHasKey],1            ; Mark key present
  mov   byte [KbOutType],KEY_ENTER      ; Mark as enter
  ret

KbGetKeyMakeBackspace:
  mov   byte [KbOutHasKey],1            ; Mark key present
  mov   byte [KbOutType],KEY_BACKSPACE  ; Mark as backspace
  ret

KbGetKeyNoKey:
  ret

; ----- Storage (explicit zeros; no .bss) -----

KbModShift        db 0
KbOutHasKey       db 0
KbOutType         db 0
KbOutChar         db 0
KbPad0            db 0
KbWorkScanCode    db 0
KbPad1            db 0,0,0

; ----- Scancode tables (same as before) -----

KbScanToAscii:
    times 0x02 db 0
    db '1','2','3','4','5','6','7','8','9','0'
    db '-','='
    db 0
    db 0
    db 'q','w','e','r','t','y','u','i','o','p'
    db '[',']'
    db 0
    db 0
    db 'a','s','d','f','g','h','j','k','l'
    db ';',39,'`'
    db 0
    db '\'
    db 'z','x','c','v','b','n','m'
    db ',', '.', '/'
    db 0
    db '*'
    db 0
    db ' '
    times (128 - 0x3A) db 0

KbScanToAsciiShift:
    times 0x02 db 0
    db '!','@','#','$','%','^','&','*','(',')'
    db '_','+'
    db 0
    db 0
    db 'Q','W','E','R','T','Y','U','I','O','P'
    db '{','}'
    db 0
    db 0
    db 'A','S','D','F','G','H','J','K','L'
    db ':','"','~'
    db 0
    db '|'
    db 'Z','X','C','V','B','N','M'
    db '<','>','?'
    db 0
    db '*'
    db 0
    db ' '
    times (128 - 0x3A) db 0