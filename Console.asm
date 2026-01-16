;==============================================================================
; Console.asm (Cn) - Console Input and Output Handler for AsmOSx86
;
; Purpose:
;   Provides routines for console initialization, line input, and line output.
;   Handles user input line editing, carriage return/line feed, and integration
;   with the video and keyboard subsystems.
;
; Coding Standards:
;   - Column alignment (LOCKED-IN)
;   - No blank lines within functions (LOCKED-IN)
;   - PascalCase for variable and label names (LOCKED-IN)
;
; Usage:
;   Call CnInit at system startup to initialize console state.
;   Use CnReadLine to read a line of user input with editing support.
;   Use CnCrLf to output a new line.
;
; Notes:
;   - No reliance on register values across CALL boundaries.
;   - No .bss section; all storage is explicitly zero-initialized.
;   - No globals or sections outside this file.
;==============================================================================

[bits 32]

;------------------------------------------------------------------------------
; CnInit
; Initializes the console input state.
;
; Output (memory):
;   CnInWorkLen = 0    ; Input length cleared
;
; Notes:
; - Should be called once at system startup or reset.
; - Ensures the console input buffer is in a known, clean state.
;------------------------------------------------------------------------------
CnInit:
  mov   word [CnInWorkLen],0                ; Clear input length
  ret

;------------------------------------------------------------------------------
; CnCrLf
; Outputs a carriage return and line feed to the console, advancing to a new line.
;
; Output:
;   Calls VdPutChar twice to emit CR (0x0D) and LF (0x0A) to the video subsystem.
;
; Notes:
; - Used to move the cursor to the beginning of the next line in the console.
; - Follows column alignment and PascalCase coding standards (LOCKED-IN).
;------------------------------------------------------------------------------
CnCrLf:
  mov   byte [VdInCh],0x0D                  ; Carriage return
  call  VdPutChar
  mov   byte [VdInCh],0x0A                  ; Line feed
  call  VdPutChar
  ret

;------------------------------------------------------------------------------
; CnReadLine
; Reads a line of user input from the console with editing support.
;
; Behavior:
;   - Accepts character input, handles backspace and enter keys.
;   - Supports editing the input line before submission.
;   - Stores the input as a length-prefixed string at [CnInDstPtr].
;
; Output (memory):
;   [CnInDstPtr] = Length-prefixed input string (LStr format)
;   CnInWorkLen  = Number of characters entered
;
; Notes:
; - Uses KbGetKey for keyboard input and VdInPutChar for display.
; - Follows column alignment and PascalCase coding standards (LOCKED-IN).
;------------------------------------------------------------------------------
CnReadLine:
  mov   word [CnInWorkLen],0                ; Reset input length
  call  VdInClearLine
CnReadLineLoop:
  call  KbGetKey
  mov   al,[KbOutHasKey]
  test  al,al
  jz    CnReadLineLoop
  mov   al,[KbOutType]
  cmp   al,KEY_CHAR
  je    CnReadLineOnChar
  cmp   al,KEY_BACKSPACE
  je    CnReadLineOnBackspace
  cmp   al,KEY_ENTER
  je    CnReadLineOnEnter
  jmp   CnReadLineLoop
CnReadLineOnChar:
  movzx ecx,word [CnInWorkLen]
  movzx edx,word [CnInMax]
  cmp   ecx,edx
  jae   CnReadLineLoop
  mov   esi,[CnInDstPtr]
  mov   al,[KbOutChar]
  mov   [esi+2+ecx],al
  inc   cx
  mov   [CnInWorkLen],cx
  mov   [VdInCh],al
  call  VdInPutChar
  jmp   CnReadLineLoop
CnReadLineOnBackspace:
  movzx ecx,word [CnInWorkLen]
  test  ecx,ecx
  jz    CnReadLineLoop
  dec   cx
  mov   [CnInWorkLen],cx
  call  VdInBackspaceVisual
  jmp   CnReadLineLoop
CnReadLineOnEnter:
  mov   esi,[CnInDstPtr]
  mov   ax,[CnInWorkLen]
  mov   [esi],ax
  call  VdInClearLine
  ret

; ----- Storage -----

CnInDstPtr       dd 0
CnInMax          dw 0
CnPad0           dw 0
CnInWorkLen      dw 0
CnPad1           dw 0