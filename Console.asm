; Console.asm (Cn) - no sections, no globals

CnInit:
  mov   word [CnInWorkLen],0                ; Clear input length
  ret

CnCrLf:
  mov   byte [VdInCh],0x0D                  ; Carriage return
  call  VdPutChar
  mov   byte [VdInCh],0x0A                  ; Line feed
  call  VdPutChar
  ret

CnReadLine:
  mov   word [CnInWorkLen],0                ; Reset input length
  call  VdInClearLine

CnReadLineLoop:
  call  KbGetKey
  mov   al,[KbOutHasKey]
  test  al,al
  jz    CnReadLineLoop
  mov   al,[KbOutType]
  cmp   al,KEY_CHAR
  je    CnReadLineOnChar
  cmp   al,KEY_BACKSPACE
  je    CnReadLineOnBackspace
  cmp   al,KEY_ENTER
  je    CnReadLineOnEnter
  jmp   CnReadLineLoop

CnReadLineOnChar:
  movzx ecx,word [CnInWorkLen]
  movzx edx,word [CnInMax]
  cmp   ecx,edx
  jae   CnReadLineLoop
  mov   esi,[CnInDstPtr]
  mov   al,[KbOutChar]
  mov   [esi+2+ecx],al
  inc   cx
  mov   [CnInWorkLen],cx
  mov   [VdInCh],al
  call  VdInPutChar
  jmp   CnReadLineLoop

CnReadLineOnBackspace:
  movzx ecx,word [CnInWorkLen]
  test  ecx,ecx
  jz    CnReadLineLoop
  dec   cx
  mov   [CnInWorkLen],cx
  call  VdInBackspaceVisual
  jmp   CnReadLineLoop

CnReadLineOnEnter:
  mov   esi,[CnInDstPtr]
  mov   ax,[CnInWorkLen]
  mov   [esi],ax
  call  VdInClearLine
  ret

; ----- Storage (explicit zeros; no .bss) -----

CnInDstPtr       dd 0
CnInMax          dw 0
CnPad0           dw 0
CnInWorkLen      dw 0
CnPad1           dw 0