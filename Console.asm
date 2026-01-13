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
;   CnPrint            ; EBX=String, prints + CrLf
;   CnBanner
;   CnBoot
;   CnLog              ; EBX=String, prints timestamp + space + String + CrLf
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
;**************************************************************************************************

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