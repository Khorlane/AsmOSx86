;**************************************************************************************************
; Kernel.asm
;   A basic 32 bit binary kernel for x86 PCs.
;
; nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst
;
; Coding Standards (LOCKED-IN)
; 1) Applies to all included files as well
; 2) Column Alignment
;    - Instruction mnemonic starts at column 3
;    - Operand 1 starts at column 9
;    - No spaces around operand commas
;    - Line comments start at column 41
; 3) Blank Lines
;    - No blank lines are allowed within a function
;    - Blank lines are allowed only between functions or major sections
; 4) Naming
;    - PascalCase (no underscores) is REQUIRED for:
;      * Labels
;      * Variables
;      * Storage symbols
;    - SCREAMING_SNAKE_CASE is REQUIRED for:
;      * Equates / constants
; 5) General Rules
;    - No size specifiers like BYTE, WORD, DWORD except for storage definitions
;    - No reliance on register values across CALL boundaries
;    - No .bss section; all storage is explicitly zero-initialized
;    - Row,Col ordering everywhere (row first, then column)
;**************************************************************************************************

[bits  32]                              ; 32 bit code
  org   100000h                         ; Kernel starts at 1 MB
  jmp   Stage3                          ; Jump to entry point

;--------------------------------------------------------------------------------------------------
; Global Descriptor Table (GDT)
;--------------------------------------------------------------------------------------------------
GDTTable:
  dq 0x0000000000000000                 ; Null Descriptor
  dq 0x00CF9A000000FFFF                 ; Code Segment Descriptor
  dq 0x00CF92000000FFFF                 ; Data Segment Descriptor
GDTTableEnd:

GDTDescriptor:
  dw GDTTableEnd - GDTTable - 1
  dd GDTTable

;--------------------------------------------------------------------------------------------------
; GDT Selector Equates
;--------------------------------------------------------------------------------------------------
  NULL_DESC             equ 00h         ; Null Descriptor
  CODE_DESC             equ 08h         ; Code Segment Descriptor
  DATA_DESC             equ 10h         ; Data Segment Descriptor

;--------------------------------------------------------------------------------------------------
; Interrupt Descriptor Table (IDT)
;--------------------------------------------------------------------------------------------------
IDT1: times 256 dq 0
IDT2:
  dw 2047
  dd IDT1

;--------------------------------------------------------------------------------------------------
; Include Macros
;--------------------------------------------------------------------------------------------------
%include "Macros.asm"

;--------------------------------------------------------------------------------------------------
; Include Major Components
;--------------------------------------------------------------------------------------------------
%include "Config.asm"
%include "Console.asm"
%include "Keyboard.asm"
%include "Time.asm"
%include "Timer.asm"
%include "Video.asm"

;--------------------------------------------------------------------------------------------------
; Kernel Entry Point
;--------------------------------------------------------------------------------------------------
Stage3:
  cli                                   ; Disable interrupts during setup
  ; Set up segments, stack, GDT, IDT
  lea   eax,[GDTDescriptor]             ; Load the GDT
  lgdt  [eax]                           ;  register
  ; Far jump required to reload CS hidden descriptor cache
  jmp   CODE_DESC:FlushCS               ; Reload CS hidden descriptor cache
FlushCS:
  mov   ax,DATA_DESC                    ; Set segment registers to data selector
  mov   ds,ax                           ;  Data segment
  mov   ss,ax                           ;  Stack segment
  mov   es,ax                           ;  Extra segment
  mov   fs,ax                           ;  General-purpose segment
  mov   gs,ax                           ;  General-purpose segment
  mov   esp,90000h                      ; Stack begins from 90000h
  lea   eax,[IDT2]                      ; Load the IDT
  lidt  [eax]                           ;  register

  ; Initialize subsystems
  call  TimerInit                       ; Initialize timer
  call  VdInit                          ; Initialize video
  call  KbInit                          ; Initialize keyboard
  call  CnInit                          ; Initialize console
  ; Start main command loop
  call  Console                         ; Console command loop

  hlt

; ----- Storage -----
; Kernel Context (all mutable "variables" live here)
;LegacyCtx: 
; "Legacy - unused - do not reference."
align 4
KernelCtx:
Char        db  0                       ; ASCII character (used by KbPrintChar)
Byte1       db  0                       ; 1-byte variable (al, ah)
KbChar      db  0                       ; Legacy keyboard scratch (unused by new driver)
ColorBack   db  0                       ; Background color (00h - 0Fh)
ColorFore   db  0                       ; Foreground color (00h - 0Fh)
ColorAttr   db  0                       ; Combination of background and foreground color (e.g. 3Fh 3=cyan background,F=white text)
Row         db  0                       ; Row (1-25)
Col         db  0                       ; Col (1-80)
align 2
Byte2       dw  0                       ; 2-byte variable (ax)
align 4
Byte4       dd  0                       ; 4-byte variable (eax)
TvRowOfs    dd  0                       ; Row Offset
VidAdr      dd  0                       ; Video Address
KernelCtxEnd:
align 4
KernelCtxSz  equ KernelCtxEnd - KernelCtx
; NASM sanity check. The kernel context memory block must be divisible by 4
; due to `rep movsd` in the ContextSwitch routine
%if (KernelCtxSz % 4) != 0
  %error "KernelCtxSz is not dword aligned"
%endif