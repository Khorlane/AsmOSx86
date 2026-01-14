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

section .data
String  Buffer,"XXXXXXXX"
HexDigits   db  "0123456789ABCDEF"      ; Hex digits for conversion

section .text
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
;     LSTR_MAX equ <value>              ; maximum payload length in bytes (excludes the 2-byte length)
;--------------------------------------------------------------------------------------------------
CStrToLStr:
  pusha
  mov   ecx,LSTR_MAX                    ; enforce standard LStr maximum payload length locally
  xor   ebx,ebx                         ; EBX = count copied so far (final length)
CStrToLStr1:
  cmp   ebx,ecx                         ; reached maximum payload length?
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

;-----------------------------------------
; Floppy motor test (temporary)
;-----------------------------------------
FloppyTest:
  call  FloppyInit                      ; controller enabled, drive A:, motors off
  call  FloppyMotorOn                   ; motor on + internal spin-up wait
  ; keep it on ~1 second (1000 x ~1ms)
  mov   ecx,1000
FloppyTest1:
  call  FlpDelay1ms                     ; helper in Floppy.asm
  loop  FloppyTest1
  call  FloppyMotorOff                  ; motor off
  ret

;--------------------------------------------------------------------------------------------------
; DebugIt — Dumps EAX as hex (unchanged, retained)
;--------------------------------------------------------------------------------------------------
DebugIt:
  call  HexDump                         ; Convert BYTE4 to hex string in Buffer
  mov   ebx,Buffer                      ; Print 
  call  PutStr                          ;  the
  mov   ebx,CrLf                        ;  hex
  call  PutStr                          ;  string
  ret

;--------------------------------------------------------------------------------------------------
; HexDump - Convert BYTE4 to hex string in Buffer
;--------------------------------------------------------------------------------------------------
HexDump:
  mov   eax,[Byte4]                     ; Load the value to be converted
  mov   ecx,8                           ; We want 8 hex digits
  mov   ebx,Buffer+2                    ; Skip string length, point to first byte of string
HexDump1:
  mov   edx,eax                         ; Copy eax to edx
  shr   edx,28                          ; Shift top nibble into lowest 4 bits
  and   edx,0Fh                         ; Mask to isolate nibble
  mov   dl,[HexDigits+edx]              ; Look up ASCII character
  mov   [ebx],dl                        ; Store in Buffer
  inc   ebx                             ; Point to next character
  shl   eax,4                           ; Shift next nibble into position
  loop  HexDump1
  ret