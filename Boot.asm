;**************************************************************************************************
; Boot.asm - AsmOSx86 Single-Stage Boot Loader
;   BIOS responsibility ends after loading sector 0 and transferring control here.
;
;   Boot:
;   1. is exactly 512 bytes long
;   2. uses NO BIOS interrupts
;   3. initializes enough floppy-controller hardware to read sectors directly
;   4. reads the AsmOSx86 manifest from sector 1
;   5. finds and loads KERNEL.BIN to 00100000h
;   6. enables A20
;   7. installs a minimal GDT and enters 32-bit protected mode
;   8. transfers control directly to the kernel
;
; nasm -f bin Boot.asm -o Boot.bin -l Boot.lst
;
; NOTE:
;   This is intentionally a minimal first-pass loader aimed at Bochs/PC-compatible
;   floppy hardware. It is not yet a production-quality floppy driver.
;**************************************************************************************************

[bits 16]
    org   07C00h

    jmp   Booter

;--------------------------------------------------------------------------------------------------
; Boot Loader Entry Point
;--------------------------------------------------------------------------------------------------
Booter:
    cli
    xor   ax,ax
    mov   ds,ax
    mov   ss,ax
    mov   sp,07C00h
    cld

    ; Install our own IRQ6 handler at real-mode vector 0Eh.
    mov   word [0038h],FdcIrq
    mov   [003Ah],ax

    ; Mask every master-PIC IRQ except IRQ6.
    mov   al,0BFh
    out   021h,al

    call  FdcInit

    ; Read ASMF manifest sector to 0000:0500.
    mov   ax,MANIFEST_SECTOR
    mov   bx,MANIFEST_BUFFER
    call  FloppyRead

    ; Find KERNEL.BIN.
    mov   di,MANIFEST_BUFFER+MANIFEST_ENTRY_OFFSET
    mov   dx,[MANIFEST_BUFFER+MANIFEST_ENTRY_COUNT]
BootFind:
    mov   bp,di
    mov   si,KernelName
    mov   cx,11
    repe  cmpsb
    je    BootFound
    mov   di,bp
    add   di,MANIFEST_ENTRY_SIZE
    dec   dx
    jnz   BootFind
    jmp   BootFail

BootFound:
    mov   di,bp
    mov   si,[di+MANIFEST_ENTRY_START_SECTOR]
    mov   bp,[di+MANIFEST_ENTRY_SECTOR_COUNT]

    ; Fast A20 gate before loading the kernel above 1 MB.
    in    al,092h
    or    al,00000010b
    and   al,11111110b
    out   092h,al

    ; Load kernel contiguously to physical 00100000h.
    mov   byte [FdcDmaPage],10h
    xor   bx,bx
BootLoad:
    mov   ax,si
    call  FloppyRead
    inc   si
    add   bx,512
    jnc   BootLoad1
    inc   byte [FdcDmaPage]
BootLoad1:
    dec   bp
    jnz   BootLoad

    cli

    lgdt  [GdtDesc]

    mov   eax,cr0
    or    eax,1
    mov   cr0,eax
    jmp   CODE_SEL:Protected

;--------------------------------------------------------------------------------------------------
; Floppy Controller Initialization
;   Controller: primary PC floppy controller
;   Drive:      A:
;   Format:     1.44 MB, 18 sectors/track, 2 heads, 512-byte sectors
;--------------------------------------------------------------------------------------------------
FdcInit:
    mov   byte [FdcDone],0

    ; Reset controller, motor A on, DMA/IRQ enabled.
    mov   dx,03F2h
    xor   al,al
    out   dx,al
    mov   al,01Ch
    out   dx,al

    ; 500 Kbit/s.
    mov   dx,03F7h
    xor   al,al
    out   dx,al

    sti
    call  FdcWaitIrq

    ; Clear reset interrupt state for drive A.
    mov   al,08h
    call  FdcOut
    call  FdcIn
    call  FdcIn

    ; SPECIFY: normal DMA operation.
    mov   al,03h
    call  FdcOut
    mov   al,0DFh
    call  FdcOut
    mov   al,02h
    call  FdcOut
    ret

;--------------------------------------------------------------------------------------------------
; Read one logical 512-byte sector
; AX => LBA
; BX => low 16 bits of physical destination
; FdcDmaPage => high DMA address byte
;--------------------------------------------------------------------------------------------------
FloppyRead:
    ; Convert LBA to C/H/S.
    xor   dx,dx
    mov   cx,18
    div   cx
    inc   dl
    mov   [FdcSector],dl

    xor   dx,dx
    mov   cx,2
    div   cx
    mov   [FdcHead],dl
    mov   [FdcTrack],al

    ; Seek requested cylinder/head.
    mov   byte [FdcDone],0
    mov   al,0Fh
    call  FdcOut
    mov   al,[FdcHead]
    shl   al,2
    call  FdcOut
    mov   al,[FdcTrack]
    call  FdcOut
    call  FdcWaitIrq

    ; Sense interrupt status.
    mov   al,08h
    call  FdcOut
    call  FdcIn
    call  FdcIn

    ; DMA channel 2: device -> memory, 512 bytes.
    mov   al,06h
    out   0Ah,al
    xor   al,al
    out   0Ch,al

    mov   ax,bx
    out   04h,al
    mov   al,ah
    out   04h,al

    mov   al,[FdcDmaPage]
    out   081h,al

    mov   ax,511
    out   05h,al
    mov   al,ah
    out   05h,al

    mov   al,046h
    out   0Bh,al
    mov   al,02h
    out   0Ah,al

    ; READ DATA, MFM, one sector.
    mov   byte [FdcDone],0
    mov   al,046h
    call  FdcOut
    mov   al,[FdcHead]
    shl   al,2
    call  FdcOut
    mov   al,[FdcTrack]
    call  FdcOut
    mov   al,[FdcHead]
    call  FdcOut
    mov   al,[FdcSector]
    call  FdcOut
    mov   al,02h
    call  FdcOut
    mov   al,18
    call  FdcOut
    mov   al,01Bh
    call  FdcOut
    mov   al,0FFh
    call  FdcOut

    call  FdcWaitIrq

    ; Consume seven result bytes. First-pass loader ignores status.
    mov   cx,7
FloppyResult:
    call  FdcIn
    loop  FloppyResult
    ret

;--------------------------------------------------------------------------------------------------
; Floppy byte I/O
;--------------------------------------------------------------------------------------------------
FdcOut:
    push  ax
FdcOutWait:
    mov   dx,03F4h
    in    al,dx
    and   al,0C0h
    cmp   al,080h
    jne   FdcOutWait
    pop   ax
    mov   dx,03F5h
    out   dx,al
    ret

FdcIn:
    mov   dx,03F4h
FdcInWait:
    in    al,dx
    and   al,0C0h
    cmp   al,0C0h
    jne   FdcInWait
    mov   dx,03F5h
    in    al,dx
    ret

FdcWaitIrq:
    cmp   byte [FdcDone],0
    jne   FdcWaitDone
    hlt
    jmp   FdcWaitIrq
FdcWaitDone:
    ret

FdcIrq:
    mov   byte [FdcDone],1
    mov   al,020h
    out   020h,al
    iret

BootFail:
    cli
BootFailLoop:
    hlt
    jmp   BootFailLoop

;--------------------------------------------------------------------------------------------------
; Protected Mode Entry
;--------------------------------------------------------------------------------------------------
[bits 32]
Protected:
    mov   ax,DATA_SEL
    mov   ds,ax
    mov   es,ax
    mov   ss,ax
    mov   esp,00090000h

    jmp   CODE_SEL:KERNEL_BASE

;--------------------------------------------------------------------------------------------------
; Minimal GDT
;--------------------------------------------------------------------------------------------------
align 4
Gdt:
    dq    0
    dw    0FFFFh,0
    db    0,09Ah,0CFh,0
    dw    0FFFFh,0
    db    0,092h,0CFh,0
GdtEnd:

GdtDesc:
    dw    GdtEnd-Gdt-1
    dd    Gdt

;--------------------------------------------------------------------------------------------------
; Constants / Working Storage
;--------------------------------------------------------------------------------------------------
CODE_SEL                    equ 08h
DATA_SEL                    equ 10h

MANIFEST_SECTOR             equ 1
MANIFEST_BUFFER             equ 0500h
MANIFEST_ENTRY_COUNT        equ 6
MANIFEST_ENTRY_OFFSET       equ 16
MANIFEST_ENTRY_SIZE         equ 32
MANIFEST_ENTRY_START_SECTOR equ 12
MANIFEST_ENTRY_SECTOR_COUNT equ 20

KERNEL_BASE                 equ 00100000h

KernelName                  db "KERNEL  BIN"

FdcDone                     db 0
FdcTrack                    db 0
FdcHead                     db 0
FdcSector                   db 0
FdcDmaPage                  db 0

;--------------------------------------------------------------------------------------------------
; Boot signature
;--------------------------------------------------------------------------------------------------
    times 510-($-$$) db 0
    dw    0AA55h
