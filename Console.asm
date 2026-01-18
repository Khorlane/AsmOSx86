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
CN_IN_MAX        equ 80                 ; maximum console input length
; ----- Console variables -----
CnInDstPtr       dd 0
CnInMax          dw 0
CnPad0           dw 0
CnInWorkLen      dw 0
CnPad1           dw 0
; Strings
CmdBuf: times (2 + CN_IN_MAX) db 0      ; Command line buffer as String:
String  CnStartMsg1,"AsmOSx86 Console (Session 0)"
String  CnStartMsg2,"AsmOSx86 - A Hobbyist Operating System in x86 Assembly"
String  CnStartMsg3,"AsmOSx86 Initialization started"

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
  call  CnReadLine                      ; Echoes on bottom row; returns string in CmdBuf
  jmp   Console

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
  mov   al,Cyan                         ; Background
  mov   [VdColorBack],al                ;  color
  mov   al,Purple                       ; Foreground
  mov   [VdColorFore],al                ;  color
  call  VdSetColorAttr                  ; Set color
  call  VdClear                         ; Clear screen
  lea   eax,[CnStartMsg1]               ; Print 
  mov   [VdInStrPtr],eax                ;  startup
  call  VdPutStr                        ;  message 1
  call  CnCrLf                          ;  with new line
  mov   ax,[VdCurRow]                   ; Bump
  inc   ax                              ;  row
  mov   [VdCurRow],ax                   ;  by 1
  lea   eax,[CnStartMsg2]               ; Print 
  mov   [VdInStrPtr],eax                ;  startup
  call  VdPutStr                        ;  message 2
  call  CnCrLf                          ;  with new line
  mov   ax,[VdCurRow]                   ; Bump
  inc   ax                              ;  row
  mov   [VdCurRow],ax                   ;  by 1
  lea   eax,[CnStartMsg3]               ; Print 
  mov   [VdInStrPtr],eax                ;  startup
  call  VdPutStr                        ;  message 3
  call  CnCrLf                          ;  with new line
  xor   ax,ax                           ; Clear input
  mov   [CnInWorkLen],ax                ;  length
  lea   eax,[CmdBuf]                    ; Set destination 
  mov   [CnInDstPtr],eax                ;  buffer for input
  mov   ax,CN_IN_MAX                    ; Set max chars
  mov   [CnInMax],ax                    ;  to read
  mov   ax,25
  mov   [VdCurRow],ax
  mov   ax,1
  mov   [VdCurCol],ax
  call  VdSetCursor
  call  TimeDtPrint ; Temprary time print for testing
  call  CnCrLf
  call  TimeTmPrint ; Temprary time print for testing
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
  mov   al,0x0D                          ; Carriage return
  mov   [VdInCh],al
  call  VdPutChar
  mov   al,0x0A                          ; Line feed
  mov   [VdInCh],al
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
  xor   ax,ax
  mov   [CnInWorkLen],ax                ; Reset input length
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
  mov   ax,[CnInWorkLen]
  movzx ecx,ax
  mov   ax,[CnInMax]
  movzx edx,ax
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
  mov   ax,[CnInWorkLen]
  movzx ecx,ax
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