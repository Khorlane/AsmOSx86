; Keyboard.asm (Kb) - no sections, no globals

KbInit:
  mov   byte [Kb_Mod_Shift],0           ; Clear shift modifier
  mov   byte [Kb_Out_HasKey],0          ; Clear key output flag
  mov   byte [Kb_Out_Type],KEY_NONE     ; Set output type to none
  mov   byte [Kb_Out_Char],0            ; Clear output character
  ret

KbGetKey:
  mov   byte [Kb_Out_HasKey],0          ; Clear key output flag
  mov   byte [Kb_Out_Type],KEY_NONE     ; Set output type to none
  mov   byte [Kb_Out_Char],0            ; Clear output character

  in    al,KBD_STATUS_PORT              ; Read keyboard status
  test  al,0x01                         ; Key available?
  jz    KbGetKey_NoKey

  in    al,KBD_DATA_PORT                ; Read key data
  mov   [Kb_Work_ScanCode],al           ; Save scancode

  test  al,0x80                         ; Break code?
  jnz   KbGetKey_OnBreak

  cmp   al,0x2A                         ; Shift down?
  je    KbGetKey_ShiftDown
  cmp   al,0x36
  je    KbGetKey_ShiftDown

  cmp   al,0x1C                         ; Enter?
  je    KbGetKey_MakeEnter

  cmp   al,0x0E                         ; Backspace?
  je    KbGetKey_MakeBackspace

  movzx esi,byte [Kb_Work_ScanCode]     ; ESI = scancode
  mov   bl,[Kb_Mod_Shift]               ; BL = shift state
  test  bl,bl
  jz    KbGetKey_Unshifted

KbGetKey_Shifted:
  mov   al,[Kb_ScanToAscii_Shift+esi]   ; Shifted ASCII
  jmp   KbGetKey_MaybeChar

KbGetKey_Unshifted:
  mov   al,[Kb_ScanToAscii+esi]         ; Unshifted ASCII

KbGetKey_MaybeChar:
  test  al,al
  jz    KbGetKey_NoKey

  mov   byte [Kb_Out_HasKey],1          ; Mark key present
  mov   byte [Kb_Out_Type],KEY_CHAR     ; Mark as char
  mov   [Kb_Out_Char],al                ; Store char
  ret

KbGetKey_OnBreak:
  and   al,0x7F                         ; Remove break bit
  cmp   al,0x2A                         ; Shift up?
  je    KbGetKey_ShiftUp
  cmp   al,0x36
  je    KbGetKey_ShiftUp
  jmp   KbGetKey_NoKey

KbGetKey_ShiftDown:
  mov   byte [Kb_Mod_Shift],1           ; Set shift
  jmp   KbGetKey_NoKey

KbGetKey_ShiftUp:
  mov   byte [Kb_Mod_Shift],0           ; Clear shift
  jmp   KbGetKey_NoKey

KbGetKey_MakeEnter:
  mov   byte [Kb_Out_HasKey],1          ; Mark key present
  mov   byte [Kb_Out_Type],KEY_ENTER    ; Mark as enter
  ret

KbGetKey_MakeBackspace:
  mov   byte [Kb_Out_HasKey],1          ; Mark key present
  mov   byte [Kb_Out_Type],KEY_BACKSPACE ; Mark as backspace
  ret

KbGetKey_NoKey:
  ret

; ----- Storage (explicit zeros; no .bss) -----

Kb_Mod_Shift      db 0

Kb_Out_HasKey     db 0
Kb_Out_Type       db 0
Kb_Out_Char       db 0
Kb_Pad0           db 0

Kb_Work_ScanCode  db 0
Kb_Pad1           db 0,0,0

; ----- Scancode tables (same as before) -----

Kb_ScanToAscii:
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

Kb_ScanToAscii_Shift:
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