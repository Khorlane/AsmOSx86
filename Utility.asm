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
;   - Data conversion helpers (e.g. CStr → Str)
;   - Generic formatting or manipulation routines
;   - Pure helper logic with no side effects beyond documented outputs
;
; Does NOT contain
;   - Hardware access code
;   - Policy decisions or global configuration constants
;   - Subsystem-specific logic
;
; Notes (LOCKED-IN)
;   - All routines use memory-contract inputs/outputs unless stated.
;   - Registers are scratch only; callers must not expect preservation.
;   - Callers must supply valid pointers and buffers per each routine’s contract.
;**************************************************************************************************

[bits 32]
; ----- Utility variables -----
align 4
pStr1            dd 0                   ; Source string pointer
pStr2            dd 0                   ; Destination string pointer
pPut2DecDst      dd 0                   ; input/output: destination payload pointer
Put2DecVal       db 0                   ; input: value 0..99
Put2DecPad0      db 0,0,0               ; alignment padding

;------------------------------------------------------------------------------
; Put2Dec
;   Input:
;     Put2DecVal  = value 0..99
;     pPut2DecDst = destination payload pointer
;   Output:
;     [pPut2DecDst original]   = tens ASCII digit
;     [pPut2DecDst original+1] = ones ASCII digit
;     pPut2DecDst += 2
;   Clobbers:
;     AL, AH, BL, EDI
;------------------------------------------------------------------------------
Put2Dec:
  mov   edi,[pPut2DecDst]
  mov   al,[Put2DecVal]
  xor   ah,ah
  mov   bl,10
  div   bl                              ; AL=tens,AH=ones
  add   al,'0'
  mov   [edi],al
  mov   al,ah
  add   al,'0'
  mov   [edi+1],al
  add   edi,2
  mov   [pPut2DecDst],edi
  ret

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

;------------------------------------------------------------------------------
; StrTrim
; Input:
;   pStr1 -> Str
; Output:
;   Leading + trailing spaces removed
;------------------------------------------------------------------------------
StrTrim:
  call  StrTrimLead
  call  StrTrimTrail
  ret

;------------------------------------------------------------------------------
; StrTrimLead
; Input:
;   pStr1 -> Str [u16 len][bytes...]
; Output:
;   Leading spaces removed in-place (payload compacted, len updated)
; Clobbers: EAX,ECX,ESI,EDI
;------------------------------------------------------------------------------
StrTrimLead:
  mov   edi,[pStr1]                     ; EDI = Str
  movzx ecx,word[edi]                  ; ECX = len
  test  ecx,ecx
  jz    StrTrimLeadDone

  lea   esi,[edi+2]                    ; ESI = payload
  xor   eax,eax                        ; EAX = skip count
StrTrimLeadScan:
  test  ecx,ecx
  jz    StrTrimLeadAllSpaces
  cmp   byte[esi],' '
  jne   StrTrimLeadMove
  inc   esi
  inc   eax
  dec   ecx
  jmp   StrTrimLeadScan
StrTrimLeadAllSpaces:
  mov   word[edi],0
  ret
StrTrimLeadMove:
  test  eax,eax
  jz    StrTrimLeadDone                ; no leading spaces
  movzx ecx,word[edi]                  ; ECX = old len
  sub   ecx,eax                        ; new len
  mov   [edi],cx
  lea   edi,[edi+2]                    ; dst = payload start
  ; ESI already at first non-space (src)
  rep   movsb
StrTrimLeadDone:
  ret
;------------------------------------------------------------------------------
; StrTrimTrail
; Input:
;   pStr1 -> Str
; Output:
;   Trailing spaces removed by reducing len
; Clobbers: ECX,ESI,EDI
;------------------------------------------------------------------------------
StrTrimTrail:
  mov   edi,[pStr1]                     ; EDI = Str
  movzx ecx,word[edi]                  ; ECX = len
  test  ecx,ecx
  jz    StrTrimTrailDone
  lea   esi,[edi+2]
  lea   esi,[esi+ecx-1]                ; last char
StrTrimTrail1:
  test  ecx,ecx
  jz    StrTrimTrailAllSpaces
  cmp   byte[esi],' '
  jne   StrTrimTrailStore
  dec   esi
  dec   ecx
  jmp   StrTrimTrail1
StrTrimTrailAllSpaces:
  xor   ecx,ecx
StrTrimTrailStore:
  mov   [edi],cx
StrTrimTrailDone:
  ret
