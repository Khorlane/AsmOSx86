;**********************************************************
; Kernel.asm
;   A basic 32 bit binary kernel
;
; nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst
;**********************************************************

[bits  32]                            ; 32 bit code
  org   100000h                       ; Kernel starts at 1 MB
  jmp   Stage3                        ; Jump to entry point

GDTTable:
  dq 0x0000000000000000
  dq 0x00CF9A000000FFFF
  dq 0x00CF92000000FFFF
GDTTableEnd:

GDTDescriptor:
  dw GDTTableEnd - GDTTable - 1
  dd GDTTable

;--------------------------------------------------------------------------------------------------
; Interrupt Descriptor Table (IDT)
;--------------------------------------------------------------------------------------------------
IDT1: times 256 dq 0
IDT2:
  dw 2047
  dd IDT1

;--------------------------------------------------------------------------------------------------
; Include Major Components
;--------------------------------------------------------------------------------------------------
%include "Video.asm"
%include "Keyboard.asm"

;--------------------------------------------------------------------------------------------------
; Kernel Entry Point
;--------------------------------------------------------------------------------------------------
Stage3:
  ; Set up segments, stack, GDT, IDT
  lea   eax,[GDTDescriptor]           ; Load the GDT
  lgdt  [eax]                         ;  register
  mov   ax,10h                        ; Set data
  mov   ds,ax                         ;  segments to
  mov   ss,ax                         ;  data selector
  mov   es,ax                         ;  (10h)
  mov   esp,90000h                    ; Stack begins from 90000h
  lea   eax,[IDT2]                    ; Load the IDT
  lidt  [eax]                         ;  register

  ; Clear screen
  mov   al,Black                      ; Background
  mov   [ColorBack],al                ;  color
  mov   al,Purple                     ; Foreground
  mov   [ColorFore],al                ;  color
  call  SetColorAttr                  ; Set color
  call  ClrScr                        ; Clear screen
  mov   al,10                         ; Set
  mov   [Row],al                      ;  Row,Col
  mov   al,1                          ;  to
  mov   [Col],al                      ;  10,1

  ; Debug addresses and memory content
  mov   eax,0DEADBEEFh                ; Dump a
  mov   [Byte4],eax                   ;  known value
  call  DebugIt                       ;  expect DEADBEEF
  mov   [Byte4],esp                   ; Dump esp
  call  DebugIt                       ;  expect 00090000
  mov   [Byte4],cs                    ; Dump cs
  call  DebugIt                       ;  expect 00000008
  mov   eax,[100000h]                 ; Dump 8 bytes
  mov   [Byte4],eax                   ;  starting at 1MB
  call  DebugIt                       ;  100000h

KbPollLoop:
  call  KbRead                        ; Read keyboard
  mov   al,[KbChar]                   ; If nothing
  cmp   al,0FFh                       ;  read (KbChar == 0xFF)
  je    KbPollLoop                    ;  keep polling until a key is pressed
  xor   eax,eax                       ; Print
  mov   al,[KbChar]                   ;  the
  mov   [Byte4],eax                   ;  scancode
  call  DebugIt                       ;  as hex
  call  KbXlate                       ; Translate scancode to ASCII
  call  KbPrintChar                   ; Print it
  jmp   KbPollLoop                    ; Repeat

  hlt

;--------------------------------------------------------------------------------------------------
; DebugIt — Dumps EAX as hex
;--------------------------------------------------------------------------------------------------
DebugIt:
  call  HexDump                       ; Convert BYTE4 to hex string in Buffer
  mov   ebx,Buffer                    ; Put
  call  PutStr                        ;  string
  mov   ebx,NewLine                   ; Put
  call  PutStr                        ;  newline
  ret

;--------------------------------------------------------------------------------------------------
; KbPrintChar — Put KbChar into Buffer and print it
;--------------------------------------------------------------------------------------------------
KbPrintChar:
  mov   al,[KbChar]                   ; Get translated character
  mov   [Buffer+2],al                 ; First byte of string (skip length word)
  mov   ecx,7                         ; Fill remaining 7 bytes
  mov   ebx,Buffer+3                  ; Start at second character
  mov   al,' '                        ; Space character
KbPrintChar1:
  mov   [ebx],al                      ; Fill
  inc   ebx                           ;  with
  loop  KbPrintChar1                  ;  spaces
  mov   ebx,Buffer                    ; Put
  call  PutStr                        ;  string
  mov   ebx,NewLine                   ; Put
  call  PutStr                        ;  newline
  ret

;--------------------------------------------------------------------------------------------------
; HexDump - Convert BYTE4 to hex string in Buffer
;--------------------------------------------------------------------------------------------------
HexDump:
  mov   eax,[Byte4]                   ; Load the value to be converted
  mov   ecx,8                         ; We want 8 hex digits
  mov   ebx,Buffer+2                  ; Skip string length, point to first byte of string
HexDump1:
  mov   edx,eax                       ; Copy eax to edx
  shr   edx,28                        ; Shift top nibble into lowest 4 bits
  and   edx,0Fh                       ; Mask to isolate nibble
  mov   dl,[HexDigits+edx]            ; Look up ASCII character
  mov   [ebx],dl                      ; Store in Buffer
  inc   ebx                           ; Point to next character
  shl   eax,4                         ; Shift next nibble into position
  loop  HexDump1
  ret

;--------------------------------------------------------------------------------------------------
; Working Storage
;--------------------------------------------------------------------------------------------------
%macro String 2
%1          dw  %%EndStr-%1
            db  %2
%%EndStr:
%endmacro

String  Buffer,"XXXXXXXX"
String  NewLine,0Ah

Char        db  0                     ; ASCII character
Byte1       db  0                     ; 1-byte variable (al, ah)
Byte2       dw  0                     ; 2-byte variable (ax)
Byte4       dd  0                     ; 4-byte variable (eax)
HexDigits   db  "0123456789ABCDEF"    ; Hex digits for conversion

;--------------------------------------------------------------------------------------------------
; Video
;--------------------------------------------------------------------------------------------------
; Variables
ColorBack   db  0                     ; Background color (00h - 0Fh)
ColorFore   db  0                     ; Foreground color (00h - 0Fh)
ColorAttr   db  0                     ; Combination of background and foreground color (e.g. 3Fh 3=cyan background,F=white text)
Row         db  0                     ; Row (1-25)
Col         db  0                     ; Col (1-80)
VidAdr      dd  0                     ; Video Address
; Equates
VidMem      equ 0B8000h               ; Video Memory (Starting Address)
TotCol      equ 80                    ; width and height of screen
Black       equ 00h                   ; Black
Cyan        equ 03h                   ; Cyan
Purple      equ 05h                   ; Purple
White       equ 0Fh                   ; White

;--------------------------------------------------------------------------------------------------
; Keyboard
;--------------------------------------------------------------------------------------------------
; Variables
KbChar      db  0                     ; Keyboard character
; Make scancodes
Scancode    db 01Eh, 030h, 02Eh, 020h, 012h, 021h, 022h, 023h, 017h, 024h, 025h, 026h     ; Make Scancodes
            db 032h, 031h, 018h, 019h, 010h, 013h, 01Fh, 014h, 016h, 02Fh, 011h, 02Dh     ;  a-z keys
            db 015h, 02Ch, 00Bh, 002h, 003h, 004h, 005h, 006h, 007h, 008h, 009h, 00Ah     ;  and 0-9 keys
ScancodeEnd:
ScancodeSz  equ ScancodeEnd - Scancode                                                    ; Size of Scancode table
; Corresponding ASCII characters
CharCode    db 061h, 062h, 063h, 064h, 065h, 066h, 067h, 068h, 069h, 06Ah, 06Bh, 06Ch     ; ASCII characters
            db 06Dh, 06Eh, 06Fh, 070h, 071h, 072h, 073h, 074h, 075h, 076h, 077h, 078h     ;  a-z
            db 079h, 07Ah, 030h, 031h, 032h, 033h, 034h, 035h, 036h, 037h, 038h, 039h     ;  and 0-9
CharCodeEnd:
CharCodeSz  equ CharCodeEnd - CharCode                                                    ; Size of CharCode table
; Break scancodes to ignore
IgnoreCode  db 09Eh, 0B0h, 0AEh, 0A0h, 092h, 0A1h, 0A2h, 0A3h, 097h, 0A4h, 0A5h, 0A6h     ; Break Scancodes
            db 0B2h, 0B1h, 098h, 099h, 090h, 093h, 09Fh, 094h, 096h, 0BFh, 091h, 0ADh     ;  a-z
            db 095h, 0ACh, 08Bh, 082h, 083h, 084h, 085h, 086h, 087h, 088h, 089h, 08Ah     ;  and 0-9
IgnoreEnd:
IgnoreSz    equ IgnoreEnd - IgnoreCode                                                    ; Size of IgnoreCode table