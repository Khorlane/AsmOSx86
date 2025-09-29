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
  lea   eax, [GDTDescriptor]          ; Load the GDT
  lgdt  [eax]                         ;  register
  mov   ax,10h                        ; Set data
  mov   ds,ax                         ;  segments to
  mov   ss,ax                         ;  data selector
  mov   es,ax                         ;  (10h)
  mov   esp,90000h                    ; Stack begins from 90000h
  lea   eax, [IDT2]                   ; Load the IDT
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
  mov   eax,0DEADBEEFh
  call  DebugIt                       ; expect DEADBEEF
  mov   eax,esp
  call  DebugIt                       ; expect 00090000
  mov   eax,cs
  call  DebugIt                       ; expect 00000008
  mov   eax,[0]
  call  DebugIt                       ; should read from linear address 0x00000000

PollKbLoop:
  call  KbRead                        ; Read keyboard
  mov   al,[KbChar]                   ; If nothing
  cmp   al,0FFh                       ;  read (KbChar == 0xFF)
  je    PollKbLoop                    ;  keep polling until a key is pressed
  mov   al,[KbChar]                   ; Get the key
  movzx eax,al                        ; Move key into EAX
  call  DebugIt                       ; Dump it as hex
  call  KbXlate                       ; Translate to ASCII
  call  PrintKbChar                   ; Print it
  jmp   PollKbLoop                    ; Repeat

  hlt

;--------------------------------------------------------------------------------------------------
; DebugIt — Dumps EAX as hex
;--------------------------------------------------------------------------------------------------
DebugIt:
  call  HexDump                       ; Convert EAX to hex string stuff it into Buffer
  mov   ebx,Buffer                    ; Put
  call  PutStr                        ;  string
  mov   ebx,NewLine                   ; Put
  call  PutStr                        ;  newline
  ret

PrintKbChar:
  mov   al,[KbChar]                   ; Get translated character
  mov   [Buffer+2], al                ; First byte of string (skip length word)
  mov   ecx,7                         ; Fill remaining 7 bytes
  mov   ebx,Buffer+3                  ; Start at second character
  mov   al,' '                        ; Space character
FillSpaces:
  mov   [ebx],al                      ; Fill 
  inc   ebx                           ;  with
  loop  FillSpaces                    ;  spaces
  mov   ebx,Buffer                    ; Put
  call  PutStr                        ;  string
  mov   ebx,NewLine                   ; Put
  call  PutStr                        ;  newline
  ret

;--------------------------------------------------------------------------------------------------
; HexDump Routine — Converts EAX to 8 ASCII hex digits
;--------------------------------------------------------------------------------------------------
HexDump:
  push  eax
  push  ebx
  push  ecx
  push  edx
  mov   ecx,8                         ; We want 8 hex digits
  mov   ebx,Buffer+2                  ; Skip length word, point to first char
HexDump1:
  mov   edx,eax                       ; Copy eax to edx
  shr   edx,28                        ; Shift top nibble into lowest 4 bits
  and   edx,0Fh                       ; Mask to isolate nibble
  mov   dl,[HexDigits+edx]            ; Look up ASCII character
  mov   [ebx],dl                      ; Store in Buffer
  inc   ebx                           ; Point to next character
  shl   eax,4                         ; Shift next nibble into position
  loop  HexDump1
  pop   edx
  pop   ecx
  pop   ebx
  pop   eax
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

ColorBack   db  0                       ; Background color (00h - 0Fh)
ColorFore   db  0                       ; Foreground color (00h - 0Fh)
ColorAttr   db  0                       ; Combination of background and foreground color (e.g. 3Fh 3=cyan background,F=white text)
Char        db  0                       ; ASCII character
KbChar      db  0                       ; Keyboard character
Row         db  0                       ; Row (1-25)
Col         db  0                       ; Col (1-80)
VidAdr      dd  0                       ; Video Address
HexDigits   db  "0123456789ABCDEF"

;--------------------------------------------------------------------------------------------------
; Video
;--------------------------------------------------------------------------------------------------
VidMem      equ 0B8000h                 ; Video Memory (Starting Address)
TotCol      equ 80                      ; width and height of screen
Black       equ 00h                     ; Black
Cyan        equ 03h                     ; Cyan
Purple      equ 05h                     ; Purple
White       equ 0Fh                     ; White

;--------------------------------------------------------------------------------------------------
; Keyboard
;--------------------------------------------------------------------------------------------------
Scancode    db  10h, 11h, 90h, 91h         ; Scancodes for 'q', 'w', 'Q', 'W'
ScancodeSz  db  ScancodeSz-Scancode

CharCode    db  71h, 77h, 51h, 57h         ; Hexcodes  for 'q', 'w', 'Q', 'W'
CharCodeSz  db  CharCodeSz-CharCode