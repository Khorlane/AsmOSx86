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
; Global Descriptor Table (GDT) for Kernel
;--------------------------------------------------------------------------------------------------
align 8
GDTTable:
    dq 0x0000000000000000       ; Null descriptor
    dq 0x00CF9A000000FFFF       ; Code segment: base=0, limit=4GB, type=code, ring 0
    dq 0x00CF92000000FFFF       ; Data segment: base=0, limit=4GB, type=data, ring 0

GDTDescriptor:
    dw GDTDescriptor - GDTTable - 1   ; Limit = size of GDT - 1
    dd GDTTable                       ; Base address of GDT

;--------------------------------------------------------------------------------------------------
; Include Major Components
;--------------------------------------------------------------------------------------------------
%include "Video.asm"                    ; Include video routines

;--------------------------------------------------------------------------------------------------
; Install our IDT
;--------------------------------------------------------------------------------------------------
InstallIDT:
    mov ax, 0x10         ; Ensure ES is valid before stosb
    mov es, ax
    cli                                 ; Disable interrupts
    pusha                               ; Save registers
    mov word [IDT2], 2047
    mov dword [IDT2+2], IDT1
    lidt  [IDT2]                        ; Load IDT into IDTR
    mov   edi,IDT1                      ; Set EDI to beginning of IDT
    mov   cx,2048                       ; 2048 bytes in IDT
    xor   eax,eax                       ; Set all 256 IDT entries to NULL (0h)
    rep   stosb                         ; Move AL to IDT pointed to by EDI, Repeat CX times, increment EDI each time
    mov ax,0
.loop:
    mov edx,FaultHandler
    call SetIDTGate
    inc ax
    cmp ax,32
    jl .loop
    
    mov ax, 0x00
    mov edx, DivideByZeroHandler
    call SetIDTGate

    mov ax, 0x08
    mov edx, DoubleFaultHandler
    call SetIDTGate

    mov   ax,0x08
    mov   edx,FaultHandler
    call  SetIDTGate

    mov   ax,0x0D
    mov   edx,FaultHandler
    call  SetIDTGate

    ; Inspect type byte of IDT[0x00]
    mov edi, IDT1
    add edi, 0x00 * 8
    mov al, [edi+5]
    call PrintByteHex      ; Should also print 8E if correct

    ; Inspect type byte of IDT[0x0D]
    mov edi, IDT1
    add edi, 0x0D * 8      ; Each gate is 8 bytes
    mov al, [edi+5]        ; Byte 5 = type field
    call PrintByteHex      ; Should print 8E if correct

    sti                                 ; Enable interrupts
    popa                                ; Restore registers
    ret                                 ; All done!

;--------------------------------------------------------------------------------------------------
; Keyboard Routines
;--------------------------------------------------------------------------------------------------
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
    lgdt [GDTDescriptor]
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
    call  SetPIT                        ; Configure the PIT for timer interrupts

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
    
    ;-----------------
    ; Set Keyboard IDT  
    ;-----------------
    mov edx,021h                       ; IRQ1 maps to vector 0x21  
    shl edx,3                          ; Multiply by 8 (IDT entry size)
    add edx,IDT                        ; Point to correct IDT slot
    mov ax,08E00h                      ; Present, DPL=0, 32-bit interrupt gate
    mov [EDX+4],ax                     ; Set access rights
    mov eax,IsrKeyboard                ; Address of ISR
    mov [edx],eax                      ; Low 16 bits of offset  
    shr eax,16                         ; High 16 bits of offset  
    mov [EDX+6],eax                    ; Set high offset  
    mov ax,008h                        ; Code segment selector  
    mov [EDX+2],ax                     ; Set segment selector

    ;--------------------
    ; ISR - Timer started
    ;--------------------
    mov   ebx,NewLine                   ; Put
    call  PutStr                        ;  a New Line
    mov   ebx,Msg4                      ; Put
    call  PutStr                        ;  Msg4
    mov   dword [SleepTicks],100        ; 3 seconds ≈ 100 ticks
    ;call  Sleep                         ; Sleep for 3 seconds
    ;call  ClrScr                        ; Clear screen

    ;-------------------
    ; Get Keyboard input
    ;-------------------
    mov   al,0                          ; Set starting
    mov   [Row],al                      ;  Row
    mov   al,1                          ;  and Col
    mov   [Col],al                      ;  for hex output
GetKey:
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
    add   al,1                          ;  Row
    mov   [Row],al                      ;  by 1
    call  CalcVideoAddr                 ; Put the keyboard
    mov   bl,[KbChar]                   ;  character
    mov   [Char],bl                     ;  on that
    call  PutChar                       ;  row
    call  MoveCursor                    ; Update cursor
    mov   bl,[KbChar]                   ; Quit
    cmp   bl,071h                       ;  when q (ASCII 071h)
    je    AllDone                       ;  is pressed
    mov   al,0FFh                       ; Reset KbChar
    mov   [KbChar],al                   ;  to wait for next key
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

;----------------------------------------------
; Configure PIT for 18.2 Hz (default frequency)
;----------------------------------------------
SetPIT:
    mov   al,00110110b                  ; Set PIT to Mode 3 (Square Wave Generator)
    out   43h,al                        ; Write to PIT control port
    mov   ax,0FFFFh                     ; Divisor for 18.2 Hz (default)
    out   40h,al                        ; Write low byte of divisor
    mov   al,ah                         ; Write high byte of divisor
    out   40h,al
    ret

;----------
; ISR Timer
;----------
IsrTimer:
    pushad
    inc   dword [TimerTicks]            ; Increment the tick counter
    mov   al,020h                       ; Send EOI - End of Interrupt
    out   PIC1_CTRL,al                  ;  to master PIC
    popad
    iretd

;-------------
; ISR Keyboard  
;-------------
IsrKeyboard:  
    pushad  
    in al,060h                         ; Read scancode from keyboard  
    mov [KbChar],al                    ; Store it in KbChar  
    mov al,020h                        ; Send EOI to PIC  
    out PIC1_CTRL,al  
    popad  
    iretd

SetIDTGate:
    ; ax = vector number
    ; edx = handler address
    mov edi, IDT1
    movzx ebx, ax
    shl ebx, 3
    add edi, ebx
    ; Offset low
    mov word [edi], dx
    ; Selector
    mov word [edi+2], 0x08
    ; Zero byte
    mov byte [edi+4], 0
    ; Type: 0x8E = 32-bit interrupt gate, ring 0, present
    mov byte [edi+5], 0x8E
    ; Offset high
    shr edx, 16
    mov word [edi+6], dx
    ret

FaultHandler:
    cli
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov ebx, FaultMsg
    call PutStr
    jmp $

DivideByZeroHandler:
    cli
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov ebx, DivideMsg
    call PutStr
    jmp $

DoubleFaultHandler:
    cli
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov ebx, DoubleMsg
    call PutStr
    jmp $

;----------------------------------------------------------
; Sleep for approximately the number of ticks in SleepTicks
;----------------------------------------------------------
Sleep:
    push eax
    push ecx
    mov ecx,[TimerTicks]               ; Get current tick count
    add ecx,[SleepTicks]               ; Target tick count = now + SleepTicks
SleepWait:
    cmp [TimerTicks],ecx              ; Has target tick been reached?
    jae SleepDone                     ; If yes (TimerTicks >= ecx), exit
    hlt                               ; Halt until next interrupt
    jmp SleepWait                     ; Check again
SleepDone:
    pop ecx
    pop eax
    ret

;----------------------
; Flush keyboard buffer
;----------------------
FlushKbBuffer:
    ; Optional: Disable keyboard to prevent new data
    mov   al,0ADh                     ; Command: Disable keyboard
    out   064h,al
    mov   ecx,8
FlushLoop:
    in    al,060h                     ; Read and discard scancode
    loop  FlushLoop
DoneFlush:
    ; Optional: Re-enable keyboard
    mov   al,0AEh                     ; Command: Enable keyboard
    out   064h,al
    ret

;--------------------------------------------------
; PrintByteHex: prints byte in AL as two hex digits
;--------------------------------------------------
PrintByteHex:
    push ax
    mov ah, al
    shr ah, 4
    call PrintNibble

    pop ax
    and al, 0Fh
    call PrintNibble
    ret

;--------------------------------------------------
; PrintNibble: prints hex digit in AL (0–F)
;--------------------------------------------------
PrintNibble:
    and al, 0Fh
    cmp al, 9
    jbe .digit
    add al, 7          ; Convert 10–15 to 'A'–'F'
.digit:
    add al, '0'

    ; Write to video memory at 0xB8000
    mov ebx, [CursorPos]     ; Get current cursor offset
    mov edi, 0xB8000
    add edi, ebx

    mov [edi], al            ; Character byte
    mov byte [edi+1], 0x07   ; Attribute: light gray on black

    mov bx, [CursorPos]
    add bx, 2               ; Advance cursor
    mov [CursorPos], bx
    ret

;--------------------------------------------------
; CursorPos: tracks current screen position
;--------------------------------------------------
CursorPos: dw 160

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
String  Msg4,"ISR Timer Started"
String  Msg5,"Start clearing keyboard buffer"
String  Msg6,"Finished clearing keyboard buffer"
String FaultMsg,"------   FAULT: System Halted   ------"
String  NewLine,0Ah
String  Buffer,"XXXXXXXX"

String  DivideMsg, "Divide by zero fault"
String  DoubleMsg, "Double fault triggered"


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

TimerTicks  dd  0                       ; Counter for timer ticks
SleepTicks  dd  0                       ; Number of ticks to sleep

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

;--------------------------------------------------------------------------------------------------
; Interrupt Descriptor Table (IDT)
;--------------------------------------------------------------------------------------------------
segment .data
align 4
IDT:
IDT1: times 2048 db 0
IDT2:
    dw 2047
    dd IDT1