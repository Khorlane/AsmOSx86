;**************************************************************************************************
; Kernel.asm
;   A basic 32 bit binary kernel for x86 PCs.
;
; nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst
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
  NullDesc              equ 00h             ; Null Descriptor
  CodeDesc              equ 08h             ; Code Segment Descriptor
  DataDesc              equ 10h             ; Data Segment Descriptor

;--------------------------------------------------------------------------------------------------
; Interrupt Descriptor Table (IDT)
;--------------------------------------------------------------------------------------------------
IDT1: times 256 dq 0
IDT2:
  dw 2047
  dd IDT1

%define KEY_NONE        0
%define KEY_CHAR        1
%define KEY_ENTER       2
%define KEY_BACKSPACE   3

%define VD_COLS         80
%define VD_ROWS         25
%define VD_OUT_MAX_ROW  23          ; output region rows: 0..23
%define VD_IN_ROW       24          ; fixed input line row

%define VGA_TEXT_BASE   0xB8000
%define VD_ATTR_DEFAULT 0x07

%define KBD_STATUS_PORT 0x64
%define KBD_DATA_PORT   0x60

;--------------------------------------------------------------------------------------------------
; Include Major Components
;--------------------------------------------------------------------------------------------------
%include "Console.asm"
%include "Keyboard.asm"
%include "Video.asm"

;--------------------------------------------------------------------------------------------------
; Kernel Entry Point
;--------------------------------------------------------------------------------------------------
Stage3:
  cli                                   ; Disable interrupts during setup
  ; Set up segments, stack, GDT, IDT
  lea   eax,[GDTDescriptor]             ; Load the GDT
  lgdt  [eax]                           ;  register
  jmp   CodeDesc:FlushCS                ; Far jump to reload CS’s hidden descriptor cache
FlushCS:
  mov   ax,DataDesc                     ; Set segment registers to data selector
  mov   ds,ax                           ;  Data segment
  mov   ss,ax                           ;  Stack segment
  mov   es,ax                           ;  Extra segment
  mov   fs,ax                           ;  General-purpose segment
  mov   gs,ax                           ;  General-purpose segment
  mov   esp,90000h                      ; Stack begins from 90000h
  lea   eax,[IDT2]                      ; Load the IDT
  lidt  [eax]                           ;  register

  call  CnInit                          ; Initialize console
  call  KbInit                          ; Initialize keyboard
  call  VdInit                          ; Initialize video

MainLoop:
  ; Provide destination Sting buffer and max chars via memory inputs
  mov dword [CnInDstPtr], CmdBuf
  mov word  [CnInMax], 80        ; max payload chars (<=80)
  call CnReadLine                  ; echoes on bottom row; returns Sting in CmdBuf
  ; v0.0.1: do nothing with the command yet (echo already happened)
  jmp MainLoop

  hlt

;--------------------------------------------------------------------------------------------------
; Working Storage
;--------------------------------------------------------------------------------------------------

; Kernel Context (all mutable "variables" live here)
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

; Command line buffer as Sting:
; [0..1]=u16 length, [2..]=payload chars
CmdBuf:
    times (2 + 80) db 0