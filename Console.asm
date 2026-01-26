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
align 4
CnHelpCnt        dd 0                  ; Number of help entries 
CnTmpCount       dd 0                  ; temp: table entry count
pCnCmdLine       dd 0                  ; Pointer to command line buffer
pCnCmdTable      dd 0                  ; Pointer to command table
pCnLogMsg        dd 0                  ; Pointer to log message
pCnTmpInput      dd 0                  ; Pointer to temp: input payload
pCnTmpTable      dd 0                  ; Pointer to temp: command table
CnCmdLineLen     dw 0                  ; Command line length
CnCmdMaxLen      dw 0                  ; Command line max length
CnTmpLen         dw 0                  ; temp: input length (u16)

; Command line buffer as String:
CnCmdLine: times (2 + CN_CMD_MAX_LEN) db 0

; Strings
String  CnStartMsg1,"AsmOSx86 - A Hobbyist Operating System in x86 Assembly"
String  CnStartMsg2,"Console (Session 0)"
String  CnStartMsg3,"Initialization started"
String  CnShutdown1,"AsmOSx86 shutting down system..."
String  CnShutdown2,"Shutdown complete."
String  CnDelayMsg1,"Delay test start (2000ms 2 seconds)"
String  CnDelayMsg2,"Delay test end"


; ----- Console commands -----
String  CnCmdDate,     "Date"
String  CnCmdDelay,    "Delay"
String  CnCmdHelp,     "Help"
String  CnCmdShutdown, "Shutdown"
String  CnCmdTime,     "Time"

; Console Command Table and Handlers
align 4
CnCmdTable:
  dd CnCmdDate,     CnDoCmdDate
  dd CnCmdDelay,    CnDoCmdDelay
  dd CnCmdHelp,     CnDoCmdHelp
  dd CnCmdShutdown, CnDoCmdShutdown
  dd CnCmdTime,     CnDoCmdTime
CnCmdTableEnd:
CnCmdTableCount equ (CnCmdTableEnd-CnCmdTable)/8

;------------------------------------------------------------------------------
; Console
; Main console loop for AsmOSx86.
;
; Behavior:
; - Continuously reads a line of user input using CnReadLine.
; - Echoes input on the bottom row of the screen.
; - Intended as the primary user interaction loop.
;
; Notes:
; - Each iteration waits for and processes a full line of input.
; - Output is displayed immediately; command processing can be added as needed.
;------------------------------------------------------------------------------
Console:
  call  CnReadLine                      ; Returns string in CnCmdLine
  lea   eax,[CnCmdLine]                 ; Echo the
  mov   [pCnLogMsg],eax                 ;  entered command
  call  CnLogIt                         ;  command
  lea   eax,[CnCmdLine]
  mov   [pStr1],eax
  call  StrTrim
  call  CnCmdDispatch                   ; Call handler if match
  jmp   Console

;------------------------------------------------------------------------------
; CnInit
; Initializes the console input state.
;
; Output (memory):
;   CnCmdLineLen = 0                        ; Input length cleared
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
  mov   [CnCmdLineLen],ax               ;  length
  lea   eax,[CnCmdLine]                 ; Set destination
  mov   [pCnCmdLine],eax                ;  buffer for input
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
;   - Stores the input as a length-prefixed string at [pCnCmdLine].
;
; Output (memory):
;   [pCnCmdLine]   = Length-prefixed input string (Str format)
;   CnCmdLineLen  = Number of characters entered
;
; Notes:
; - Uses KbGetKey for keyboard input and VdInPutChar for display.
; - Follows column alignment and PascalCase coding standards (LOCKED-IN).
;------------------------------------------------------------------------------
CnReadLine:
  xor   ax,ax
  mov   [CnCmdLineLen],ax               ; Reset input length
  call  VdInClearLine
CnReadLineLoop:
  call  TimerNowTicks                   ; keep accumulator updated
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
  mov   ax,[CnCmdLineLen]
  movzx ecx,ax
  mov   ax,[CnCmdMaxLen]
  movzx edx,ax
  cmp   ecx,edx
  jae   CnReadLineLoop
  mov   esi,[pCnCmdLine]
  mov   al,[KbOutChar]
  mov   [esi+2+ecx],al
  inc   cx
  mov   [CnCmdLineLen],cx
  mov   [VdInCh],al
  call  VdInPutChar
  jmp   CnReadLineLoop
CnReadLineOnBackspace:
  mov   ax,[CnCmdLineLen]
  movzx ecx,ax
  test  ecx,ecx
  jz    CnReadLineLoop
  dec   cx
  mov   [CnCmdLineLen],cx
  call  VdInBackspaceVisual
  jmp   CnReadLineLoop
CnReadLineOnEnter:
  mov   esi,[pCnCmdLine]
  mov   ax,[CnCmdLineLen]
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

;------------------------------------------------------------------------------
; CnCmdDispatch
; Dispatches the command in CnCmdLine by searching CnCmdTable entries:
;   dd CnCmdNameStr,CnCmdHandler
; Match policy:
;   - exact match, case-insensitive, length must match
; On match:
;   - Calls the handler
; On no match:
;   - Just returns
;------------------------------------------------------------------------------
CnCmdDispatch:
  lea   eax,[CnCmdLine]                 ; EAX = input Str
  mov   bx,[eax]                        ; BX  = input length
  mov   [CnTmpLen],bx                   ; save len (u16)
  lea   eax,[eax+2]                     ; EAX = input payload
  mov   [pCnTmpInput],eax               ; save input payload ptr
  mov   eax,CnCmdTable                  ; EAX = table base
  mov   [pCnTmpTable],eax               ; save table ptr
  mov   eax,CnCmdTableCount             ; EAX = entry count
  mov   [CnTmpCount],eax                ; save count
CnCmdDispatchNext:
  mov   eax,[CnTmpCount]                ; remaining entries
  test  eax,eax
  jz    CnCmdDispatchDone
  mov   edi,[pCnTmpTable]               ; EDI = entry ptr
  mov   ebx,[edi]                       ; EBX = ptr to command Str
  mov   dx,[ebx]                        ; DX  = cmd length
  cmp   dx,[CnTmpLen]                   ; length match?
  jne   CnCmdDispatchSkip
  ; compare payloads, case-insensitive
  movzx ecx,word[CnTmpLen]              ; ECX = compare count
  mov   esi,[pCnTmpInput]               ; ESI = input payload
  lea   ebx,[ebx+2]                     ; EBX = cmd payload
CnCmdDispatchCmp:
  test  ecx,ecx
  jz    CnCmdDispatchMatch
  mov   al,[esi]                        ; input char
  mov   ah,[ebx]                        ; table char
  cmp   al,'A'
  jb    CnCmdCi1
  cmp   al,'Z'
  ja    CnCmdCi1
  add   al,32                           ; input -> lowercase
CnCmdCi1:
  cmp   ah,'A'
  jb    CnCmdCi2
  cmp   ah,'Z'
  ja    CnCmdCi2
  add   ah,32                           ; table -> lowercase
CnCmdCi2:
  cmp   al,ah
  jne   CnCmdDispatchSkip
  inc   esi
  inc   ebx
  dec   ecx
  jmp   CnCmdDispatchCmp
CnCmdDispatchMatch:
  mov   eax,[edi+4]                     ; EAX = handler address
  call  eax
  ret
CnCmdDispatchSkip:
  mov   eax,[pCnTmpTable]               ; advance to next entry
  add   eax,8
  mov   [pCnTmpTable],eax
  mov   eax,[CnTmpCount]
  dec   eax
  mov   [CnTmpCount],eax
  jmp   CnCmdDispatchNext
CnCmdDispatchDone:
  ret

;------------------------------------------------------------------------------
; Command Handlers
; Each handler corresponds to a command in CnCmdTable.
; Handlers perform specific actions based on the command invoked.
;------------------------------------------------------------------------------
CnDoCmdDate:
  call  TimeDtPrint
  call  CnCrLf
  ret

CnDoCmdDelay:
  call  TimeTmPrint
  call  CnSpace
  lea   eax,[CnDelayMsg1]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  mov   eax,2000
  call  TimerDelayMs
  call  TimeTmPrint
  call  CnSpace
  lea   eax,[CnDelayMsg2]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret

CnDoCmdHelp:
  mov   eax,CnCmdTable
  mov   [pCnCmdTable],eax
  mov   eax,CnCmdTableCount
  mov   [CnHelpCnt],eax
CnDoCmdHelpLoop:
  mov   eax,[CnHelpCnt]
  test  eax,eax
  jz    CnDoCmdHelpDone
  mov   eax,[pCnCmdTable]               ; EAX = entry ptr (safe)
  mov   ebx,[eax]                       ; EBX = ptr to command Str
  mov   [pVdStr],ebx
  call  VdPutStr
  call  CnCrLf
  mov   eax,[pCnCmdTable]               ; reload (calls clobbered regs)
  add   eax,8                           ; next entry
  mov   [pCnCmdTable],eax
  mov   eax,[CnHelpCnt]
  dec   eax
  mov   [CnHelpCnt],eax
  jmp   CnDoCmdHelpLoop
CnDoCmdHelpDone:
  ret

CnDoCmdShutdown:
  lea   eax,[CnShutdown1]               ; Print 1st
  mov   [pCnLogMsg],eax                 ;  shutdown
  call  CnLogIt                         ;  message
  lea   eax,[CnShutdown2]               ; Print 2nd
  mov   [pCnLogMsg],eax                 ;  shutdown
  call  CnLogIt                         ;  message
  mov   ax,0x2000                       ; select Bochs power-control port
  mov   dx,0xB004                       ;  "soft power off" value
  out   dx,ax                           ;  write value to port
  mov   dx,0x604                        ; Alternate ACPI 
  out   dx,ax                           ;  poweroff port
  cli                                   ; Fallback behavior
  hlt                                   ;  if above fails
  ret                                   ; Never reached

CnDoCmdTime:
  call  TimeTmPrint
  call  CnCrLf
  ret