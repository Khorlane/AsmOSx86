;==============================================================================
; Keyboard.asm (Kb) - Keyboard Input Handler for AsmOSx86
;
; Purpose:
;   Provides routines for initializing keyboard state and reading key events
;   from the PC/AT keyboard hardware. Handles shift state, scancode decoding,
;   and ASCII translation.
;
; Coding Standards:
;   - Column alignment (LOCKED-IN)
;   - No blank lines within functions (LOCKED-IN)
;   - PascalCase for variable and label names (LOCKED-IN)
;
; Usage:
;   Call KbInit at system startup to initialize keyboard state.
;   Call KbGetKey to poll and decode key events.
;
; Notes:
;   - No reliance on register values across CALL boundaries.
;   - No .bss section; all storage is explicitly zero-initialized.
;   - No globals or sections outside this file.
;==============================================================================
;------------------------------------------------------------------------------
; KbInit
; Initializes keyboard state variables.
;
; Output (memory):
;   KbModShift    = 0   ; Shift modifier cleared
;   KbOutHasKey   = 0   ; No key event pending
;   KbOutType     = KEY_NONE ; Output type set to none
;   KbOutChar     = 0   ; Output character cleared
;
; Notes:
; - Should be called once at system startup or reset.
; - Ensures keyboard state is in a known, clean state.
;------------------------------------------------------------------------------
KbInit:
  mov   byte [KbModShift],0             ; Clear shift modifier
  mov   byte [KbOutHasKey],0            ; Clear key output flag
  mov   byte [KbOutType],KEY_NONE       ; Set output type to none
  mov   byte [KbOutChar],0              ; Clear output character
  ret

;------------------------------------------------------------------------------
; KbGetKey
; Reads a key event from the keyboard hardware and decodes it.
; 
; Output (memory):
;   KbOutHasKey = 1 if a key event is available, 0 otherwise
;   KbOutType   = KEY_CHAR, KEY_ENTER, KEY_BACKSPACE, or KEY_NONE
;   KbOutChar   = ASCII value if KEY_CHAR, undefined otherwise
;
; Notes:
; - Handles shift state and translates scancodes to ASCII.
; - Does not rely on register values across CALL boundaries.
;------------------------------------------------------------------------------
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