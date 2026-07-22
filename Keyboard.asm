;**************************************************************************************************
; Keyboard.asm
;   PC/AT keyboard input handling for AsmOSx86.
;
; Purpose
;   Initialize keyboard state, poll the keyboard controller, track modifier
;   state, decode scancodes, and translate supported keys to ASCII/events.
;
; Contains
;   - Keyboard state initialization
;   - Single-key polling
;   - Shift make/break tracking
;   - Scancode-to-ASCII translation
;
; Notes
;   - KbInit is called during kernel startup.
;   - KbGetKey polls once and returns memory-backed key state.
;   - Physical keyboard hardware remains kernel-owned.
;**************************************************************************************************

[bits 32]

; ----- Keyboard constants -----
KEY_NONE        equ 0
KEY_CHAR        equ 1
KEY_ENTER       equ 2
KEY_BACKSPACE   equ 3

KBD_STATUS_PORT equ 0x64
KBD_DATA_PORT   equ 0x60

;------------------------------------------------------------------------------
; KbInit
;   Output:
;     KbModShift  = 0
;     KbOutHasKey = 0
;     KbOutType   = KEY_NONE
;     KbOutChar   = 0
; Notes:
;     Initializes keyboard state to a known idle state.
;------------------------------------------------------------------------------
KbInit:
  xor   eax,eax
  mov   [KbModShift],al                 ; Clear shift modifier
  mov   [KbOutHasKey],al                ; Clear key output flag
  mov   [KbOutType],al                  ; Set output type to none
  mov   [KbOutChar],al                  ; Clear output character
  ret

;------------------------------------------------------------------------------
; KbGetKey
;   Output:
;     KbOutHasKey = 1 if a key event is available, 0 otherwise
;     KbOutType   = KEY_CHAR, KEY_ENTER, KEY_BACKSPACE, or KEY_NONE
;     KbOutChar   = ASCII value if KEY_CHAR, 0 otherwise
;     KbModShift  = updated shift state when shift make/break is seen
; Notes:
;     Polls the keyboard controller once.
;     Handles shift state and translates scancodes to ASCII.
;------------------------------------------------------------------------------
KbGetKey:
  xor   eax,eax
  mov   [KbOutHasKey],al                ; Clear key output flag
  mov   [KbOutType],al                  ; Set output type to none
  mov   [KbOutChar],al                  ; Clear output character
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
  xor   esi,esi
  mov   al,[KbWorkScanCode]
  movzx esi,al                          ; ESI = scancode
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
  mov   bl,1
  mov   [KbOutHasKey],bl                ; Mark key present
  mov   bl,KEY_CHAR
  mov   [KbOutType],bl                  ; Mark as char
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
  mov   al,1
  mov   [KbModShift],al                 ; Set shift
  jmp   KbGetKeyNoKey
KbGetKeyShiftUp:
  xor   eax,eax
  mov   [KbModShift],al                 ; Clear shift
  jmp   KbGetKeyNoKey
KbGetKeyMakeEnter:
  mov   al,1
  mov   [KbOutHasKey],al                ; Mark key present
  mov   al,KEY_ENTER
  mov   [KbOutType],al                  ; Mark as enter
  ret
KbGetKeyMakeBackspace:
  mov   al,1
  mov   [KbOutHasKey],al                ; Mark key present
  mov   al,KEY_BACKSPACE
  mov   [KbOutType],al                  ; Mark as backspace
  ret
KbGetKeyNoKey:
  ret

; ----- Storage -----
KbModShift        db 0
KbOutHasKey       db 0
KbOutType         db 0
KbOutChar         db 0
KbPad0            db 0
KbWorkScanCode    db 0
KbPad1            db 0,0,0

; ----- Scancode tables -----
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
    db 0x5C ; '\' backslash
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
