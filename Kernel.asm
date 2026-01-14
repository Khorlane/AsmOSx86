;**************************************************************************************************
; Kernel.asm
;   A basic 32 bit binary kernel
;
; Test goal (updated)
;   - Exercise KbReadLine (editable line input) from Keyboard.asm
;   - Show a prompt, accept a line, then print: "You typed: <line>"
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
;--------------------------------------------------------------------------------------------------
; Include Macro Definitions
;--------------------------------------------------------------------------------------------------
%include "Macros.asm"

;--------------------------------------------------------------------------------------------------
; Include Major Components
;--------------------------------------------------------------------------------------------------
%include "Config.asm"
%include "Console.asm"
%include "Floppy.asm"
%include "Keyboard.asm"
%include "Time.asm"
%include "Timer.asm"
%include "Uptime.asm"
%include "Utility.asm"
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

  ; Clear screen
  mov   al,Black                        ; Background
  mov   [ColorBack],al                  ;  color
  mov   al,Purple                       ; Foreground
  mov   [ColorFore],al                  ;  color
  call  SetColorAttr                    ; Set color
  call  ClrScr                          ; Clear screen
  mov   al,1                            ; Set
  mov   [Row],al                        ;  Row,Col
  mov   al,1                            ;  to
  mov   [Col],al                        ;  1,1

  ; Initialize components
  call  TimerInit                       ; Initialize PIT / monotonic ticks
  call  UptimeInit                      ; Initialize uptime
  call  TimeSync                        ; Sync time from CMOS
  call  CnInit                          ; Initialize console
  call  KbInit                          ; Initialize keyboard

  ; Debug prints to show time and uptime
  call  UptimePrint                     ; Uptime
  call  TimePrint                       ; Print Time
  mov   eax,1000                        ; Delay                 
  call  TimerDelayMs                    ;  1 second
  call  TimePrint                       ; Print Time
  call  UptimePrint                     ; Print Uptime
  call  FloppyTest                      ; Floppy motor test

  ; Debug addresses and memory content
  mov   eax,0DEADBEEFh                  ; Dump a
  mov   [Byte4],eax                     ;  known value
  call  DebugIt                         ;  expect DEADBEEF
  xor   eax,eax                         ; Dump
  mov   [Byte4],eax                     ;  value of
  mov   [Byte4],esp                     ;  esp
  call  DebugIt                         ;  expect 00090000
  xor   eax,eax                         ; Dump
  mov   [Byte4],eax                     ;  value of
  mov   [Byte4],cs                      ;  cs
  call  DebugIt                         ;  expect 00000008
  xor   eax,eax                         ; Dump
  mov   [Byte4],eax                     ;  8 bytes of 
  mov   eax,[100000h]                   ;  memory, starting
  mov   [Byte4],eax                     ;  at address
  call  DebugIt                         ;  1mb (100000h)

;------------------------------------------------------------------------------------------------
; Line-input test harness
;   - Print prompt
;   - Read line into LineBuf (editable)
;   - Print "You typed: " + the line + CRLF
;------------------------------------------------------------------------------------------------
ShellLoop:
  ; Show prompt (LStr)
  mov   ebx,PromptStr                   ; EBX = LStr "> "
  call  PutStr                          ; print prompt
  ; Read a full line into LineBuf as C string (NUL-terminated)
  mov   ebx,LineBuf                     ; EBX = CStr destination buffer
  mov   ecx,LINE_MAX                    ; max chars (excluding NUL)
  call  KbReadLine                      ; blocks until Enter; LineBuf becomes NUL-terminated
  ; Convert CStr(LineBuf) -> LStr(LineLStr) so we can print with PutStr
  mov   esi,LineBuf                     ; ESI = CStr source
  mov   edi,LineLStr                    ; EDI = LStr destination
  call  CStrToLStr                      ; updates [LineLStr] length + payload
  ; Echo: "You typed: " + line + CRLF
  mov   ebx,TypedPrefixStr              ; EBX = LStr "You typed: "
  call  PutStr                          ; print prefix
  mov   ebx,LineLStr                    ; EBX = LStr version of the input line
  call  PutStr                          ; print the line
  mov   ebx,CrLf                        ; EBX = LStr CRLF
  call  PutStr                          ; newline
  jmp   ShellLoop

  hlt

;--------------------------------------------------------------------------------------------------
; Working Storage
;--------------------------------------------------------------------------------------------------

; Strings
String  PromptStr,">"," "
String  TypedPrefixStr,"You typed: "

; Line input buffer (0-terminated)
align 4
LineBuf     times (LINE_MAX+1) db 0     ; +1 for 0 terminator
; Line input LStr buffer
LineLStr:  dw 0
          times LSTR_MAX db 0

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