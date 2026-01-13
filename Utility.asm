;--------------------------------------------------------------------------------------------------
; CStrToLStr
;   Purpose:
;     Convert a C-style NUL-terminated string (CStr) into an OS length-prefixed string (LStr).
;   LStr layout:
;     [EDI+0]  dw Length
;     [EDI+2]  db Payload[...]          ; not NUL-terminated
;   Input:
;     ESI = pointer to CStr (NUL-terminated)
;     EDI = pointer to destination LStr
;   Output:
;     Copies up to LSTR_CAP bytes into payload
;     Writes length word to [EDI]
;   Policy:
;     - No padding/space-fill; consumers trust the length.
;     - Truncates at LSTR_CAP.
;     - Preserves all GPRs (ABI-compliant).
;   Requires:
;     LSTR_MAX equ <value>              ; payload capacity in bytes (excludes the 2-byte length)
;--------------------------------------------------------------------------------------------------
CStrToLStr:
  pusha
  mov   ecx,LSTR_MAX                    ; enforce standard LStr payload capacity locally
  xor   ebx,ebx                         ; EBX = count copied so far (final length)
CStrToLStr1:
  cmp   ebx,ecx                         ; reached payload capacity?
  jae   CStrToLStr2                     ; yes -> stop (truncate)
  mov   al,[esi]                        ; read next source byte
  test  al,al                           ; NUL terminator ends the CStr
  jz    CStrToLStr2
  mov   [edi+2+ebx],al                  ; write into LStr payload
  inc   esi                             ; advance source pointer
  inc   ebx                             ; advance payload length
  jmp   CStrToLStr1
CStrToLStr2:
  add   bx,2                            ; adjust BX to total LStr size (length prefix + payload)
  mov   [edi],bx                        ; store LStr length prefix
  popa
  ret