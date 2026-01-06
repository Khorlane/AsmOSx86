;**********************************************************
; Video.asm
;   Video routines for kernel
;   Provides basic video output functions
;   such as printing characters and strings to the screen
;   and updating the hardware cursor.
;**********************************************************

;--------------------------------------------------------------------------------------------------
; Video Routines
;--------------------------------------------------------------------------------------------------

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

;------------------------------------------
; Routine to calculate video memory address
;   represented by the given Row,Col
;------------------------------------------
CalcVideoAddr:
  pusha                                 ; Save registers
  mov   al,[Row]                        ; If Row is
  cmp   al,25                           ;  is less than 25
  jl    CalcVideoAddr1                  ;  go to CalcVideoAddr1
  mov   al,24                           ; Set row to 24
  mov   [Row],al                        ;  save it
  call  ScrollUp                        ;  and scroll up the screen
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

;------------------------------
; Put a character on the screen
; EDI = address in video memory
;------------------------------
PutChar:
  pusha                                 ; Save registers
  mov   edi,[VidAdr]                    ; EDI = Video Address
  mov   dl,[Char]                       ; DL = character
  mov   dh,[ColorAttr]                  ; DH = attribute
  mov   [edi],dx                        ; Move attribute and character to video display
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;---------------------------------
; Print a string to the screen
; EBX = address of string to print
;---------------------------------
PutStr:
  pusha                                 ; Save registers
  call  CalcVideoAddr                   ; Calculate video address
  xor   ecx,ecx                         ; Clear ECX
  push  ebx                             ; Copy the string address in EBX
  pop   esi                             ;  into ESI
  mov   cx,[esi]                        ; Grab string length using ESI, stuff it into CX
  sub   cx,2                            ; Subtract out 2 bytes for the length field
  add   esi,2                           ; Bump past the length field to the beginning of string
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
  mov   al,[Row]                        ;   bump row
  inc   al                              ;   by 1
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
  call  MoveCursor                      ; Update cursor (do this once after displaying the string, more efficient)
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;-----------------------
; Update hardware cursor
;-----------------------
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

;-------------
; Clear Screen
;-------------
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

;-------------------
; Set Color Attribute
;-------------------
SetColorAttr:
  pusha                                 ; Save registers
  mov   al,[ColorBack]                  ; Background color (e.g. 3)
  shl   al,4                            ;  goes in highest 4 bits of AL
  mov   bl,[ColorFore]                  ; Foreground color in lowest 4 bits of BL (e.g. F)
  or    eax,ebx                         ; AL now has the combination of background and foreground (e.g. 3F)
  mov   [ColorAttr],al                  ; Save result in ColorAttr
  popa                                  ; Restore registers
  ret                                   ; Return to caller

;-----------------
; Scroll Screen Up
;-----------------
ScrollUp:
  pusha
  mov   esi,VidMem + 160                ; start of row 2
  mov   edi,VidMem                      ; start of row 1
  mov   ecx,24*80                       ; 24 rows × 80 columns
  rep   movsw                           ; copy each word (char+attr)
  ; Clear bottom row
  mov   ax,' '                          ; space character
  mov   ah,[ColorAttr]                  ; current color
  mov   edi,VidMem + 24*160             ; start of row 25
  mov   ecx,80
ScrollClr:
  stosw
  loop  ScrollClr
  popa
  ret