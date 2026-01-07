;**********************************************************
; Console.asm
;   Console output (Session 0 / physical terminal)
;
;   Console is NOT a login session.
;   It is the machine console used for boot/status/debug output and
;   operator-only commands (later).
;
;   Policy:
;     - Console writes strings ONLY (PutStr).
;     - Mode 0 newline: CR and LF are separate controls with their
;       traditional meanings (handled inside PutStr).
;**********************************************************

;--------------------------------------------------------------------------------------------------
; ConsoleInit - initialize console state (colors, start row/col, etc.)
;--------------------------------------------------------------------------------------------------
CnInit:
  pusha                                 ; Save registers
  ; NOTE: Kernel currently sets Row/Col and colors before entering loop.
  ;       This routine exists so Console can own that setup later.
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; CnMsg - Print a console message (string)
;   EBX = Address of String to print
;--------------------------------------------------------------------------------------------------
CnMsg:
  pusha                                 ; Save registers
  call  PutStr                          ; Print the string
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; CnBanner - Print console banner (string) + CrLf
;--------------------------------------------------------------------------------------------------
CnBanner:
  pusha                                 ; Save registers
  mov   ebx,CnBannerStr                 ; Put banner
  call  PutStr                          ;  string
  mov   ebx,CrLf                        ; Put
  call  PutStr                          ;  CrLf
  popa                                  ; Restore registers
  ret                                   ; Return to caller