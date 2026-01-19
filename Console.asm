;==============================================================================
; Console.asm (Cn) - Console Input and Output Handler for AsmOSx86
;
; Purpose:
;   Provides routines for console initialization, line input, and line output.
;   Handles user input line editing, carriage return/line feed, and integration
;   with the video and keyboard subsystems.
;
; Usage:
;   Call CnInit at system startup to initialize console state.
;   Use CnReadLine to read a line of user input with editing support.
;   Use CnCrLf to output a new line.
;==============================================================================

[bits 32]

; ----- Console constants -----
CN_CMD_MAX_LEN   equ 79                 ; maximum console input length
; ----- Console variables -----
pCnCmd           dd 0
pCnLogMsg        dd 0
CnCmdLen         dw 0
CnCmdMaxLen      dw 0
; Strings
CnCmd: times (2 + CN_CMD_MAX_LEN) db 0  ; Command line buffer as String:
String  CnStartMsg1,"AsmOSx86 - A Hobbyist Operating System in x86 Assembly"
String  CnStartMsg2,"Console (Session 0)"
String  CnStartMsg3,"Initialization started"

;------------------------------------------------------------------------------
; Console
; Main console loop for AsmOSx86.
;
; Behavior:
;   - Continuously reads a line of user input using CnReadLine.
;   - Echoes input on the bottom row of the screen.
;   - Intended as the primary user interaction loop.
;
; Notes:
;   - Each iteration waits for and processes a full line of input.
;   - Output is displayed immediately; command processing can be added as needed.
;------------------------------------------------------------------------------
Console:
  call  CnReadLine                      ; Returns string in CnCmd
  lea   eax,[CnCmd]                     ; Echo the
  mov   [pCnLogMsg],eax                 ;  entered command
  call  CnLogIt                         ;  command
  jmp   Console

;------------------------------------------------------------------------------
; CnInit
; Initializes the console input state.
;
; Output (memory):
;   CnCmdLen = 0                        ; Input length cleared
;
; Notes:
; - Should be called once at system startup or reset.
; - Ensures the console input buffer is in a known, clean state.
;------------------------------------------------------------------------------
CnInit:
  mov   al,Black                        ; Background
  mov   [VdColorBack],al                ;  color
  mov   al,Purple                       ; Foreground
  mov   [VdColorFore],al                ;  color
  call  VdSetColorAttr                  ; Set color
  call  VdClear                         ; Clear screen
  xor   ax,ax                           ; Clear input
  mov   [CnCmdLen],ax                   ;  length
  lea   eax,[CnCmd]                     ; Set destination
  mov   [pCnCmd],eax                    ;  buffer for input
  mov   ax,CN_CMD_MAX_LEN               ; Set max chars
  mov   [CnCmdMaxLen],ax                ;  to read
  mov   ax,25                           ; Set
  mov   [VdCurRow],ax                   ;  row to 25
  mov   ax,1                            ; Set
  mov   [VdCurCol],ax                   ;  column to 1
  call  VdSetCursor                     ; Update cursor position
  ; Log startup messages
  lea  eax,[CnStartMsg1]
  mov  [pCnLogMsg],eax
  call CnLogIt
  lea  eax,[CnStartMsg2]
  mov  [pCnLogMsg],eax
  call CnLogIt
  lea  eax,[CnStartMsg3]
  mov  [pCnLogMsg],eax
  call CnLogIt
  ret

;------------------------------------------------------------------------------
; CnCrLf - Outputs a carriage return and line feed to the console
; Output:
;   Calls VdPutStr to print CRLF sequence
; Notes:
; - Used to move the cursor to the beginning of the next line in the console
;------------------------------------------------------------------------------
CnCrLf:
  lea   eax,[CrLf]        
  mov   [pVdStr],eax         
  call  VdPutStr   
  ret

;------------------------------------------------------------------------------
; CnSpace -  Outputs a space character to the console
; Output:
;   Calls VdPutStr to print space character
; Notes:
; - Used to insert a space in the console output
;------------------------------------------------------------------------------
CnSpace:
  lea   eax,[Space1]
  mov   [pVdStr],eax
  call  VdPutStr
  ret

;------------------------------------------------------------------------------
; CnReadLine
; Reads a line of user input from the console with editing support.
;
; Behavior:
;   - Accepts character input, handles backspace and enter keys.
;   - Supports editing the input line before submission.
;   - Stores the input as a length-prefixed string at [pCnCmd].
;
; Output (memory):
;   [pCnCmd]   = Length-prefixed input string (LStr format)
;   CnCmdLen  = Number of characters entered
;
; Notes:
; - Uses KbGetKey for keyboard input and VdInPutChar for display.
; - Follows column alignment and PascalCase coding standards (LOCKED-IN).
;------------------------------------------------------------------------------
CnReadLine:
  xor   ax,ax
  mov   [CnCmdLen],ax                ; Reset input length
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
  mov   ax,[CnCmdLen]
  movzx ecx,ax
  mov   ax,[CnCmdMaxLen]
  movzx edx,ax
  cmp   ecx,edx
  jae   CnReadLineLoop
  mov   esi,[pCnCmd]
  mov   al,[KbOutChar]
  mov   [esi+2+ecx],al
  inc   cx
  mov   [CnCmdLen],cx
  mov   [VdInCh],al
  call  VdInPutChar
  jmp   CnReadLineLoop
CnReadLineOnBackspace:
  mov   ax,[CnCmdLen]
  movzx ecx,ax
  test  ecx,ecx
  jz    CnReadLineLoop
  dec   cx
  mov   [CnCmdLen],cx
  call  VdInBackspaceVisual
  jmp   CnReadLineLoop
CnReadLineOnEnter:
  mov   esi,[pCnCmd]
  mov   ax,[CnCmdLen]
  mov   [esi],ax
  call  VdInClearLine
  ret

; -----------------------------------------------------------------------------
; CnLogIt - Logs a message with timestamp to the console
; Output: None
; Notes:
; - Uses TimeDtPrint and TimeTmPrint for timestamping
; - Outputs the message pointed to by pCnLogMsg
; -----------------------------------------------------------------------------
CnLogIt:
  call  TimeDtPrint
  call  CnSpace
  call  TimeTmPrint
  call  CnSpace
  mov   eax,[pCnLogMsg]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret