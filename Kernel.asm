;**********************************************************
; Kernel.asm
;   A basic 32 bit binary kernel
;
; nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst
;**********************************************************

[bits  32]                              ; 32 bit code
    org   100000h                       ; Kernel starts at 1 MB
    jmp   Stage3                        ; Jump to entry point

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
    pusha                               ; Save registers
    xor   eax,eax                       ; Row calculation
    mov   al,[Row]                      ;  row
    dec   eax                           ;  minus 1
    mov   edx,160                       ;  times
    mul   edx                           ;  160
    push  eax                           ;  save it
    xor   eax,eax                       ; Col calculation
    mov   al,[Col]                      ;  col
    mov   edx,2                         ;  times
    mul   edx                           ;  2
    sub   eax,2                         ;  minus 2
    pop   edx                           ; Add col calculation
    add   eax,edx                       ;  to row calculation
    add   eax,VidMem                    ;  plus VidMem
    mov   [VidAdr],eax                  ; Save in VidAdr
    popa                                ; Restore registers
    ret                                 ; Return to caller

;------------------------------
; Put a character on the screen
; EDI = address in video memory
;------------------------------
PutChar:
    pusha                               ; Save registers
    mov   edi,[VidAdr]                  ; EDI = Video Address
    mov   dl,[Char]                     ; DL = character
    mov   dh,[ColorAttr]                ; DH = attribute
    mov   [edi],dx                      ; Move attribute and character to video display
    popa                                ; Restore registers
    ret                                 ; Return to caller

;---------------------------------
; Print a null terminated string
; EBX = address of string to print
;---------------------------------
PutStr:
    pusha                               ; Save registers
    call  CalcVideoAddr                 ; Calculate video address
    xor   ecx,ecx                       ; Clear ECX
    push  ebx                           ; Copy the string address in EBX
    pop   esi                           ;  into ESI
    mov   cx,[esi]                      ; Grab string length using ESI, stuff it into CX
    sub   cx,2                          ; Subtract out 2 bytes for the length field
    add   esi,2                         ; Bump past the length field to the beginning of string
PutStr1:
    mov   bl,[esi]                      ; Get next character
    cmp   bl,0Ah                        ; NewLine?
    jne   PutStr2                       ;  No
    xor   eax,eax                       ;  Yes
    mov   al,1                          ;   Set Col
    mov   [Col],al                      ;   back to
    mov   al,[Row]                      ;   1 and
    inc   al                            ;   bump row
    mov   [Row],al                      ;   by 1
    call  CalcVideoAddr                 ; Calculate video address
    jmp   PutStr3                       ; Continue
PutStr2:
    mov   [Char],bl                     ; Stash our character
    call  PutChar                       ; Print it out
    mov   eax,[VidAdr]                  ; Bump
    add   eax,2                         ;  Video Address
    mov   [VidAdr],eax                  ;  by 2
    xor   eax,eax                       ; Bump
    mov   al,[Col]                      ;  Col
    add   al,1                          ;  by
    mov   [Col],al                      ;  1
PutStr3:
    inc   esi                           ; Bump ESI to next character in our string
    loop  PutStr1                       ; Loop (Decrement CX each time until CX is zero)
    call  MoveCursor                    ; Update cursor (do this once after displaying the string, more efficient)
    popa                                ; Restore registers
    ret                                 ; Return to caller

;-----------------------
; Update hardware cursor
;-----------------------
MoveCursor:
    pusha                               ; Save registers
    mov   bh,[Row]                      ; BH = row
    mov   bl,[Col]                      ; BL = col
    dec   bh                            ; BH-- (Make row zero based)

    xor   eax,eax                       ; Clear EAX
    mov   ecx,TotCol                    ; ECX = TotCol
    mov   al,bh                         ; Row
    mul   ecx                           ;  * TotCol
    add   al,bl                         ;  + Col
    mov   ebx,eax                       ; Save result in EBX (BL,BH in particular)

    xor   eax,eax                       ; Clear EAX
    mov   dx,03D4h                      ; Set VGA port to  03D4h (Video controller register select)
    mov   al,0Fh                        ; Set VGA port-index 0Fh (cursor location low byte)
    out   dx,al                         ; Write to the VGA port
    mov   dx,03D5h                      ; Set VGA port to  03D5h (Video controller data)
    mov   al,bl                         ; Set low byte of calculated cursor position from above
    out   dx,al                         ; Write to the VGA port

    xor   eax,eax                       ; Clear EAX
    mov   dx,03D4h                      ; Set VGA port to  03D4h (Video controller register select)
    mov   al,0Eh                        ; Set VGA port-index 0Fh (cursor location high byte)
    out   dx,al                         ; Write to the VGA port
    mov   dx,03D5h                      ; Set VGA port to  03D5h (Video controller data)
    mov   al,bh                         ; Set high byte of calculated cursor position from above
    out   dx,al                         ; Write to the VGA port

    popa                                ; Restore registers
    ret                                 ; Return to caller

;-------------
; Clear Screen
;-------------
ClrScr:
    pusha                               ; Save registers
    cld                                 ; Clear DF Flag, REP STOSW increments EDI
    mov   edi,VidMem                    ; Set EDI to beginning of Video Memory
    xor   ecx,ecx                       ; 2,000 'words'
    mov   cx,2000                       ;  on the screen
    mov   ah,[ColorAttr]                ; Set color attribute
    mov   al,' '                        ; We're going to 'blank' out the screen
    rep   stosw                         ; Move AX to video memory pointed to by EDI, Repeat CX times, increment EDI each time
    mov   al,1
    mov   [Col],al                      ; Set Col to 1
    mov   [Row],al                      ; Set Row to 1
    popa                                ; Restore registers
    ret                                 ; Return to caller

;-------------------
;Set Color Attribute
;-------------------
SetColorAttr:
    pusha                               ; Save registers
    mov   al,[ColorBack]                ; Background color (e.g. 3)
    shl   al,4                          ;  goes in highest 4 bits of AL
    mov   bl,[ColorFore]                ; Foreground color in lowest 4 bits of BL (e.g. F)
    or    eax,ebx                       ; AL now has the combination of background and foreground (e.g. 3F)
    mov   [ColorAttr],al                ; Save result in ColorAttr
    popa                                ; Restore registers
    ret                                 ; Return to caller

;--------------------------------------------------------------------------------------------------
; Install our IDT
;--------------------------------------------------------------------------------------------------
InstallIDT:
    cli                                 ; Disable interrupts
    pusha                               ; Save registers
    lidt  [IDT2]                        ; Load IDT into IDTR
    mov   edi,IDT1                      ; Set EDI to beginning of IDT
    mov   cx,2048                       ; 2048 bytes in IDT
    xor   eax,eax                       ; Set all 256 IDT entries to NULL (0h)
    rep   stosb                         ; Move AL to IDT pointed to by EDI, Repeat CX times, increment EDI each time
    sti                                 ; Enable interrupts
    popa                                ; Restore registers
    ret                                 ; All done!

;--------------------------------------------------------------------------------------------------
; Keyboard Routines
;--------------------------------------------------------------------------------------------------
KbRead:
    ;--------------
    ; Read scancode
    ;--------------
    mov   ecx,2FFFFh                    ; Set count for loop
KbWait:
    in    al,064h                       ; Read 8042 Status Register (bit 1 is input buffer status (0=empty, 1=full)
    test  al,1                          ; If bit 1
    jnz   KbGetIt                       ;  go get scancode
    loop  KbWait                        ; Keep looping
    mov   al,0FFh                       ; No scan
    mov   [KbChar],al                   ;  code received
    ret                                 ; All done!
KbGetIt:
    in    al,060h                       ; Obtain scancode from
    mov   [KbChar],al                   ;   Keyboard I/O Port
    ret                                 ; All done!
    ;-------------------
    ; Translate scancode
    ;-------------------
KbXlate:
    xor   eax,eax
    xor   esi,esi
    mov   ecx,ScancodeSz
    mov   al,[KbChar]                   ; Put scancode in AL
KbXlateLoop1:
    cmp   al,[Scancode+ESI]             ; Compare to Scancode
    je    KbXlateFound                  ; Match!
    inc   esi                           ; Bump ESI
    loop  KbXlateLoop1                  ; Check next
    mov   al,'?'                        ; Not found defaults to ? for now
    jmp   KbXlateDone                   ; Jump to done
KbXlateFound:
    mov   al,[CharCode+ESI]             ; Put ASCII character matching the Scancode in AL
KbXlateDone:
    mov   [KbChar],al                   ; Put translated char in KbChar
    ret                                 ; All done!

;---------
; Hex Dump
;---------
HexDump:
    pusha                               ; Save registers
    mov   ecx,8                         ; Move
    mov   esi,Buffer+2                  ;  8
    mov   al,020h                       ;  spaces
HexDump1:                               ;  to
    mov   [esi],al                      ;  clear
    inc   esi                           ;  out
    loop  HexDump1                      ;  Buffer
    mov   ecx,8                         ; Setup
    xor   edx,edx                       ;  for translating
    mov   dl,[KbChar]                   ;  the keyboard
    mov   ebx,HexDigits                 ;  scancode
    mov   esi,Buffer+9                  ;  to hex display
HexDump2:
    mov   al,dl                         ; Translate
    and   al,15                         ;  each
    xlat                                ;  hex
    mov   [esi],al                      ;  digit
    dec   esi                           ;  and put
    shr   edx,4                         ;  it in
    loop  HexDump2                      ;  Buffer
    popa                                ; Restore registers
    ret                                 ; Return to caller

;--------------------------------------------------------------------------------------------------
; Stage3 - Our Kernel code starts executing here!
;--------------------------------------------------------------------------------------------------
Stage3:
    ;--------------
    ; Set registers
    ;--------------
    mov   ax,10h                        ; Set data
    mov   ds,ax                         ;  segments to
    mov   ss,ax                         ;  data selector
    mov   es,ax                         ;  (10h)
    mov   esp,90000h                    ; Stack begins from 90000h

    call  InstallIDT                    ; Install our Interrupt Descriptor Table

    ;-------------
    ; Clear screen
    ;-------------
    mov   al,Black                      ; Background
    mov   [ColorBack],al                ;  color
    mov   al,Purple                     ; Foreground
    mov   [ColorFore],al                ;  color
    call  SetColorAttr                  ; Set color
    call  ClrScr                        ; Clear screen

    ;--------------
    ; Print success
    ;--------------
    mov   al,10                         ; Set
    mov   [Row],al                      ;  Row,Col
    mov   al,1                          ;  to
    mov   [Col],al                      ;  10,1
    mov   ebx,Msg1                      ; Put
    call  PutStr                        ;  Msg1
    mov   ebx,NewLine                   ; Put
    call  PutStr                        ;  a New Line
    mov   ebx,Msg2                      ; Put
    call  PutStr                        ;  Msg2

    ;------------------------
    ; Initialize the 8259 PIC
    ;------------------------
    mov   al,00010001b                  ; Set ICW1
    out   PIC1_CTRL,al                  ;  Intialize
    out   PIC2_CTRL,al                  ;  8259
    mov   al,020h                       ; Set ICW2
    out   PIC1_DATA,al                  ;  Map
    mov   al,028h                       ;  IRQs
    out   PIC2_DATA,al                  ;  32-47
    mov   al,00000100b                  ; Set ICW3
    out   PIC1_DATA,al                  ;  Connect PIC1
    mov   al,00000010b                  ;  and PIC2
    out   PIC2_DATA,al                  ;  via IRQ line 2
    mov   al,00000001b                  ; Set ICW4
    out   PIC1_DATA,al                  ;  We are in
    out   PIC2_DATA,al                  ;  80x86 mode

    ;--------------
    ; Set Timer IDT
    ;--------------
    mov   edx,020h                      ; Timer IRQ 0 is now IRQ 32 (020h)
    shl   edx,3                         ; Position into
    add   edx,IDT                       ;  the IDT
    mov   ax,08E00h                     ; Stash
    mov   [EDX+4],ax                    ;  stuff
    mov   eax,IsrTimer                  ;  into
    mov   [edx],ax                      ;  the IDT
    shr   eax,16                        ;  to link IRQ 32
    mov   [EDX+6],ax                    ;  to the
    mov   ax,008h                       ;  correct ISR
    mov   [EDX+2],ax                    ;  which is IsrTimer
    hlt                                 ; Halt and wait for timer interrupt to get us going again

    ;-------------------
    ; Get Keyboard input
    ;-------------------
    mov   al,0
    mov   [Row],al                      ; Set starting
    mov   al,1                          ;  Row, Col
    mov   [Col],al                      ;  for hex output
    cli                                 ; No Interrupts!
GetKey:
    mov   al,[Row]                      ; If Row is
    cmp   al,25                         ;  25 or more
    jl    GetKey1                       ;  reset
    mov   al,0                          ;  it to
    mov   [Row],al                      ;  zero
GetKey1:
    call  KbRead                        ; Read the keyboard
    mov   al,[KbChar]                   ; If nothing
    cmp   al,0FFh                       ;  read then
    je    GetKey                        ;  jump back
    call  HexDump                       ; Translate to hex display
    mov   al,[Row]                      ; Bump
    add   al,1                          ;  Row
    mov   [Row],al                      ;  by 1
    mov   al,1                          ; Reset
    mov   [Col],al                      ;  Col to 1
    mov   ebx,Buffer                    ; Put hex out at upper left
    call  PutStr                        ;  corner of the screen
    call  KbXlate                       ; Translate scancode to ASCII
    mov   al,1                          ; Reset
    mov   [Col],al                      ;  Col to 1
    mov   al,[Row]                      ; Bump
    add   al,1                          ;  Row by 1
    mov   [Row],al                      ;  and put the
    call  CalcVideoAddr                 ;  keyboard
    mov   bl,[KbChar]                   ;  character
    mov   [Char],bl                     ;  on that
    call  PutChar                       ;  row
    mov   bl,[KbChar]                   ; Quit
    cmp   bl,071h                       ;  when q (ASCII 071h)
    je    AllDone                       ;  is pressed
    jmp   GetKey                        ; Loop

AllDone:
    ;---------------
    ; Print shutdown
    ;---------------
    mov   ebx,NewLine                   ; Put
    call  PutStr                        ;  a New Line
    mov   ebx,NewLine                   ; Put
    call  PutStr                        ;  a New Line
    mov   ebx,Msg3                      ; Put
    call  PutStr                        ;  Msg3

    ;---------------
    ; Stop execution
    ;---------------
    cli                                 ; Disable interrupts
    hlt                                 ; Halt

    ;--------------------
    ; Temporary Timer ISR
    ;--------------------
IsrTimer:
    pushad
    mov   ebx,NewLine                   ; Put
    call  PutStr                        ;  a New Line
    mov   ebx,Msg4                      ; Put
    call  PutStr                        ;  Msg4
    mov   al,020h                       ; Send EOI - End of Interrupt
    out   PIC1_CTRL,al                  ;  to master PIC
    popad
    iretd

;--------------------------------------------------------------------------------------------------
; Interrupt Descriptor Table (IDT)
;--------------------------------------------------------------------------------------------------
IDT:
IDT1:
TIMES 2048  db 0                        ; The IDT is exactly 2048 bytes - 256 entries 8 bytes each
;-------------------
; pointer to our IDT
;-------------------
IDT2:
                  dw  IDT2-IDT1-1       ; limit (Size of IDT)
                  dd  IDT1              ; base of IDT

;--------------------------------------------------------------------------------------------------
; Working Storage
;--------------------------------------------------------------------------------------------------
%macro String 2
%1          dw  %%EndStr-%1
            db  %2
%%EndStr:
%endmacro
String  Msg1,"------   AsmOSx86 v0.0.1   -----"
String  Msg2,"--------  32 Bit Kernel --------"
String  Msg3,"AsmOSx86 has ended!!"
String  Msg4,"ISR - Timer - Fired"
String  NewLine,0Ah
String  Buffer,"XXXXXXXX"

ColorBack   db  0                       ; Background color (00h - 0Fh)
ColorFore   db  0                       ; Foreground color (00h - 0Fh)
ColorAttr   db  0                       ; Combination of background and foreground color (e.g. 3Fh 3=cyan background,F=white text)
Char        db  0                       ; ASCII character
KbChar      db  0                       ; Keyboard character
Row         db  0                       ; Row (1-25)
Col         db  0                       ; Col (1-80)
VidAdr      dd  0                       ; Video Address
HexDigits   db  "0123456789ABCDEF"

Scancode    db  10h, 11h
ScancodeSz  db  ScancodeSz-Scancode
CharCode    db  71h, 77h
CharCodeSz  db  ScancodeSz-Scancode

One         db  1

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
; PIC - 8259 Programmable Interrupt Controller
;--------------------------------------------------------------------------------------------------
PIC1        equ 020h                    ; PIC - Master
PIC2        equ 0A0h                    ; PIC - Slave
PIC1_CTRL   equ PIC1                    ; PIC1 Command port
PIC1_DATA   equ PIC1+1                  ; PIC1 Data port
PIC2_CTRL   equ PIC2                    ; PIC2 Command port
PIC2_DATA   equ PIC2+1                  ; PIC2 Data port