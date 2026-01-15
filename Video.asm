;**************************************************************************************************
; Video.asm
;   Video routines for kernel
;   Provides basic video output functions
;   such as printing characters and strings to the screen
;   and updating the hardware cursor.
;
; Video Contract (Kernel-facing)
;
; Exported:
;   CalcVideoAddr       ; uses Row/Col, updates VidAdr
;   CalcVideoAddrRaw    ; use for fixed UI areas
;   PutChar             ; uses Char/ColorAttr and VidAdr
;   PutStr              ; EBX=String, interprets CR/LF, updates Row/Col and cursor
;   PutStrRaw           ; Print an LStr without scrolling/clamping (Fixed UI areas)
;   MoveCursor
;   ClrScr
;   SetColorAttr
;   ScrollUp
;
; Requires (KernelCtx globals in Kernel.asm):
;   Row,Col,VidAdr,TvRowOfs
;   Char,ColorAttr,ColorBack,ColorFore
;
; Requires:
;   Doc/Abi.md String format (length-prefixed word + payload)
;
; Notes (LOCKED-IN):
;   - PutStr is responsible for CR/LF semantics for console output.
;   - Supports VidScrollTop / VidScrollBot
;   - ScrollUp respects those bounds
;**************************************************************************************************

;---------------
;- Color Codes -
;---------------
;  0 0 Black
;  1 1 Blue
;  2 2 Green
;  3 3 Cyan
;  4 4 Red
;  5 5 Magenta
;  6 6 Brown
;  7 7 White
;  8 8 Gray
;  9 9 Light Blue
; 10 A Light Green
; 11 B Light Cyan
; 12 C Light Red
; 13 D Light Magenta
; 14 E Yellow
; 15 F Bright White
; Example 3F
;         ^^
;         ||
;         ||- Foreground F = White
;         |-- Background 3 = Cyan

[bits 32]
section .data
VidMem      equ 0B8000h                 ; Video Memory (Starting Address)
TotCol      equ 80                      ; width and height of screen
Black       equ 00h                     ; Black
Cyan        equ 03h                     ; Cyan
Purple      equ 05h                     ; Purple
White       equ 0Fh                     ; White

section .text
;--------------------------------------------------------------------------------------------------
; Routine to calculate video memory address
;   represented by the given Row,Col
;--------------------------------------------------------------------------------------------------
CalcVideoAddr:
  pusha                                 ; Save registers
  mov   al,[Row]
  cmp   al,25                           ; rows 1..24 are valid for main output
  jl    CalcVideoAddr1
  mov   al,24
  mov   [Row],al
  call  ScrollUpMain                    ; keep row 25 untouched
CalcVideoAddr1:
  xor   eax,eax                         ; Row calculation
  mov   al,[Row]                        ;  row
  dec   eax                             ;  minus 1
  mov   edx,160                         ;  times
  mul   edx                             ;  160
  mov   [TvRowOfs],eax                  ;  save it
  xor   eax,eax                         ; Col calculation
  mov   al,[Col]                        ;  col
  mov   edx,2                           ;  times
  mul   edx                             ;  2
  sub   eax,2                           ;  minus 2
  mov   edx,[TvRowOfs]                  ; Add col calculation
  add   eax,edx                         ;  to row calculation
  add   eax,VidMem                      ;  plus VidMem
  mov   [VidAdr],eax                    ; Save in VidAdr
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; CalcVideoAddrRaw
;   Like CalcVideoAddr, but NEVER scrolls.
;   Intended for fixed UI areas (e.g., bottom command line at Row=25).
;--------------------------------------------------------------------------------------------------
CalcVideoAddrRaw:
  pusha
  mov   al,[Row]
  cmp   al,1
  jge   CalcVideoAddrRaw1
  mov   al,1
  mov   [Row],al
CalcVideoAddrRaw1:
  cmp   al,25
  jle   CalcVideoAddrRaw2
  mov   al,25
  mov   [Row],al
CalcVideoAddrRaw2:
  ; Same address math as CalcVideoAddr
  xor   eax,eax
  mov   al,[Row]
  dec   eax
  mov   edx,160
  mul   edx
  mov   [TvRowOfs],eax
  xor   eax,eax
  mov   al,[Col]
  mov   edx,2
  mul   edx
  sub   eax,2
  mov   edx,[TvRowOfs]
  add   eax,edx
  add   eax,VidMem
  mov   [VidAdr],eax
  popa
  ret

;--------------------------------------------------------------------------------------------------
; Put a character on the screen
; EDI = address in video memory
;--------------------------------------------------------------------------------------------------
PutChar:
  pusha                                 ; Save registers
  mov   edi,[VidAdr]                    ; EDI = Video Address
  mov   dl,[Char]                       ; DL = character
  mov   dh,[ColorAttr]                  ; DH = attribute
  mov   [edi],dx                        ; Move attribute and character to video display
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; Print a string to the screen
; EBX = address of string to print
;--------------------------------------------------------------------------------------------------
PutStr:
  pusha                                 ; Save registers
  call  CalcVideoAddr                   ; Calculate video address
  xor   ecx,ecx                         ; Clear ECX
  push  ebx                             ; Copy the string address in EBX
  pop   esi                             ;  into ESI
  mov   cx,[esi]
  cmp   cx,2                            ; if Length <= 2?
  jbe   PutStrDone                      ;  then Empty string
  sub   cx,2
  add   esi,2
  jcxz  PutStrDone
PutStr1:
  mov   bl,[esi]                        ; Get next character
  cmp   bl,0Dh                          ; CR?
  jne   PutStr2                         ;  No
  xor   eax,eax                         ;  Yes
  mov   al,1                            ;   Set Col
  mov   [Col],al                        ;   to 1
  call  CalcVideoAddr                   ;   and update address
  jmp   PutStr5                         ; Continue
PutStr2:
  cmp   bl,0Ah                          ; LF?
  jne   PutStr3                         ;  No
  xor   eax,eax                         ;  Yes
  mov   al,[Row]                        ;   if Row == 24, scroll (keep cmd line at 25 untouched)
  cmp   al,24
  jne   PutStr2a
  call  ScrollUpMain                    ;   (we'll tweak ScrollUp next to preserve row 25)
  mov   al,24
  mov   [Row],al                        ;   stay on last output row
  call  CalcVideoAddr
  jmp   PutStr5
PutStr2a:
  inc   al
  mov   [Row],al                        ;   (do not change Col)
  call  CalcVideoAddr                   ;   and update address
  jmp   PutStr5                         ; Continue
PutStr3:
  mov   [Char],bl                       ; Stash our character
  call  PutChar                         ; Print it out
  mov   eax,[VidAdr]                    ; Bump
  add   eax,2                           ;  Video Address
  mov   [VidAdr],eax                    ;  by 2
  xor   eax,eax                         ; Bump
  mov   al,[Col]                        ;  Col
  add   al,1                            ;  by
  mov   [Col],al                        ;  1
PutStr5:
  inc   esi                             ; Bump ESI to next character in our string
  loop  PutStr1                         ; Loop (Decrement CX each time until CX is zero)
PutStrDone:
  call  MoveCursor                      ; Update cursor (do this once after displaying the string, more efficient)
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; PutStrRaw
;   Print an LStr without scrolling/clamping (for fixed UI areas).
;   EBX = address of LStr to print
;--------------------------------------------------------------------------------------------------
PutStrRaw:
  pusha
  call  CalcVideoAddrRaw
  xor   ecx,ecx
  push  ebx
  pop   esi
  mov   cx,[esi]
  cmp   cx,2
  jbe   PutStrRawDone
  sub   cx,2
  add   esi,2
  jcxz  PutStrRawDone
PutStrRaw1:
  mov   bl,[esi]
  ; Backspace? move cursor left (do not print a glyph)
  cmp   bl,08h
  jne   PutStrRaw1_CR
  mov   al,[Col]
  cmp   al,1
  jbe   PutStrRaw5                      ; already at col 1 => nothing
  dec   al
  mov   [Col],al
  call  CalcVideoAddrRaw
  jmp   PutStrRaw5
PutStrRaw1_CR:
  cmp   bl,0Dh
  jne   PutStrRaw2
PutStrRaw2:
  cmp   bl,0Ah
  jne   PutStrRaw3
  xor   eax,eax
  mov   al,[Row]
  inc   al
  mov   [Row],al
  call  CalcVideoAddrRaw
  jmp   PutStrRaw5
PutStrRaw3:
  mov   [Char],bl
  call  PutChar
  mov   eax,[VidAdr]
  add   eax,2
  mov   [VidAdr],eax
  xor   eax,eax
  mov   al,[Col]
  add   al,1
  mov   [Col],al
PutStrRaw5:
  inc   esi
  loop  PutStrRaw1
PutStrRawDone:
  call  MoveCursor
  popa
  ret

;--------------------------------------------------------------------------------------------------
; Update hardware cursor
;--------------------------------------------------------------------------------------------------
MoveCursor:
  pusha                                 ; Save registers
  mov   bh,[Row]                        ; BH = row
  mov   bl,[Col]                        ; BL = col
  dec   bh                              ; BH-- (Make row zero based)
  xor   eax,eax                         ; Clear EAX
  mov   ecx,TotCol                      ; ECX = TotCol
  mov   al,bh                           ; Row
  mul   ecx                             ;  * TotCol
  add   al,bl                           ;  + Col
  mov   ebx,eax                         ; Save result in EBX (BL,BH in particular)
  xor   eax,eax                         ; Clear EAX
  mov   dx,03D4h                        ; Set VGA port to  03D4h (Video controller register select)
  mov   al,0Fh                          ; Set VGA port-index 0Fh (cursor location low byte)
  out   dx,al                           ; Write to the VGA port
  mov   dx,03D5h                        ; Set VGA port to  03D5h (Video controller data)
  mov   al,bl                           ; Set low byte of calculated cursor position from above
  out   dx,al                           ; Write to the VGA port
  xor   eax,eax                         ; Clear EAX
  mov   dx,03D4h                        ; Set VGA port to  03D4h (Video controller register select)
  mov   al,0Eh                          ; Set VGA port-index 0Fh (cursor location high byte)
  out   dx,al                           ; Write to the VGA port
  mov   dx,03D5h                        ; Set VGA port to  03D5h (Video controller data)
  mov   al,bh                           ; Set high byte of calculated cursor position from above
  out   dx,al                           ; Write to the VGA port
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; Clear Screen
;--------------------------------------------------------------------------------------------------
ClrScr:
  pusha                                 ; Save registers
  cld                                   ; Clear DF Flag, REP STOSW increments EDI
  mov   edi,VidMem                      ; Set EDI to beginning of Video Memory
  xor   ecx,ecx                         ; 2,000 'words'
  mov   cx,2000                         ;  on the screen
  mov   ah,[ColorAttr]                  ; Set color attribute
  mov   al,' '                          ; We're going to 'blank' out the screen
  rep   stosw                           ; Move AX to video memory pointed to by EDI, Repeat CX times, increment EDI each time
  mov   al,1
  mov   [Col],al                        ; Set Col to 1
  mov   [Row],al                        ; Set Row to 1
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; Set Color Attribute
;--------------------------------------------------------------------------------------------------
SetColorAttr:
  pusha                                 ; Save registers
  mov   al,[ColorBack]                  ; Background color (e.g. 3)
  shl   al,4                            ;  goes in highest 4 bits of AL
  mov   bl,[ColorFore]                  ; Foreground color in lowest 4 bits of BL (e.g. F)
  or    eax,ebx                         ; AL now has the combination of background and foreground (e.g. 3F)
  mov   [ColorAttr],al                  ; Save result in ColorAttr
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;--------------------------------------------------------------------------------------------------
; Scroll Screen Up
;--------------------------------------------------------------------------------------------------
ScrollUp:
  pusha
  mov   esi,VidMem+160                  ; start of row 2
  mov   edi,VidMem                      ; start of row 1
  mov   ecx,23*80                       ; Console 23 rows (later for shell 24 rows) × 80 columns)
  rep   movsw                           ; copy each word (char+attr)
  ; Clear bottom row
  mov   ax,' '                          ; space character
  mov   ah,[ColorAttr]                  ; current color
  mov   edi,VidMem + 23*160             ; start of row 24 for console (25 for shell)
  mov   ecx,80
ScrollUp1:
  stosw
  loop  ScrollUp1
  popa
  ret

;--------------------------------------------------------------------------------------------------
; ScrollUpMain — scroll rows 1..24 up by 1, keep row 25 untouched (reserved for console cmd line)
;--------------------------------------------------------------------------------------------------
ScrollUpMain:
  pusha
  mov   esi,VidMem+160                  ; source: start of row 2
  mov   edi,VidMem                      ; dest:   start of row 1
  mov   ecx,23*80                       ; copy 23 rows × 80 columns (rows 2..24 -> 1..23)
  rep   movsw                           ; copy each word (char+attr)

  ; Clear row 24 only (row 25 remains untouched)
  mov   ax,' '                          ; space character
  mov   ah,[ColorAttr]                  ; current color
  mov   edi,VidMem + 23*160             ; start of row 24
  mov   ecx,80
ScrollUpMain1:
  stosw
  loop  ScrollUpMain1
  popa
  ret

