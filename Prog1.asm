;**************************************************************************************************
; Prog1.asm
;   Tiny flat user-program smoke test.
;**************************************************************************************************

[bits 32]
  org   00200000h

KERNEL_CALL_GATEWAY equ 00100005h
KC_TS_EXIT          equ 5
KC_BLOCK            equ 00200FE0h
KC_BLOCK_NUMBER     equ 0
KC_BLOCK_ARG0       equ 8

Start:
  xor   eax,eax
  mov   ecx,1
Prog1Sum:
  add   eax,ecx
  inc   ecx
  cmp   ecx,11
  jb    Prog1Sum
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_EXIT
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
Prog1Done:
  jmp   Prog1Done
