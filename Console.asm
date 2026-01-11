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
;
; Requires:
;   PutStr             ; EBX=String (Video.asm)
;   CrLf               ; String in Kernel.asm
;   CnBannerStr        ; String in Kernel.asm
;   CnBootMsg          ; String in Kernel.asm
;
; Notes (LOCKED-IN):
;   - Console prints strings only.
;   - Console messages always end with CrLf.
;**************************************************************************************************

;--------------------------------------------------------------------------------------------------
; CnInit - initialize console state (colors, start row/col, etc.)
;--------------------------------------------------------------------------------------------------
CnInit:
  pusha                                 ; Save registers
  ; NOTE: Kernel currently sets Row/Col and colors before entering loop.
  ;       This routine exists so Console can own that setup later.
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
; CnBanner - Print console banner (string) + CrLf
;--------------------------------------------------------------------------------------------------
CnBanner:
  pusha                                 ; Save registers
  mov   ebx,CnBannerStr                 ; Put banner
  call  CnPrint                         ;  string (+ CrLf)
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; CnBoot - Print boot-time console output
;--------------------------------------------------------------------------------------------------
CnBoot:
  pusha                                 ; Save registers
  call  CnBanner                        ; Print banner (+ CrLf)
  mov   ebx,CnBootMsg                   ; Put boot
  call  CnPrint                         ;  message (+ CrLf)
  popa                                  ; Restore registers
  ret                                   ; Return to caller