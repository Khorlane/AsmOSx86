;**************************************************************************************************
; Prog1.asm
;   Tiny flat user-program smoke test.
;**************************************************************************************************

[bits 32]
  org   00200000h

KERNEL_CALL_GATEWAY equ 00100005h
KC_TS_YIELD         equ 3
KC_TS_EXIT          equ 5
KC_BLOCK            equ 00200FE0h
KC_BLOCK_NUMBER     equ 0
KC_BLOCK_ARG0       equ 8

Start:
  mov   dword[Prog1SumValue],0
  mov   dword[Prog1NextValue],1
  mov   dword[Prog1YieldCount],0
Prog1Loop:
  mov   eax,[Prog1SumValue]
  add   eax,[Prog1NextValue]
  mov   [Prog1SumValue],eax
  mov   eax,[Prog1YieldCount]
  inc   eax
  mov   [Prog1YieldCount],eax
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_YIELD
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
  mov   eax,[Prog1NextValue]
  inc   eax
  mov   [Prog1NextValue],eax
  cmp   eax,11
  jb    Prog1Loop
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_EXIT
  mov   eax,[Prog1YieldCount]
  shl   eax,16
  or    eax,[Prog1SumValue]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
Prog1Done:
  jmp   Prog1Done

align 4
Prog1SumValue        dd 0
Prog1NextValue       dd 0
Prog1YieldCount      dd 0
