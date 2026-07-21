;**************************************************************************************************
; Prog2.asm
;   Tiny flat user-program smoke test.
;**************************************************************************************************

[bits 32]
  org   00201000h

KERNEL_CALL_GATEWAY equ 00100005h
KC_TS_EXIT          equ 5
KC_BLOCK            equ 00201FE0h
KC_BLOCK_NUMBER     equ 0
KC_BLOCK_ARG0       equ 8

Start:
  xor   eax,eax
  mov   ecx,11
Prog2Sum:
  add   eax,ecx
  inc   ecx
  cmp   ecx,21
  jb    Prog2Sum
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_EXIT
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
Prog2Done:
  jmp   Prog2Done
