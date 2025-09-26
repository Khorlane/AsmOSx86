;**********************************************************
; Kernel.asm
;   A basic 32 bit binary kernel
;
; nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst
;**********************************************************

[bits  32]                              ; 32 bit code
  org   100000h                         ; Kernel starts at 1 MB
  jmp   Stage3                          ; Jump to entry point

;--------------------------------------------------------------------------------------------------
; Include Major Components
;--------------------------------------------------------------------------------------------------
%include "Video.asm"                    ; Include video routines

;--------------------------------------------------------------------------------------------------
; Kernel Entry Point
;--------------------------------------------------------------------------------------------------
Stage3:
  ;--------------
  ; Set registers
  ;--------------
 	mov		ax,0x10
  mov   ds,ax                         ;  segments to
  mov   ss,ax                         ;  data selector
  mov   es,ax                         ;  (10h)
  mov   esp,90000h                    ; Stack begins from 90000h
  
 lea    eax, [GDTDescriptor]         ; Load the address of GDTDescriptor into EAX
 lgdt   [eax]                        ; Load the GDT using the address in EAX
  
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
  mov   ebx,NewLine                   ; Put
  call  PutStr                        ;  a New Line

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
  mov   ebx,Msg7                      ; Put
  call  DebugIt                       ;  Msg7

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
  mov   ebx,Msg8                      ; Put
  call  DebugIt                       ;  Msg8

  ;-----------------
  ; Set Keyboard IDT  
  ;-----------------
  mov   edx,021h                      ; IRQ1 maps to vector 0x21  
  shl   edx,3                         ; Multiply by 8 (IDT entry size)
  add   edx,IDT                       ; Point to correct IDT slot
  mov   ax,08E00h                     ; Present, DPL=0, 32-bit interrupt gate
  mov   [EDX+4],ax                    ; Set access rights
  mov   eax,IsrKeyboard               ; Address of ISR
  mov   [edx],eax                     ; Low 16 bits of offset  
  shr   eax,16                        ; High 16 bits of offset  
  mov   [EDX+6],eax                   ; Set high offset  
  mov   ax,008h                       ; Code segment selector  
  mov   [EDX+2],ax                    ; Set segment selector
  mov   ebx,Msg9                      ; Put
  call  DebugIt                       ;  Msg9

.halt:
  jmp .halt                           ; Infinite loop to prevent return

DebugIt:
  call PutStr                         ; Print string at EBX
  mov   ebx,NewLine                   ; Put
  call  PutStr                        ;  a New Line
    
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
String  Msg7,"PIT Configured"
String  Msg8,"Timer IDT Set"
String  Msg9,"Keyboard IDT Set"
String  FaultMsg,"------   FAULT: System Halted   ------"
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

;--------------------------------------------------------------------------------------------------
; Global Descriptor Table (GDT) for Kernel
;--------------------------------------------------------------------------------------------------
segment .data
align 8

GDTTable:
    dq 0x0000000000000000       ; Null descriptor (selector 0x00)
    dq 0x00CF9A000000FFFF       ; Code segment (selector 0x08)
    dq 0x00CF92000000FFFF       ; Data segment (selector 0x10)
GDTTableEnd:

GDTDescriptor:
    dw GDTTableEnd - GDTTable - 1   ; Limit = size of GDT - 1 (should be 23 bytes)
    dd 0x00100808                   ; Base = linear address of GDTTable (1MB + offset)