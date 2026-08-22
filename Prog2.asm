;**************************************************************************************************
; Prog2.asm
;   Tiny flat user-program smoke test.
;**************************************************************************************************

[bits 32]
  org   00200000h

KC_TS_YIELD         equ 3
KC_TS_EXIT          equ 5
KC_BLOCK            equ 00210000h
KC_BLOCK_NUMBER     equ 0
KC_BLOCK_ARG0       equ 8

Start:
  mov   dword[Prog2SumValue],0
  mov   dword[Prog2NextValue],11
  mov   dword[Prog2YieldCount],0
Prog2Loop:
  mov   eax,[Prog2SumValue]
  add   eax,[Prog2NextValue]
  mov   [Prog2SumValue],eax
  mov   eax,[Prog2YieldCount]
  inc   eax
  mov   [Prog2YieldCount],eax
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_YIELD
  int   080h
  mov   eax,[Prog2NextValue]
  inc   eax
  mov   [Prog2NextValue],eax
  cmp   eax,26
  jb    Prog2Loop
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_EXIT
  mov   eax,[Prog2YieldCount]
  shl   eax,16
  or    eax,[Prog2SumValue]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  int   080h
Prog2Done:
  jmp   Prog2Done

align 4
Prog2SumValue        dd 0
Prog2NextValue       dd 0
Prog2YieldCount      dd 0
