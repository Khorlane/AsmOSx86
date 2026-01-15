;**************************************************************************************************
; Console.asm
;   Console output (Session 0 / physical terminal)
;
;   Console is NOT a login session.
;   It is the machine console used for boot/status/debug output and
;   operator-only commands (later).
;
; Console Contract (Session 0 / physical terminal)
;
; Exported:
;   CnInit
;   CnCrLf
;   CnPrint            ; EBX=String to EBX=LStr
;   CnBanner
;   CnBoot
;   CnLog              ; EBX=String to EBX=LStr
;   CnReadLine         ; EBX=CStr destination buffer, ECX=max length
;
; Requires:
;   PutStr             ; EBX=String (Video.asm)
;   CrLf               ; String in Kernel.asm
;   CnStartMsg1        ; String in Kernel.asm
;   CnStartMsg2        ; String in Kernel.asm
;   TimeNow            ; advance wall time using monotonic ticks (Time.asm)
;   TimeFmtYmdHms      ; formats current date/time as "YYYY-MM-DD HH:MM:SS" (Time.asm)
;   LogStampStr        ; timestamp string buffer (Kernel.asm)
;   LogSepStr          ; separator string (Kernel.asm)
;
; Notes (LOCKED-IN):
;   - Console prints strings only.
;   - Console messages always end with CrLf.
;   - All Cn* routines take LStr
;   - Owns “row 25 is command line”
;   - All console printing preserves/repaints row 25 after output
;**************************************************************************************************

section .data
String  CnStartMsg1,"AsmOSx86 Console (Session 0)"
String  CnStartMsg2,"AsmOSx86 - A Hobbyist Operating System in x86 Assembly"
String  CnStartMsg3,"AsmOSx86 Initialization started"
String  LogStampStr,"YYYY-MM-DD HH:MM:SS"
String  LogSepStr," "
String  PromptStr,">"," "
String  TypedPrefixStr,"You typed: "
String  CmdLineClearStr,"                                                                                "
String  CnBsSeqStr,08h,020h,08h         ; BS, space, BS

align 4
; Line input LStr buffer
LineLStr:  dw 0
          times LSTR_MAX db 0
CnMainRow    db 1                        ; main output cursor row (1..24)
CnMainCol    db 1                        ; main output cursor col (1..80)
CnCmdRow     db 0                        ; saved command-line cursor row
CnCmdCol     db 0                        ; saved command-line cursor col

section .text
;------------------------------------------------------------------------------------------------
; Command Line-input Console Loop
;------------------------------------------------------------------------------------------------
ConsoleLoop:
  ; Fixed command line always lives on last row
  mov   al,25
  mov   [Row],al
  mov   al,1
  mov   [Col],al
  mov   ebx,CmdLineClearStr             ; blank out bottom row
  call  PutStrRaw
  mov   al,25                           ; restore cursor to start of cmd line
  mov   [Row],al
  mov   al,1
  mov   [Col],al
  ; Show prompt (LStr)
  mov   ebx,PromptStr                   ; EBX = LStr "> "
  call  PutStrRaw                       ; print prompt
  mov   ebx,LineLStr
  mov   ecx,LSTR_MAX
  call  CnReadLine
  ; Switch to main output area before printing
  mov   al,24
  mov   [Row],al
  mov   al,1
  mov   [Col],al
  call  MoveCursor
  ; Echo: "You typed: " + line + CRLF
  mov   ebx,TypedPrefixStr
  call  PutStr
  mov   ebx,LineLStr
  call  PutStr
  mov   ebx,CrLf
  call  PutStr
  jmp   ConsoleLoop

;--------------------------------------------------------------------------------------------------
; CnInit - initialize console state (colors, start row/col, etc.)
;--------------------------------------------------------------------------------------------------
CnInit:
  pusha                                 ; Save registers
  mov   ebx,CnStartMsg1                 ; Print console session banner
  call  CnLog                           ;  string (+ CrLf)
  mov   ebx,CnStartMsg2                 ; Print Announcement message
  call  CnLog                           ;  message (+ CrLf)
  mov   ebx,CnStartMsg3                 ; Print Initialization message
  call  CnLog                           ;  message (+ CrLf)
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; CnCrLf - print CrLf
;--------------------------------------------------------------------------------------------------
CnCrLf:
  pusha                                 ; Save registers
  mov   ebx,CrLf                        ; Put
  call  PutStr                          ;  CrLf
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; CnPrint - Print a console message (string) followed by CrLf
;   EBX = Address of String to print
;--------------------------------------------------------------------------------------------------
CnPrint:
  pusha                                 ; Save registers
  call  PutStr                          ; Print the string
  call  CnCrLf                          ;  followed by CrLf
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; CnLog - Print timestamp + space + message + CrLf
;   EBX = Address of message String
;--------------------------------------------------------------------------------------------------
CnLog:
  pusha                                 ; Save registers
  push  ebx                             ; Save message ptr
  call  TimeNow                         ; Update wall time from baseline + monotonic ticks
  mov   ebx,LogStampStr                 ; Format target
  call  TimeFmtYmdHms                   ; Fill "YYYY-MM-DD HH:MM:SS"
  mov   ebx,LogStampStr                 ; Put timestamp
  call  PutStr                          ;  (no CrLf yet)
  mov   ebx,LogSepStr                   ; Put space
  call  PutStr                          ;  (no CrLf yet)
  pop   ebx                             ; Restore message ptr
  call  PutStr                          ; Put message
  call  CnCrLf                          ; End line
  popa                                  ; Restore registers
  ret

;--------------------------------------------------------------------------------------------------
; CnCmdSave - save current cursor position for restoring fixed command line
;--------------------------------------------------------------------------------------------------
CnCmdSave:
  pusha
  mov   al,[Row]
  mov   [CnCmdRow],al
  mov   al,[Col]
  mov   [CnCmdCol],al
  popa
  ret

;--------------------------------------------------------------------------------------------------
; CnCmdRestore - restore cursor position for fixed command line
;--------------------------------------------------------------------------------------------------
CnCmdRestore:
  pusha
  mov   al,[CnCmdRow]
  mov   [Row],al
  mov   al,[CnCmdCol]
  mov   [Col],al
  call  MoveCursor
  popa
  ret

;--------------------------------------------------------------------------------------------------
; CnReadLine
;   Purpose:
;     Read a full line of console input from the fixed bottom command line.
;
;   Behavior:
;     - Blocks waiting for keyboard input
;     - Echoes characters on row 25 only
;     - Supports Backspace and Enter
;     - Produces a NUL-terminated CStr
;
;   Input:
;     EBX = destination buffer (CStr)
;     ECX = maximum characters (excluding NUL)
;
;   Output:
;     Buffer filled with ASCII chars
;     Buffer terminated with NUL (0)
;
;   Notes:
;     - Cursor never leaves row 25
;     - Caller decides how to convert to LStr
;     - Preserves all registers (ABI)
;--------------------------------------------------------------------------------------------------
CnReadLine:
  pusha
  lea   edx,[ebx+2]                     ; EDX = payload start (skip LStr length word)
  xor   edi,edi                         ; EDI = current length / index
  mov   word [ebx],2                    ; empty LStr length = 2 bytes (length word only)
  mov   byte [edx],0                    ; payload[0] = NUL (keeps PutStr safe if length ever gets stale)
CnReadLine_Loop:
  call  KbWaitChar                      ; AL = ASCII (non-zero)
  cmp   al,0Dh                          ; Enter?
  je    CnReadLine_Done
  cmp   al,08h                          ; Backspace?
  je    CnReadLine_Backspace
  ; Printable character
  cmp   edi,ecx                         ; reached max length?
  jae   CnReadLine_Loop                 ; ignore if full
  mov   [edx+edi],al                    ; store character
  inc   edi
  ; echo char on command line using raw LStr writer
  push  ebx
  mov   [KbEchoBuf+2],al                ; reuse the 1-char LStr if it’s globally accessible
  mov   ebx,KbEchoBuf
  call  PutStrRaw
  pop   ebx
  jmp   CnReadLine_Loop
CnReadLine_Backspace:
  test  edi,edi                         ; nothing to delete?
  jz    CnReadLine_Loop
  dec   edi                             ; remove one char from buffer length
  push  ebx                             ; <-- preserve destination LStr pointer
  mov   ebx,CnBsSeqStr
  call  PutStrRaw                       ; erase last char visually on row 25
  pop   ebx                             ; <-- restore destination LStr pointer
  jmp   CnReadLine_Loop
CnReadLine_Done:
  mov   ax,di                           ; AX = length typed
  add   ax,2                            ; LStr total size includes the length word
  mov   [ebx],ax                        ; store LStr length
  mov   byte [edx+edi],0                ; optional NUL terminator for convenience
  popa
  ret