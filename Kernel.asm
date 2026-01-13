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
%include "Console.asm"
%include "Floppy.asm"
%include "Keyboard.asm"
%include "Time.asm"
%include "Timer.asm"
%include "Uptime.asm"
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
  mov   ebx,PromptStr                   ; Print prompt
  call  PutStr                          ;  "> "
  mov   ebx,LineBuf                     ; EBX = destination buffer
  mov   ecx,LINE_MAX                    ; ECX = max chars (excluding 0 terminator)
  call  KbReadLine                      ; Blocks until Enter, buffer becomes 0-terminated string
  mov   ebx,TypedStr                    ; Echo input
  call  PutStr                          ;  with
  mov   ebx,LineBuf                     ;  "You typed: "
  call  PutZStr                         ;  followed
  mov   ebx,CrLf                        ;  by the
  call  PutStr                          ;  input
  jmp   ShellLoop

  hlt

;-----------------------------------------
; Floppy motor test (temporary)
;-----------------------------------------
FloppyTest:
  call  FloppyInit                      ; controller enabled, drive A:, motors off
  call  FloppyMotorOn                   ; motor on + internal spin-up wait
  ; keep it on ~1 second (1000 x ~1ms)
  mov   ecx,1000
FloppyTest1:
  call  FlpDelay1ms                     ; helper in Floppy.asm
  loop  FloppyTest1
  call  FloppyMotorOff                  ; motor off
  ret

;--------------------------------------------------------------------------------------------------
; PutZStr — print a 0-terminated string using Console.PutStr by chunking into Buffer
;
; Big picture
;   - Console.PutStr expects a length-prefixed string.
;   - This helper converts a C-style 0-terminated string into repeated PutStr calls.
;   - For simplicity in early stage, we print one char at a time.
;
; Input
;   EBX = pointer to 0-terminated string
;--------------------------------------------------------------------------------------------------
PutZStr:
  push  eax
  push  ebx
  push  ecx
  push  edx
  push  esi
  mov   esi,ebx                         ; ESI walks the input string
PutZStr1:
  mov   al,[esi]
  test  al,al
  jz    PutZStrDone
  mov   [ZBuf+2],al                     ; put char into 1-char length-prefixed string
  mov   ebx,ZBuf
  call  PutStr
  inc   esi
  jmp   PutZStr1
PutZStrDone:
  pop   esi
  pop   edx
  pop   ecx
  pop   ebx
  pop   eax
  ret

;--------------------------------------------------------------------------------------------------
; DebugIt — Dumps EAX as hex (unchanged, retained)
;--------------------------------------------------------------------------------------------------
DebugIt:
  call  HexDump                         ; Convert BYTE4 to hex string in Buffer
  mov   ebx,Buffer                      ; Print 
  call  PutStr                          ;  the
  mov   ebx,CrLf                        ;  hex
  call  PutStr                          ;  string
  ret

;--------------------------------------------------------------------------------------------------
; HexDump - Convert BYTE4 to hex string in Buffer
;--------------------------------------------------------------------------------------------------
HexDump:
  mov   eax,[Byte4]                     ; Load the value to be converted
  mov   ecx,8                           ; We want 8 hex digits
  mov   ebx,Buffer+2                    ; Skip string length, point to first byte of string
HexDump1:
  mov   edx,eax                         ; Copy eax to edx
  shr   edx,28                          ; Shift top nibble into lowest 4 bits
  and   edx,0Fh                         ; Mask to isolate nibble
  mov   dl,[HexDigits+edx]              ; Look up ASCII character
  mov   [ebx],dl                        ; Store in Buffer
  inc   ebx                             ; Point to next character
  shl   eax,4                           ; Shift next nibble into position
  loop  HexDump1
  ret

;--------------------------------------------------------------------------------------------------
; Working Storage
;--------------------------------------------------------------------------------------------------

; Strings
String  Buffer,"XXXXXXXX"
String  PromptStr,">"," "
String  TypedStr,"You typed:"," "
String  ZBuf,"X"

String  CnStartMsg1,"AsmOSx86 Console (Session 0)"
String  CnStartMsg2,"AsmOSx86 - A Hobbyist Operating System in x86 Assembly"
String  CnStartMsg3,"AsmOSx86 Initialization started"
String  CrLf,0Dh,0Ah
String  LogStampStr,"YYYY-MM-DD HH:MM:SS"
String  LogSepStr," "
String  TimeStr,"HH:MM:SS"
String  UptimeStr,"UP YY:DDD:HH:MM:SS"

; Line input buffer (0-terminated)
LINE_MAX    equ 64
align 4
LineBuf     times (LINE_MAX+1) db 0     ; +1 for 0 terminator

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

HexDigits   db  "0123456789ABCDEF"      ; Hex digits for conversion