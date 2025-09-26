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
  ; Set registers
 	mov		ax,0x10
  mov   ds,ax                         ;  segments to
  mov   ss,ax                         ;  data selector
  mov   es,ax                         ;  (10h)
  mov   esp,90000h                    ; Stack begins from 90000h
  ; Load the GDT
  lea   eax, [GDTDescriptor]          ; Load the address of GDTDescriptor into EAX
  lgdt  [eax]                         ; Load the GDT using the address in EAX
  ; Start it up
  call  BootMsg                       ; Print boot message
  call  InitPic                       ; Initialize PIC
  call  InitPit                       ; Initialize PIT
  call  InitIdt                       ; Initialize IDT
  call  SetTimerIdt                   ; Set Timer IDT
  call  SetKeyboardIdt                ; Set Keyboard IDT
  sti                                 ; Enable interrupts
  mov   dword [SleepTicks],200        ; Sleep for 200 ticks
  call  Sleep                         ; Sleep
  mov   ebx,Msg7                      ; Put
  call  DebugIt                       ;  Msg7

.halt:
  jmp .halt                           ; Infinite loop to prevent return

BootMsg:  
  ; Set colors and clear screen
  mov   al,Black                      ; Background
  mov   [ColorBack],al                ;  color
  mov   al,Purple                     ; Foreground
  mov   [ColorFore],al                ;  color
  call  SetColorAttr                  ; Set color
  call  ClrScr                        ; Clear screen
  ; Print success
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
  ret
    
InitPic:
  mov   al,00010001b                  ; Set ICW1
  out   PIC1_CTRL,al                  ;  Initialize
  out   PIC2_CTRL,al                  ;  8259 PIC
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
  mov   ebx,Msg3                      ; Put
  call  DebugIt                       ;  Msg3
  ret

InitPit:
  ; Configure PIT for 18.2 Hz (default frequency)
  mov   al,00110110b                  ; Set PIT to Mode 3 (Square Wave Generator)
  out   43h,al                        ; Write to PIT control port
  mov   ax,0FFFFh                     ; Divisor for 18.2 Hz (default)
  out   40h,al                        ; Write low byte of divisor
  mov   al,ah                         ; Write high
  out   40h,al                        ;  byte of divisor
  mov   ebx,Msg4                      ; Put
  call  DebugIt                       ;  Msg4
  ret

SetTimerIdt:
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
  mov   ebx,Msg5                      ; Put
  call  DebugIt                       ;  Msg5
  ret

SetKeyboardIdt:
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
  mov   ebx,Msg6                      ; Put
  call  DebugIt                       ;  Msg6
  ret

InitIdt:
  cli                                 ; Disable interrupts during initialization
  mov   edi, IDT1                     ; Set EDI to the start of the IDT
  mov   ecx, 2048                     ; IDT size in bytes
  xor   eax, eax                      ; Clear EAX (used to zero out the IDT)
  rep   stosb                         ; Fill the IDT with zeros (clear all entries)
  ; Set up default entries for all 256 vectors (optional)
  mov   ecx, 256                      ; Number of interrupt vectors
  xor   edx, edx                      ; Clear EDX (used for vector index)
SetDefaultIdtEntry:
  ; Example: Set all entries to point to a default ISR (e.g., DefaultIsr)
  mov   eax, DefaultIsr               ; Address of the default ISR
  mov   [IDT + edx * 8], eax          ; Set ISR address (low 32 bits)
  shr   eax, 16                       ; Get high 16 bits of ISR address
  mov   [IDT + edx * 8 + 6], ax       ; Set ISR address (high 16 bits)
  mov   ax, 0x08                      ; Code segment selector
  mov   [IDT + edx * 8 + 2], ax       ; Set segment selector
  mov   ax, 0x8E00                    ; Access byte: Present, Ring 0, 32-bit interrupt gate
  mov   [IDT + edx * 8 + 4], ax       ; Set access byte
  inc   edx                           ; Increment vector index
  loop  SetDefaultIdtEntry            ; Repeat for all 256 vectors
  lidt  [IDT2]                        ; Load the IDT descriptor into the IDTR
  ret

DefaultIsr:
  cli                                 ; Disable interrupts
  hlt                                 ; Halt the CPU (or handle the interrupt gracefully)
  jmp DefaultIsr                      ; Infinite loop to prevent further execution

DebugIt:
  call  PutStr                        ; Print string at EBX
  mov   ebx,NewLine                   ; Put
  call  PutStr                        ;  a New Line
  ret

Sleep:
  push eax
  push ecx
  mov ecx,[TimerTicks]                ; Get current tick count
  add ecx,[SleepTicks]                ; Target tick count = now + SleepTicks
SleepWait:
  cmp [TimerTicks],ecx                ; Has target tick been reached?
  jae SleepDone                       ; If yes (TimerTicks >= ecx), exit
  hlt                                 ; Halt until next interrupt
  jmp SleepWait                       ; Check again
SleepDone:
  pop ecx
  pop eax
  ret

;--------------------------------------------------------------------------------------------------
; Interrupt Service Routines (ISRs)
;--------------------------------------------------------------------------------------------------
IsrTimer:
  pushad
  inc   dword [TimerTicks]            ; Increment the tick counter
  mov   al,020h                       ; Send EOI - End of Interrupt
  out   PIC1_CTRL,al                  ;  to master PIC
  popad
  iretd

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
String  Msg1,"------   AsmOSx86 v0.0.2   -----"
String  Msg2,"--------  32 Bit Kernel --------"
String  Msg3,"Init PIC"
String  Msg4,"Init PIT"
String  Msg5,"Set IDT - Timer"
String  Msg6,"Set IDT - Keyboard"
String  Msg7,"Timer is ticking..."
String  NewLine,0Ah
String  Buffer,"XXXXXXXX"
String  MsgA,"AsmOSx86 has ended!!"
String  MsgB,"ISR Timer Started"
String  MsgC,"Start clearing keyboard buffer"
String  MsgD,"Finished clearing keyboard buffer"
String  MsgE,"Keyboard IDT Set"

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
align 4
IDT:
IDT1: times 2048 db 0
IDT2:
  dw 2047
  dd IDT1

;--------------------------------------------------------------------------------------------------
; Global Descriptor Table (GDT) for Kernel
;--------------------------------------------------------------------------------------------------
align 8
GDTTable:
  dq 0x0000000000000000       ; Null descriptor (selector 0x00)
  dq 0x00CF9A000000FFFF       ; Code segment (selector 0x08)
  dq 0x00CF92000000FFFF       ; Data segment (selector 0x10)
GDTTableEnd:
GDTDescriptor:
  dw GDTTableEnd - GDTTable - 1   ; Limit = size of GDT - 1 (should be 23 bytes)
  dd 0x00100808                   ; Base = linear address of GDTTable (1MB + offset)