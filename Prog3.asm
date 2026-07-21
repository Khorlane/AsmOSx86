;**************************************************************************************************
; Prog3.asm
;   Tiny flat user-program smoke test.
;**************************************************************************************************

[bits 32]
  org   00202000h

KERNEL_CALL_GATEWAY equ 00100005h
KC_TS_YIELD         equ 3
KC_TS_EXIT          equ 5
KC_BLOCK            equ 00202FE0h
KC_BLOCK_NUMBER     equ 0
KC_BLOCK_ARG0       equ 8

Start:
  mov   dword[Prog3SumValue],0
  mov   dword[Prog3NextValue],21
Prog3Loop:
  mov   eax,[Prog3SumValue]
  add   eax,[Prog3NextValue]
  mov   [Prog3SumValue],eax
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_YIELD
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
  mov   eax,[Prog3NextValue]
  inc   eax
  mov   [Prog3NextValue],eax
  cmp   eax,31
  jb    Prog3Loop
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_EXIT
  mov   eax,[Prog3SumValue]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
Prog3Done:
  jmp   Prog3Done

align 4
Prog3SumValue        dd 0
Prog3NextValue       dd 0
