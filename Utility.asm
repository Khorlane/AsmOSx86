;**************************************************************************************************
; Utility.asm
;   Kernel utility routines (subsystem-agnostic helpers)
;
; Purpose
;   Provide small, reusable helper routines that:
;     - Are not tied to a specific hardware device
;     - Are not part of a single kernel subsystem
;     - Are safe to call from early boot and core kernel code
;
; Contains
;   - Data conversion helpers (e.g. CStr → LStr)
;   - Generic formatting or manipulation routines
;   - Pure helper logic with no side effects beyond documented outputs
;
; Does NOT contain
;   - Hardware access code
;   - Policy decisions or global configuration constants
;   - Subsystem-specific logic
;
; Notes (LOCKED-IN)
;   - All routines are ABI-compliant and preserve registers unless stated.
;   - Callers must supply valid pointers and buffers per each routine’s contract.
;**************************************************************************************************

[bits 32]
; ----- Utility variables -----
pStr1            dd 0                   ; Source string pointer
pStr2            dd 0                   ; Destination string pointer

;------------------------------------------------------------------------------
; StrCopy
; Copies a length-prefixed string from [pStr1] to [pStr2].
; pStr1 and pStr2 are global variables set before call.
;------------------------------------------------------------------------------
StrCopy:
  mov   esi,[pStr1]        ; Source pointer
  mov   edi,[pStr2]        ; Destination pointer
  mov   cx,[esi]           ; Get length prefix (u16)
  add   cx,2               ; Include length word
  rep   movsb
  ret