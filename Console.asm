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
CnRlActive       db 0                  ; 1=in-progress line edit,0=idle
CnOutHasLine     db 0                  ; 1=completed line ready in CnCmdLine
CnPad2           db 0,0                ; pad to keep alignment friendly

; Command line buffer as String:
CnCmdLine: times (2 + CN_CMD_MAX_LEN) db 0

; Strings
String  CnStartMsg1,"AsmOSx86 - A Hobbyist Operating System in x86 Assembly"
String  CnStartMsg2,"Console (Session 0)"
String  CnStartMsg3,"Initialization started"
String  CnShutdown1,"AsmOSx86 shutting down system..."
String  CnShutdown2,"System halted. It is now safe to power off."
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
;   Output:
;     Reads completed command lines, logs them, trims them, and dispatches commands.
; Notes:
;     Uses pCnLogMsg and pStr1 as memory-backed call inputs after CnReadLine
;     reports a completed line through CnOutHasLine.
;------------------------------------------------------------------------------
Console:
  call  CnReadLine                      ; non-blocking line editor
  mov   al,[CnOutHasLine]
  test  al,al
  jz    ConsoleDone
  lea   eax,[CnCmdLine]
  mov   [pCnLogMsg],eax
  call  CnLogIt
  lea   eax,[CnCmdLine]
  mov   [pStr1],eax
  call  StrTrim
  call  CnCmdDispatch
ConsoleDone:
  ret

;------------------------------------------------------------------------------
; CnInit
;   Output:
;     Initializes console input state, command buffer metadata, video color,
;     cursor position, and startup log messages.
; Notes:
;     Sets pCnCmdLine, CnCmdMaxLen, CnCmdLineLen, VdCurRow, and VdCurCol.
;     Uses pCnLogMsg as the memory-backed input to CnLogIt.
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
  lea   eax,[CnStartMsg1]
  mov   [pCnLogMsg],eax
  call  CnLogIt
  lea   eax,[CnStartMsg2]
  mov   [pCnLogMsg],eax
  call  CnLogIt
  lea   eax,[CnStartMsg3]
  mov   [pCnLogMsg],eax
  call  CnLogIt
  ret

;------------------------------------------------------------------------------
; CnCrLf
;   Output:
;     Prints CRLF through VdPutStr.
; Notes:
;     Sets pVdStr to CrLf before calling VdPutStr.
;------------------------------------------------------------------------------
CnCrLf:
  lea   eax,[CrLf]
  mov   [pVdStr],eax
  call  VdPutStr
  ret

;------------------------------------------------------------------------------
; CnSpace
;   Output:
;     Prints one space through VdPutStr.
; Notes:
;     Sets pVdStr to Space1 before calling VdPutStr.
;------------------------------------------------------------------------------
CnSpace:
  lea   eax,[Space1]
  mov   [pVdStr],eax
  call  VdPutStr
  ret

;------------------------------------------------------------------------------
; CnReadLine
;   Input:
;     pCnCmdLine   = destination command-line Str buffer
;     CnCmdMaxLen  = maximum payload length
;     CnRlActive   = 1 if an input line is already being edited, 0 otherwise
;   Output:
;     pCnCmdLine target receives committed Str length and payload on Enter.
;     CnCmdLineLen = current edit length while editing.
;     CnOutHasLine = 1 when a full line was submitted this call, else 0.
;     CnRlActive   = 0 after Enter, 1 while editing.
; Notes:
;     Non-blocking line editor. Polls timer and keyboard once per call.
;     Uses KbGetKey output variables and VdIn* routines for visual editing.
;     Registers are scratch only across all calls.
;------------------------------------------------------------------------------
CnReadLine:
  mov   byte[CnOutHasLine],0            ; default: no completed line
  cmp   byte[CnRlActive],1              ; already editing a line?
  je    CnReadLinePoll
  mov   byte[CnRlActive],1              ; begin new line
  xor   ax,ax
  mov   [CnCmdLineLen],ax               ; reset input length
  call  VdInClearLine                   ; clear input row,InCurCol=1
CnReadLinePoll:
  call  TimerNowTicks                   ; keep accumulator updated
  call  KbGetKey                        ; poll keyboard once
  mov   al,[KbOutHasKey]
  test  al,al
  jz    CnReadLineDone                  ; no key -> return immediately
  mov   al,[KbOutType]
  cmp   al,KEY_CHAR
  je    CnReadLineOnChar
  cmp   al,KEY_BACKSPACE
  je    CnReadLineOnBackspace
  cmp   al,KEY_ENTER
  je    CnReadLineOnEnter
  jmp   CnReadLineDone
CnReadLineOnChar:
  mov   ax,[CnCmdLineLen]
  movzx ecx,ax
  mov   ax,[CnCmdMaxLen]
  movzx edx,ax
  cmp   ecx,edx
  jae   CnReadLineDone
  mov   esi,[pCnCmdLine]
  mov   al,[KbOutChar]
  mov   [esi+2+ecx],al
  inc   cx
  mov   [CnCmdLineLen],cx
  mov   [VdInCh],al                     ; visual char input
  call  VdInPutChar
  jmp   CnReadLineDone
CnReadLineOnBackspace:
  mov   ax,[CnCmdLineLen]
  movzx ecx,ax
  test  ecx,ecx
  jz    CnReadLineDone
  dec   cx
  mov   [CnCmdLineLen],cx
  call  VdInBackspaceVisual
  jmp   CnReadLineDone
CnReadLineOnEnter:
  mov   esi,[pCnCmdLine]
  mov   ax,[CnCmdLineLen]
  mov   [esi],ax                        ; commit Str length
  mov   byte[CnOutHasLine],1            ; signal: line ready
  mov   byte[CnRlActive],0              ; go idle (next call starts new line)
  call  VdInClearLine                   ; clear the input row after submit
CnReadLineDone:
  ret

;------------------------------------------------------------------------------
; CnLogIt
;   Input:
;     pCnLogMsg = Str pointer to message payload to print after timestamp
;   Output:
;     Writes "YYYY-MM-DD HH:MM:SS <message>" plus CRLF to the console.
;   Notes:
;     Uses TimeDtPrint, TimeTmPrint, VdPutStr, and CnCrLf.
;------------------------------------------------------------------------------
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
;   Input:
;     CnCmdLine = command line Str to match
;     CnCmdTable/CnCmdTableCount = command table and entry count
;   Output:
;     Calls matching command handler if found; otherwise returns.
;   Notes:
;     Uses CnTmpLen, pCnTmpInput, pCnTmpTable, and CnTmpCount as
;     memory-backed dispatch state.
;     Comparison is exact, case-insensitive, and length must match.
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
;------------------------------------------------------------------------------
; CnDoCmdDate
;   Output:
;     Prints current wall date plus CRLF.
;------------------------------------------------------------------------------
CnDoCmdDate:
  call  TimeDtPrint
  call  CnCrLf
  ret

;------------------------------------------------------------------------------
; CnDoCmdDelay
;   Output:
;     Prints start timestamp/message, waits about 2000ms, then prints end
;     timestamp/message.
;------------------------------------------------------------------------------
CnDoCmdDelay:
  call  TimeTmPrint
  call  CnSpace
  lea   eax,[CnDelayMsg1]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  mov   eax,2000
  mov   [TimerDelayMs],eax
  call  TimerSpinDelayMs
  call  TimeTmPrint
  call  CnSpace
  lea   eax,[CnDelayMsg2]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret

;------------------------------------------------------------------------------
; CnDoCmdHelp
;   Output:
;     Prints each command name in CnCmdTable, one per line.
;   Notes:
;     Uses pCnCmdTable and CnHelpCnt as memory-backed loop state.
;------------------------------------------------------------------------------
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

;------------------------------------------------------------------------------
; CnDoCmdShutdown
;   Output:
;     Logs shutdown messages, waits briefly, attempts soft power-off, then halts.
;------------------------------------------------------------------------------
CnDoCmdShutdown:
  lea   eax,[CnShutdown1]               ; Print 1st
  mov   [pCnLogMsg],eax                 ;  shutdown
  call  CnLogIt                         ;  message
  lea   eax,[CnShutdown2]               ; Print 2nd
  mov   [pCnLogMsg],eax                 ;  shutdown
  call  CnLogIt                         ;  message
  mov   eax,3000                        ; Leave final message visible briefly
  mov   [TimerDelayMs],eax
  call  TimerSpinDelayMs                ;  before optional power-off request
  mov   ax,0x2000                       ; Optional environment-specific
  mov   dx,0xB004                       ;  Bochs/ACPI soft-power-off request
  out   dx,ax                           ;  if supported by the runtime
  mov   dx,0x604                        ; Alternate ACPI-compatible port
  out   dx,ax                           ;  for environments that honor it
  cli                                   ; Canonical shutdown state on real
  hlt                                   ;  386-class hardware: stop forever
  ret                                   ; Never reached; does not return

;------------------------------------------------------------------------------
; CnDoCmdTime
;   Output:
;     Prints current wall time plus CRLF.
;------------------------------------------------------------------------------
CnDoCmdTime:
  call  TimeTmPrint
  call  CnCrLf
  ret
