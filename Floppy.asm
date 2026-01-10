;**************************************************************************************************
; Floppy.asm
;   Minimal floppy driver (FAT12 target, 1.44MB, 82077/NEC FDC compatible)
;   PROTECTED MODE, NO BIOS, NO IRQ/DMA — motor control only (for now)
;   Routines exported:
;     FloppyInit        ; optional: set defaults (drive A), controller enabled
;     FloppySetDrive    ; optional: change selected drive 0..3
;     FloppyMotorOn     ; enable motor for selected drive (busy-wait spinup)
;     FloppyMotorOff    ; disable motor for selected drive
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; FDC I/O Ports (primary controller @ 0x3F0)
;--------------------------------------------------------------------------------------------------
FDC_BASE        equ 03F0h
FDC_SRA         equ FDC_BASE + 0       ; Status Reg A      (read)
FDC_SRB         equ FDC_BASE + 1       ; Status Reg B      (read)
FDC_DOR         equ FDC_BASE + 2       ; Digital Output    (write, *shadow maintained here*)
FDC_TDR         equ FDC_BASE + 3       ; Tape Drive Reg    (unused)
FDC_MSR         equ FDC_BASE + 4       ; Main Status Reg   (read)
FDC_DSR         equ FDC_BASE + 4       ; Data Rate Select  (write, if needed later)
FDC_DATA        equ FDC_BASE + 5       ; FIFO data         (rw)
FDC_DIR         equ FDC_BASE + 7       ; Digital Input Reg (read)
FDC_CCR         equ FDC_BASE + 7       ; Config Control    (write)

;--------------------------------------------------------------------------------------------------
; DOR bits
;   0..1 : Drive Select (0..3)
;      2 : /RESET (1 = run, 0 = reset controller)
;      3 : DMA/IRQ enable (we don't use IRQ, but 1 is harmless & typical)
;   4..7 : Motor enable for drives 0..3 (bit (4 + drive))
;--------------------------------------------------------------------------------------------------
DOR_SEL_MASK    equ 00000011b
DOR_RESET       equ 00000100b           ; bit2
DOR_DMAIRQ      equ 00001000b           ; bit3

; convenience masks for motors
DOR_MOT_A       equ 00010000b           ; drive 0 (A:)
DOR_MOT_B       equ 00100000b           ; drive 1 (B:)
DOR_MOT_C       equ 01000000b           ; drive 2
DOR_MOT_D       equ 10000000b           ; drive 3

;--------------------------------------------------------------------------------------------------
; Tunables
;--------------------------------------------------------------------------------------------------
; Rough spin-up wait after enabling the motor (in “ticks”).
; This is a very crude busy-wait; you can tune it to your emulator/real HW.
; ~500ms typical spin-up; start with 500 “ms-ish” loops and adjust.
FLOPPY_SPINUP_TICKS  equ 500

;--------------------------------------------------------------------------------------------------
; Variables (kernel .bss/.data style)
;--------------------------------------------------------------------------------------------------
section .data
FlpDorShadow    db 0                    ; we keep a shadow of last DOR write (DOR is write-only)
FlpDrive        db 0                    ; selected drive (0=A, 1=B, 2=C, 3=D)

section .text
;--------------------------------------------------------------------------------------------------
; FloppyInit — select A:, enable controller (out of reset), disable all motors
;--------------------------------------------------------------------------------------------------
FloppyInit:
  pusha
  mov   al,[FlpDrive]                 ; ensure 0..3
  and   al,DOR_SEL_MASK
  or    al,DOR_RESET | DOR_DMAIRQ     ; controller running, (DMA/IRQ enabled = harmless)
  mov   [FlpDorShadow],al
  mov   dx,FDC_DOR
  out   dx,al
  popa
  ret

;--------------------------------------------------------------------------------------------------
; FloppySetDrive — EAX = drive# (0..3). Keeps controller enabled, motors off.
;--------------------------------------------------------------------------------------------------
FloppySetDrive:
  pusha
  mov   eax,[esp+28]                  ; grab caller EAX (pusha saved 8 regs = 32 bytes, EAX is at +28)
  and   al,DOR_SEL_MASK
  mov   [FlpDrive],al
  ; rebuild DOR: keep RESET/DMA bits; clear select bits; clear motors
  mov   bl,[FlpDorShadow]
  and   bl,(DOR_RESET | DOR_DMAIRQ)   ; keep controller-run + dma flag
  or    bl,al                         ; add new select
  mov   [FlpDorShadow],bl
  mov   dx,FDC_DOR
  mov   al,bl
  out   dx,al
  popa
  ret

;--------------------------------------------------------------------------------------------------
; FloppyMotorOn — enable motor bit for selected drive, keep controller running
;   Side-effect: delays ~FLOPPY_SPINUP_TICKS "ms-ish" for spin-up
;--------------------------------------------------------------------------------------------------
FloppyMotorOn:
  pusha
  mov   al,[FlpDrive]                   ; 0..3
  mov   bl,1
  shl   bl,4                            ; BL = 0x10 (A:)
  mov   cl,al                           ; shift count must be in cl
  shl   bl,cl                           ; BL = 0x10 << drive (motor bit)
  mov   bh,bl                           ; Save motor bit in BH
  mov   al,[FlpDorShadow]
  or    al,DOR_RESET | DOR_DMAIRQ
  mov   bl,DOR_SEL_MASK
  not   bl
  and   al,bl
  or    al,[FlpDrive]
  or    al,bh                           ; Add motor bit from BH
  mov   [FlpDorShadow],al
  mov   dx,FDC_DOR
  out   dx,al
  mov   ecx,FLOPPY_SPINUP_TICKS
FloppyMotorOn1:
  call  FlpDelay1ms
  loop  FloppyMotorOn1
  popa
  ret

;--------------------------------------------------------------------------------------------------
; FloppyMotorOff — clear motor bit for selected drive; leave controller running
;--------------------------------------------------------------------------------------------------
FloppyMotorOff:
  pusha
  mov   al,[FlpDrive]                 ; 0..3
  mov   bl,1
  shl   bl,4                          ; BL = 0x10
  mov   cl,al                         ; shift count must be in cl
  shl   bl,cl                         ; BL = 0x10 << drive
  mov   al,[FlpDorShadow]
  not   bl                            ; clear that motor bit only
  and   al,bl
  mov   [FlpDorShadow],al
  mov   dx,FDC_DOR
  out   dx,al
  popa
  ret

;--------------------------------------------------------------------------------------------------
; FlpDelay1ms — very rough ~1ms busy-wait using port 0x80 I/O delays
;   NOTE: purely heuristic; tune the inner loop count if needed.
;--------------------------------------------------------------------------------------------------
FlpDelay1ms:
  push  ecx
  mov   ecx,4000                      ; tweak per machine/emulator to ~1ms
FlpDelay1ms1:
  in    al,80h                        ; tiny I/O delay tick
  loop  FlpDelay1ms1
  pop   ecx
  ret