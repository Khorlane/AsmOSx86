;**************************************************************************************************
; Console.asm
;   Kernel/operator console for AsmOSx86.
;
; Purpose
;   Provide the current operator interface, command processor, line input/editing,
;   and console output integration with keyboard, video, and kernel services.
;
; Contains
;   - Console initialization and startup messages
;   - Command line input and editing
;   - Command lookup and dispatch
;   - Operator commands for date/time/uptime, delay, shutdown, and tests
;   - Current launch path for file-loaded user-program tests
;
; Notes
;   - Console.asm is the kernel/operator interface, not the future userland shell.
;   - CnInit is called during kernel startup.
;   - Console is called by the kernel main loop.
;   - CnCrLf is also used by other modules for kernel text output.
;**************************************************************************************************

[bits 32]

; ----- Console constants -----
CN_CMD_MAX_LEN   equ 79                 ; maximum console input length
; ----- Console variables -----
align 4
CnHelpCnt        dd 0                  ; Number of help entries 
CnTmpCount       dd 0                  ; temp: table entry count
CnFsTestHandle   dd 0                  ; temp: FsTest file handle
pCnCmdLine       dd 0                  ; Pointer to command line buffer
pCnCmdArg        dd 0                  ; Pointer to command argument payload
pCnCmdTable      dd 0                  ; Pointer to command table
pCnLogMsg        dd 0                  ; Pointer to log message
pCnRunInput      dd 0                  ; Pointer to Run argument scanner
pCnRunFileDst    dd 0                  ; Pointer to Run file destination
pCnRunArgDst     dd 0                  ; Pointer to Run argument destination
pCnTmpInput      dd 0                  ; Pointer to temp: input payload
pCnTmpTable      dd 0                  ; Pointer to temp: command table
CnRunCount       dd 0                  ; Run program count
CnRunParseOk     dd 0                  ; 1 when Run parse succeeds
CnRunFailTask    dd 0                  ; Run load failure task index
CnCmdLineLen     dw 0                  ; Command line length
CnCmdMaxLen      dw 0                  ; Command line max length
CnCmdArgLen      dw 0                  ; Command argument length
CnRunInputLeft   dw 0                  ; Run argument scanner bytes left
CnRunFileLen     dw 0                  ; Run filename length
CnRunArgLen      dw 0                  ; Run argument length
CnTmpLen         dw 0                  ; temp: input length (u16)
CnRlActive       db 0                  ; 1=in-progress line edit,0=idle
CnOutHasLine     db 0                  ; 1=completed line ready in CnCmdLine
CnPad2           db 0,0                ; pad to keep alignment friendly

; Command line buffer as String:
CnCmdLine: times (2 + CN_CMD_MAX_LEN) db 0
CnRunFile1: times (2 + CN_CMD_MAX_LEN) db 0
CnRunFile2: times (2 + CN_CMD_MAX_LEN) db 0
CnRunFile3: times (2 + CN_CMD_MAX_LEN) db 0
CnRunArg1: times (2 + CN_CMD_MAX_LEN) db 0
CnRunArg2: times (2 + CN_CMD_MAX_LEN) db 0
CnRunArg3: times (2 + CN_CMD_MAX_LEN) db 0
CnFsTestBuffer:
  times 32 db 0

; Strings
String  CnStartMsg1,"AsmOSx86 - A Hobbyist Operating System in x86 Assembly"
String  CnStartMsg2,"Console (Session 0)"
String  CnStartMsg3,"Initialization started"
String  CnShutdown1,"AsmOSx86 shutting down system..."
String  CnShutdown2,"System halted. It is now safe to power off."
String  CnDelayMsg1,"Delay test start (2000ms 2 seconds)"
String  CnDelayMsg2,"Delay test end"
String  CnFsTestFile,"KERNEL.BIN"
String  CnFsTestOpenStatus,"FsTest: open status 0000"
String  CnFsTestOpenHandle,"FsTest: open handle 0000"
String  CnFsTestReadStatus,"FsTest: read status 0000"
String  CnFsTestReadBytes,"FsTest: read bytes 0000"
String  CnFsTestCloseStatus,"FsTest: close status 0000"
String  CnKcTestMsg1,"KcTest: KcVdWriteStr dispatch OK"
String  CnKcTestMsg2,"KcTest: KcTmGetUptime dispatch result:"
String  CnRunMsg1,"Run: loading programs"
String  CnRunMsg2,"Run: running programs"
String  CnRunMsg3,"Run: complete"
String  CnRunExit,"Run: task exit 0000"
String  CnRunUsage,"Run usage: run <program> [-- <arg>] [| <program> [-- <arg>]]"
String  CnRunFail,"Run: load failed task 0 status 0000"

; ----- Console commands -----
String  CnCmdClear,    "Clear"
String  CnCmdDate,     "Date"
String  CnCmdDelay,    "Delay"
String  CnCmdFsTest,   "FsTest"
String  CnCmdHelp,     "Help"
String  CnCmdKcTest,   "KcTest"
String  CnCmdRun,      "Run"
String  CnCmdShutdown, "Shutdown"
String  CnCmdTime,     "Time"
String  CnCmdUptime,   "Uptime"

; Console Command Table and Handlers
align 4
CnCmdTable:
  dd CnCmdClear,    CnDoCmdClear
  dd CnCmdDate,     CnDoCmdDate
  dd CnCmdDelay,    CnDoCmdDelay
  dd CnCmdFsTest,   CnDoCmdFsTest
  dd CnCmdHelp,     CnDoCmdHelp
  dd CnCmdKcTest,   CnDoCmdKcTest
  dd CnCmdRun,      CnDoCmdRun
  dd CnCmdShutdown, CnDoCmdShutdown
  dd CnCmdTime,     CnDoCmdTime
  dd CnCmdUptime,   CnDoCmdUptime
CnCmdTableEnd:
CnCmdTableCount equ (CnCmdTableEnd-CnCmdTable)/8

;------------------------------------------------------------------------------
; External Routines
;------------------------------------------------------------------------------

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
; Internal Routines
;------------------------------------------------------------------------------

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
;     pCnCmdArg/CnCmdArgLen describe text after the first command token.
;   Notes:
;     Uses CnTmpLen, pCnTmpInput, pCnTmpTable, and CnTmpCount as
;     memory-backed dispatch state.
;     Comparison is case-insensitive and matches only the first command token.
;------------------------------------------------------------------------------
CnCmdDispatch:
  lea   eax,[CnCmdLine]                 ; EAX = input Str
  mov   bx,[eax]                        ; BX  = input length
  mov   [CnTmpLen],bx                   ; save len (u16)
  lea   eax,[eax+2]                     ; EAX = input payload
  mov   [pCnTmpInput],eax               ; save input payload ptr
  mov   dword[pCnCmdArg],0
  mov   word[CnCmdArgLen],0
  call  CnCmdSplitArg
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
; CnCmdSplitArg
;   Input:
;     pCnTmpInput = command line payload.
;     CnTmpLen    = command line payload length.
;   Output:
;     CnTmpLen    = first token length.
;     pCnCmdArg   = argument payload after spaces, or 0.
;     CnCmdArgLen = argument payload length, or 0.
;------------------------------------------------------------------------------
CnCmdSplitArg:
  mov   esi,[pCnTmpInput]
  movzx ecx,word[CnTmpLen]
  xor   edx,edx
CnCmdSplitArgScan:
  test  ecx,ecx
  jz    CnCmdSplitArgDone
  cmp   byte[esi+edx],' '
  je    CnCmdSplitArgFound
  inc   edx
  dec   ecx
  jmp   CnCmdSplitArgScan
CnCmdSplitArgFound:
  mov   [CnTmpLen],dx
  mov   edi,esi
  add   edi,edx
CnCmdSplitArgSkip:
  test  ecx,ecx
  jz    CnCmdSplitArgNoArg
  cmp   byte[edi],' '
  jne   CnCmdSplitArgSave
  inc   edi
  dec   ecx
  jmp   CnCmdSplitArgSkip
CnCmdSplitArgSave:
  mov   [pCnCmdArg],edi
  mov   [CnCmdArgLen],cx
  ret
CnCmdSplitArgNoArg:
  mov   dword[pCnCmdArg],0
  mov   word[CnCmdArgLen],0
CnCmdSplitArgDone:
  ret

;------------------------------------------------------------------------------
; Command Handlers
; Each handler corresponds to a command in CnCmdTable.
; Handlers are internal command-table entries.
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; CnDoCmdClear
;   Output:
;     Clears the console screen and restores the input cursor to row 25.
;------------------------------------------------------------------------------
CnDoCmdClear:
  call  VdClear
  mov   ax,25
  mov   [VdCurRow],ax
  mov   ax,1
  mov   [VdCurCol],ax
  call  VdSetCursor
  ret

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

;------------------------------------------------------------------------------
; CnDoCmdUptime
;   Output:
;     Prints current uptime plus CRLF.
;------------------------------------------------------------------------------
CnDoCmdUptime:
  call  UptimePrint
  ret

;------------------------------------------------------------------------------
; CnDoCmdFsTest
;   Output:
;     Opens KERNEL.BIN through KcFsOpen, reads 32 bytes, closes it, and prints
;     simple status lines.
;------------------------------------------------------------------------------
CnDoCmdFsTest:
  mov   dword[CnFsTestHandle],0
  mov   dword[KcNumber],KcFsOpen
  lea   eax,[CnFsTestFile]
  mov   [KcArg0],eax
  call  KcDispatch
  mov   eax,[KcResult0]
  mov   [TaskPut4DecVal],eax
  lea   eax,[CnFsTestOpenStatus+22]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[CnFsTestOpenStatus]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  mov   eax,[KcResult1]
  mov   [CnFsTestHandle],eax
  mov   [TaskPut4DecVal],eax
  lea   eax,[CnFsTestOpenHandle+22]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[CnFsTestOpenHandle]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  mov   eax,[CnFsTestHandle]
  test  eax,eax
  jz    CnDoCmdFsTestDone
  mov   dword[KcNumber],KcFsRead
  mov   [KcArg0],eax
  lea   eax,[CnFsTestBuffer]
  mov   [KcArg1],eax
  mov   dword[KcArg2],32
  call  KcDispatch
  mov   eax,[KcResult0]
  mov   [TaskPut4DecVal],eax
  lea   eax,[CnFsTestReadStatus+22]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[CnFsTestReadStatus]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  mov   eax,[KcResult1]
  mov   [TaskPut4DecVal],eax
  lea   eax,[CnFsTestReadBytes+21]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[CnFsTestReadBytes]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  mov   dword[KcNumber],KcFsClose
  mov   eax,[CnFsTestHandle]
  mov   [KcArg0],eax
  call  KcDispatch
  mov   eax,[KcResult0]
  mov   [TaskPut4DecVal],eax
  lea   eax,[CnFsTestCloseStatus+23]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[CnFsTestCloseStatus]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
CnDoCmdFsTestDone:
  ret

;------------------------------------------------------------------------------
; CnDoCmdKcTest
;   Output:
;     Exercises the current Kernel Call dispatcher from the operator console.
;   Notes:
;     Tests KcVdWriteStr and KcTmGetUptime using memory-backed Kc fields.
;------------------------------------------------------------------------------
CnDoCmdKcTest:
  mov   dword[KcNumber],KcVdWriteStr
  lea   eax,[CnKcTestMsg1]
  mov   [KcArg0],eax
  call  KcDispatch
  call  CnCrLf
  mov   dword[KcNumber],KcVdWriteStr
  lea   eax,[CnKcTestMsg2]
  mov   [KcArg0],eax
  call  KcDispatch
  call  CnCrLf
  mov   dword[KcNumber],KcTmGetUptime
  call  KcDispatch
  mov   eax,[KcResult0]
  mov   [UptimeFmtSec],eax
  call  UptimeFmtYdhms
  mov   dword[KcNumber],KcVdWriteStr
  mov   eax,UptimeStr
  mov   [KcArg0],eax
  call  KcDispatch
  call  CnCrLf
  ret

;------------------------------------------------------------------------------
; CnDoCmdRun
;   Input:
;     pCnCmdArg/CnCmdArgLen = run launch specs from command line.
;   Output:
;     Loads 1..3 named user programs, then runs them cooperatively together.
;------------------------------------------------------------------------------
CnDoCmdRun:
  mov   ax,[CnCmdArgLen]
  test  ax,ax
  jz    CnDoCmdRunUsage
  call  CnRunParseSpecs
  mov   eax,[CnRunParseOk]
  test  eax,eax
  jz    CnDoCmdRunUsage
  lea   eax,[CnRunMsg1]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  call  TaskProgramInit
  mov   eax,[CnRunCount]
  mov   [TaskProgramRunCount],eax
  lea   eax,[CnRunFile1]
  mov   [KcArg0],eax
  mov   dword[KcArg1],1
  mov   dword[KcArg2],1
  lea   eax,[CnRunArg1]
  mov   [TaskProgramArgPtr],eax
  call  CnRunLoadTask
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   CnDoCmdRunFail
  mov   eax,[CnRunCount]
  cmp   eax,2
  jb    CnDoCmdRunStart
  lea   eax,[CnRunFile2]
  mov   [KcArg0],eax
  mov   dword[KcArg1],2
  mov   dword[KcArg2],2
  lea   eax,[CnRunArg2]
  mov   [TaskProgramArgPtr],eax
  call  CnRunLoadTask
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   CnDoCmdRunFail
  mov   eax,[CnRunCount]
  cmp   eax,3
  jb    CnDoCmdRunStart
  lea   eax,[CnRunFile3]
  mov   [KcArg0],eax
  mov   dword[KcArg1],3
  mov   dword[KcArg2],3
  lea   eax,[CnRunArg3]
  mov   [TaskProgramArgPtr],eax
  call  CnRunLoadTask
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   CnDoCmdRunFail
CnDoCmdRunStart:
  lea   eax,[CnRunMsg2]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  call  TaskProgramStartN
  call  CnCrLf
  mov   eax,[CnRunCount]
  cmp   eax,1
  jne   CnDoCmdRunPrintMany
  mov   dword[TaskProgramTaskIndex],1
  call  TaskProgramGetExitCode
  mov   eax,[TaskProgramExitCode]
  mov   [TaskPut4DecVal],eax
  lea   eax,[CnRunExit+17]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[CnRunExit]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  jmp   CnDoCmdRunComplete
CnDoCmdRunPrintMany:
  call  TaskProgramPrintExitCodesN
CnDoCmdRunComplete:
  lea   eax,[CnRunMsg3]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret
CnDoCmdRunUsage:
  lea   eax,[CnRunUsage]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret
CnDoCmdRunFail:
  mov   eax,[CnRunFailTask]
  add   al,'0'
  mov   [CnRunFail+24],al
  mov   eax,[KcResult0]
  mov   [TaskPut4DecVal],eax
  lea   eax,[CnRunFail+33]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[CnRunFail]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret

;------------------------------------------------------------------------------
; CnRunParseSpecs
;   Input:
;     pCnCmdArg/CnCmdArgLen = run command text after "run ".
;   Output:
;     CnRunCount = number of parsed launch specs.
;     CnRunFile1..3/CnRunArg1..3 = parsed filenames and optional arguments.
;     CnRunParseOk = 1 when the command matches the supported run grammar.
;------------------------------------------------------------------------------
CnRunParseSpecs:
  mov   dword[CnRunCount],0
  mov   dword[CnRunParseOk],0
  mov   word[CnRunFile1],0
  mov   word[CnRunFile2],0
  mov   word[CnRunFile3],0
  mov   word[CnRunArg1],0
  mov   word[CnRunArg2],0
  mov   word[CnRunArg3],0
  mov   eax,[pCnCmdArg]
  mov   [pCnRunInput],eax
  mov   ax,[CnCmdArgLen]
  mov   [CnRunInputLeft],ax
  call  CnRunSkipSpaces
  mov   ax,[CnRunInputLeft]
  test  ax,ax
  jz    CnRunParseSpecsDone
CnRunParseSpecsLoop:
  mov   eax,[CnRunCount]
  cmp   eax,3
  jae   CnRunParseSpecsDone
  call  CnRunSelectDsts
  call  CnRunCopyFile
  mov   ax,[CnRunFileLen]
  test  ax,ax
  jz    CnRunParseSpecsDone
  inc   dword[CnRunCount]
  call  CnRunSkipSpaces
  mov   ax,[CnRunInputLeft]
  test  ax,ax
  jz    CnRunParseSpecsOk
  mov   esi,[pCnRunInput]
  cmp   ax,2
  jb    CnRunParseSpecsPipe
  cmp   byte[esi],'-'
  jne   CnRunParseSpecsPipe
  cmp   byte[esi+1],'-'
  jne   CnRunParseSpecsPipe
  add   esi,2
  mov   [pCnRunInput],esi
  sub   ax,2
  mov   [CnRunInputLeft],ax
  call  CnRunSkipSpaces
  call  CnRunCopyArg
  call  CnRunSkipSpaces
  mov   ax,[CnRunInputLeft]
  test  ax,ax
  jz    CnRunParseSpecsOk
CnRunParseSpecsPipe:
  mov   esi,[pCnRunInput]
  cmp   byte[esi],'|'
  jne   CnRunParseSpecsDone
  inc   esi
  mov   [pCnRunInput],esi
  dec   word[CnRunInputLeft]
  call  CnRunSkipSpaces
  mov   ax,[CnRunInputLeft]
  test  ax,ax
  jz    CnRunParseSpecsDone
  jmp   CnRunParseSpecsLoop
CnRunParseSpecsOk:
  mov   dword[CnRunParseOk],1
CnRunParseSpecsDone:
  ret

;------------------------------------------------------------------------------
; CnRunSkipSpaces
;   Output:
;     Advances pCnRunInput/CnRunInputLeft past leading spaces.
;------------------------------------------------------------------------------
CnRunSkipSpaces:
  mov   ax,[CnRunInputLeft]
CnRunSkipSpaces1:
  test  ax,ax
  jz    CnRunSkipSpacesDone
  mov   esi,[pCnRunInput]
  cmp   byte[esi],' '
  jne   CnRunSkipSpacesDone
  inc   esi
  mov   [pCnRunInput],esi
  dec   ax
  jmp   CnRunSkipSpaces1
CnRunSkipSpacesDone:
  mov   [CnRunInputLeft],ax
  ret

;------------------------------------------------------------------------------
; CnRunSelectDsts
;   Output:
;     pCnRunFileDst/pCnRunArgDst point at the current launch-spec buffers.
;------------------------------------------------------------------------------
CnRunSelectDsts:
  mov   eax,[CnRunCount]
  cmp   eax,1
  je    CnRunSelectDsts2
  cmp   eax,2
  je    CnRunSelectDsts3
  lea   eax,[CnRunFile1]
  mov   [pCnRunFileDst],eax
  lea   eax,[CnRunArg1]
  mov   [pCnRunArgDst],eax
  ret
CnRunSelectDsts2:
  lea   eax,[CnRunFile2]
  mov   [pCnRunFileDst],eax
  lea   eax,[CnRunArg2]
  mov   [pCnRunArgDst],eax
  ret
CnRunSelectDsts3:
  lea   eax,[CnRunFile3]
  mov   [pCnRunFileDst],eax
  lea   eax,[CnRunArg3]
  mov   [pCnRunArgDst],eax
  ret

;------------------------------------------------------------------------------
; CnRunCopyFile
;   Output:
;     Current file destination receives one filename token.
;------------------------------------------------------------------------------
CnRunCopyFile:
  mov   word[CnRunFileLen],0
  mov   edi,[pCnRunFileDst]
  mov   word[edi],0
CnRunCopyFile1:
  mov   ax,[CnRunInputLeft]
  test  ax,ax
  jz    CnRunCopyFileDone
  mov   esi,[pCnRunInput]
  cmp   byte[esi],' '
  je    CnRunCopyFileDone
  cmp   byte[esi],'|'
  je    CnRunCopyFileDone
  movzx ebx,word[CnRunFileLen]
  cmp   ebx,CN_CMD_MAX_LEN
  jae   CnRunCopyFileAdvance
  mov   edi,[pCnRunFileDst]
  mov   al,[esi]
  mov   [edi+ebx+2],al
  inc   word[CnRunFileLen]
CnRunCopyFileAdvance:
  inc   esi
  mov   [pCnRunInput],esi
  dec   word[CnRunInputLeft]
  jmp   CnRunCopyFile1
CnRunCopyFileDone:
  mov   edi,[pCnRunFileDst]
  mov   ax,[CnRunFileLen]
  mov   [edi],ax
  ret

;------------------------------------------------------------------------------
; CnRunCopyArg
;   Output:
;     Current argument destination receives text through the next pipe or end.
;------------------------------------------------------------------------------
CnRunCopyArg:
  mov   word[CnRunArgLen],0
  mov   edi,[pCnRunArgDst]
  mov   word[edi],0
CnRunCopyArg1:
  mov   ax,[CnRunInputLeft]
  test  ax,ax
  jz    CnRunCopyArgTrim
  mov   esi,[pCnRunInput]
  cmp   byte[esi],'|'
  je    CnRunCopyArgTrim
  movzx ebx,word[CnRunArgLen]
  cmp   ebx,CN_CMD_MAX_LEN
  jae   CnRunCopyArgAdvance
  mov   edi,[pCnRunArgDst]
  mov   al,[esi]
  mov   [edi+ebx+2],al
  inc   word[CnRunArgLen]
CnRunCopyArgAdvance:
  inc   esi
  mov   [pCnRunInput],esi
  dec   word[CnRunInputLeft]
  jmp   CnRunCopyArg1
CnRunCopyArgTrim:
  movzx ebx,word[CnRunArgLen]
  test  ebx,ebx
  jz    CnRunCopyArgDone
  mov   edi,[pCnRunArgDst]
  cmp   byte[edi+ebx+1],' '
  jne   CnRunCopyArgDone
  dec   word[CnRunArgLen]
  jmp   CnRunCopyArgTrim
CnRunCopyArgDone:
  mov   edi,[pCnRunArgDst]
  mov   ax,[CnRunArgLen]
  mov   [edi],ax
  ret

;------------------------------------------------------------------------------
; CnRunLoadTask
;   Input:
;     KcArg0 = program filename Str.
;     KcArg1 = task table index.
;     KcArg2 = stack slot index.
;     TaskProgramArgPtr = task startup argument Str.
;   Output:
;     KcStatus/KcResult0 from KcTsLoadProgram.
;------------------------------------------------------------------------------
CnRunLoadTask:
  mov   eax,[KcArg1]
  mov   [CnRunFailTask],eax
  mov   [TaskProgramTaskIndex],eax
  mov   dword[KcNumber],KcTsLoadProgram
  call  KcDispatch
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   CnRunLoadTaskDone
  call  TaskProgramSetArg
CnRunLoadTaskDone:
  ret
