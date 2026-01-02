;**********************************************************
; Boot2.asm - Stage 2 Boot Loader
;   A kernel loader that:
;   1. installs Global Descriptor Table (GDT)
;   2. enables the A20 line
;   3. load the kernel from floppy into low memory
;   4. switch to x86 Protected Mode
;   5. switch from 16 bit to 32 bit addressing
;   5. copy kernel to high memory
;   6. jump to kernel
;
; nasm -f bin Boot2.asm -o Boot2.bin -l Boot2.lst
;**********************************************************

; Remember the memory map-- 500h through 7BFFh is unused above the BIOS data area.
; We are loaded at 500h (50h:0h)
[bits 16]
    org   0500h
    jmp   Main                          ; jump to Main

;--------------------------------------------------------------------------------------------------
; Prints a null terminated string using BIOS call
; DS => SI: null terminated string
;--------------------------------------------------------------------------------------------------
[bits 16]
PutStr:
    pusha                               ; save registers
    mov   ah,0Eh                        ; write text in teletype mode
PutStr1:
    lodsb                               ; load next byte from string from SI to AL
    or    al,al                         ; Does AL=0?
    jz    PutStr2                       ; Yep, null terminator found-bail out
    int   10h                           ; invoke BIOS to print 1 character
    jmp   PutStr1                       ; Repeat until null terminator found
PutStr2:
    popa                                ; restore registers
    ret                                 ; we are done, so return

;--------------------------------------------------------------------------------------------------
; Install our GDT
;--------------------------------------------------------------------------------------------------
[bits 16]
InstallGDT:
    pusha                               ; save registers
    lgdt  [GDT2]                        ; load GDT into GDTR
    popa                                ; restore registers
    ret                                 ; All done!

;--------------------------------------------------------------------------------------------------
; Enable A20 line through output port
;--------------------------------------------------------------------------------------------------
[bits 16]
EnableA20:
    pusha

    call  WaitInput                     ; wait for keypress
    mov   al,0ADh
    out   64h,al                        ; disable keyboard
    call  WaitInput                    

    mov   al,0D0h
    out   64h,al                        ; tell controller to read output port
    call  WaitOutput                   

    in    al,60h
    push  ax                            ; get output port data and store it
    call  WaitInput                    

    mov   al,0D1h
    out   64h,al                        ; tell controller to write output port
    call  WaitInput                    

    pop   ax
    or    al,2                          ; set bit 1 (enable a20)
    out   60h,al                        ; write out data back to the output port

    call  WaitInput                    
    mov   al,0AEh                       ; enable keyboard
    out   64h,al

    call  WaitInput                     ; wait for keypress
    popa
    ret

;------------------------------
; Helper routines for EnableA20
;------------------------------
WaitInput:
    in    al,64h                        ; wait for
    test  al,2                          ;  input buffer
    jnz   WaitInput                     ;   to clear
    ret

WaitOutput:
    in    al,64h                        ; wait for
    test  al,1                          ;  output buffer
    jz    WaitOutput                    ;   to clear
    ret

;--------------------------------------------------------------------------------------------------
; Floppy Driver Routines
;--------------------------------------------------------------------------------------------------
;------------------------------------------
; Convert CHS to LBA
; LBA = (cluster - 2) * sectors per cluster
;------------------------------------------
[bits 16]
ClusterLBA:
    sub   ax,0002h                      ; zero base cluster number
    xor   cx,cx
    mov   cl,byte [SectorsPerCluster]   ; convert byte to word
    mul   cx
    add   ax,word [DataSector]          ; base data sector
    ret

;---------------------------------------------------------------------------
; Convert LBA to CHS
; AX = LBA Address to convert
;
; absolute sector = (logical sector / sectors per track) + 1
; absolute head   = (logical sector / sectors per track) MOD number of heads
; absolute track  = logical sector / (sectors per track * number of heads)
;---------------------------------------------------------------------------
[bits 16]
LBACHS:                                 ;
    xor   dx,dx                         ; prepare dx:ax for operation
    div   word [SectorsPerTrack]        ; calculate
    inc   dl                            ; adjust for sector 0
    mov   byte [AbsoluteSector],dl
    xor   dx,dx                         ; prepare dx:ax for operation
    div   word [HeadsPerCylinder]       ; calculate
    mov   byte [AbsoluteHead],dl
    mov   byte [AbsoluteTrack],al
    ret

;-----------------------------------
; Read a series of sectors
; CX     = Number of sectors to read
; AX     = Starting sector
; ES:EBX = Buffer
;-----------------------------------
[bits 16]
ReadSector:
    mov   di,0005h                      ; five retries for error
ReadSector1:
    push  ax
    push  bx
    push  cx
    call  LBACHS                        ; convert starting sector to CHS
    mov   ah,02h                        ; BIOS read sector
    mov   al,01h                        ; read one sector
    mov   ch,byte [AbsoluteTrack]       ; track
    mov   cl,byte [AbsoluteSector]      ; sector
    mov   dh,byte [AbsoluteHead]        ; head
    mov   dl,byte [DriveNumber]         ; drive
    int   13h                           ; invoke BIOS
    jnc   ReadSector2                   ; test for read error
    xor   ax,ax                         ; BIOS reset disk
    int   13h                           ; invoke BIOS
    dec   di                            ; decrement error counter
    pop   cx
    pop   bx
    pop   ax
    jnz   ReadSector1                   ; attempt to read again
    int   18h
ReadSector2:
    pop   cx
    pop   bx
    pop   ax
    add   bx,word [BytesPerSector]      ; queue next buffer
    inc   ax                            ; queue next sector
    loop  ReadSector                    ; read next sector
    ret

;------------------------------------
; Load Root Directory Table to 07E00h
;------------------------------------
[bits 16]
LoadRootDir:
    pusha                               ; store registers
    push  es
    ; compute size of root directory and store in "CX"
    xor   cx,cx                         ; clear registers
    xor   dx,dx
    mov   ax,32                         ; 32 byte directory entry
    mul   word [RootEntries]            ; total size of directory
    div   word [BytesPerSector]         ; sectors used by directory
    xchg  ax,cx                         ; move into AX
    ; compute location of root directory and store in "AX"
    mov   al,byte [NumberOfFATs]        ; number of FATs
    mul   word [SectorsPerFAT]          ; sectors used by FATs
    add   ax,word [ReservedSectors]
    mov   word [DataSector],ax          ; base of root directory
    add   word [DataSector],cx
    ; read root directory into 07E00h
    push  word RootSegment
    pop   es
    mov   bx,0                          ; copy root dir
    call  ReadSector                    ; read in directory table
    pop   es
    popa                                ; restore registers and return
    ret

;-----------------------------
; Loads FAT table to 07C00h
; ES:DI = Root Directory Table
;-----------------------------
[bits 16]
LoadFAT:
    pusha                               ; store registers
    push  es
    ; compute size of FAT and store in "CX"
    xor   ax,ax
    mov   al,byte [NumberOfFATs]        ; number of FATs
    mul   word [SectorsPerFAT]          ; sectors used by FATs
    mov   cx,ax
    ; compute location of FAT and store in "ax"
    mov   ax,word [ReservedSectors]
    ; read FAT into memory (Overwrite our bootloader at 07C00h)
    push  word FatSegment
    pop   es
    xor   bx,bx
    call  ReadSector 
    pop   es
    popa                                ; restore registers and return
    ret

;----------------------------------------------------------------
; Search for filename in root table
; parm DS:SI = File name
; ret  AX    = File index number in directory table. -1 if error
;----------------------------------------------------------------
[bits 16]
FindFile:
    push  cx                            ; store registers
    push  dx
    push  bx
    mov   bx,si                         ; copy filename for later
    ; browse root directory for binary image
    mov   cx,word [RootEntries]         ; load loop counter
    mov   di,RootOffset                 ; locate first root entry at 1 MB mark
    cld                                 ; clear direction flag
FindFile1:
    push  cx
    mov   cx,11                         ; eleven character name. Image name is in SI
    mov   si,bx                         ; image name is in BX
    push  di
    rep   cmpsb                         ; test for entry match
    pop   di
    je    FindFile2
    pop   cx
    add   di,32                         ; queue next directory entry
    loop  FindFile1
    ; Not Found
    pop   bx                            ; restore registers and return
    pop   dx
    pop   cx
    mov   ax,-1                         ; set error code
    ret
FindFile2:
    pop   ax                            ; return value into AX contains entry of file
    pop   bx                            ; restore registers and return
    pop   dx
    pop   cx
    ret

;-----------------------------------------
; Load file
; parm ES:SI  = File to load
; parm EBX:BP = Buffer to load file to
; ret  AX     = -1 on error, 0 on success
; ret  CX     = number of sectors read
;-----------------------------------------
[bits 16]
LoadFile:
    xor   cx,cx                         ; size of file in sectors
    push  cx
    push  bx                            ; BX => BP points to buffer to write to; store it for later
    push  bp
    call  FindFile                      ; find our file. ES:SI contains our filename
    cmp   ax,-1
    jne   LoadFile1
    ; failed to find file
    pop   bp
    pop   bx
    pop   cx
    mov   ax,-1
    ret
LoadFile1:
    sub   di,RootOffset
    sub   ax,RootOffset
    ; get starting cluster
    push  word RootSegment              ; root segment loc
    pop   es
    mov   dx,word [es:di + 0001Ah]      ; DI points to file entry in root directory table. Refrence the table...
    mov   word [Cluster],dx             ; file's first cluster
    pop   bx                            ; get location to write to so we dont screw up the stack
    pop   es
    push  bx                            ; store location for later again
    push  es
    call  LoadFAT
LoadFile2:
    ; load the cluster
    mov   ax,word [Cluster]             ; cluster to read
    pop   es                            ; bx:bp=es:bx
    pop   bx
    call  ClusterLBA
    xor   cx,cx
    mov   cl,byte [SectorsPerCluster]
    call  ReadSector 
    pop   cx
    inc   cx                            ; add one more sector to counter
    push  cx
    push  bx
    push  es
    mov   ax,FatSegment                 ;start reading from fat
    mov   es,ax
    xor   bx,bx
    ; get next cluster
    mov   ax,word [Cluster]             ; identify current cluster
    mov   cx,ax                         ; copy current cluster
    mov   dx,ax
    shr   dx,0001h                      ; divide by two
    add   cx,dx                         ; sum for (3/2)
    mov   bx,0                          ; location of fat in memory
    add   bx,cx
    mov   dx,word [es:bx]
    test  ax,0001h                      ; test for odd or even cluster
    jnz   LoadFile3
    and   dx,0000111111111111b          ; Even cluster - take low 12 bits
    jmp   LoadFile4
LoadFile3:
    shr   dx,0004h                      ; Odd cluster  - take high 12 bits
LoadFile4:
    mov   word [Cluster],dx
    cmp   dx,0FF0h                      ; test for end of file marker
    jb    LoadFile2
    ; We're done
    pop   es
    pop   bx
    pop   cx
    xor   ax,ax
    ret

;--------------------------------------------------------------------------------------------------
; Stage 2 Entry Point
; - Set Data segment registers and stack
; - Install GDT
; - Enable A20
; - Read Kernel.bin into memory
; - Protected mode (pmode)
;--------------------------------------------------------------------------------------------------
[bits 16]
Main:
    ;----------------------------
    ; Set Data Segement registers
    ;----------------------------
    cli                                 ; disable interrupts and never re-enable until pmode
    xor   ax,ax                         ; null segments
    mov   ds,ax
    mov   es,ax

    ;-----------------
    ; Set up our Stack
    ;-----------------
    mov   ax,00h                        ; stack begins at 09000h-0FFFFh
    mov   SS,ax
    mov   SP,0FFFFh

    ;----------------
    ; Install our GDT
    ;----------------
    call  InstallGDT

    ;-----------
    ; Enable A20
    ;-----------
    call  EnableA20

    ;----------------------
    ; Print loading message
    ;----------------------
    mov   si,LoadingMsg
    call  PutStr

    ;----------------------
    ; Initialize filesystem
    ;----------------------
    call  LoadRootDir                   ; Load root directory table

    ;----------------------
    ; Read Stage3 from disk
    ;----------------------
    mov   bx,0                          ; BX:BP points to buffer to load to
    mov   bp,RModeBase
    mov   si,Stage3Name                 ; our file to load
    call  LoadFile
    mov   [Stage3Size],cx               ; save the size of Stage3
    cmp   ax,0                          ; Test for success
    je    GoProtected                   ; yep--onto Stage 3!

    ;------------------
    ; This is very bad!
    ;------------------
    mov   si,FailureMsg                 ; Nope--print error
    call  PutStr                        ;
    mov   ah,0                          ; wait
    int   16h                           ;  for keypress
    int   19h                           ; warm boot computer
    hlt                                 ; If we get here, something really went wrong

GoProtected:
    mov   si,Stage3Msg
    call  PutStr
    mov   ah,00h                        ; wait
    int   16h                           ;  for keypress
    ;--------------
    ; Go into pmode
    ;--------------
    mov   eax,cr0                       ; set bit 0 in cr0--enter pmode
    or    eax,1
    mov   cr0,eax
    jmp   CodeDesc:GoStage3             ; far jump to fix CS. Remember that the code selector is 08h!

  ; Note: Do NOT re-enable interrupts! Doing so will triple fault!
  ; We will adjust this in the Kernel.

;--------------------------------------------------------------------------------------------------
; Get to Stage3 - Our Kernel!
; - Set Data Segment Register
; - Set up our Stack
; - Copy Kernel to address 1 MB
; - Jump to our Kernel!!
;--------------------------------------------------------------------------------------------------
[bits 32]
GoStage3:
    ;----------------------------
    ; Set Data Segement registers
    ;----------------------------
    mov   ax,DataDesc                   ; set data segments to data selector (10h)
    mov   ds,ax
    mov   ss,ax
    mov   es,ax

    ;-----------------
    ; Set up our Stack
    ;-----------------
    mov   esp,90000h                    ; stack begins from 90000h

    ;-------------------
    ; Copy Kernel to 1MB
    ;-------------------
    movzx eax,word [Stage3Size]         ; Stage 3 size in sectors
    movzx ebx,word [BytesPerSector]
    mul   ebx
    mov   ebx,4
    div   ebx
    cld
    mov   esi,RModeBase
    mov   edi,PModeBase
    mov   ecx,eax
    rep   movsd                         ; copy image to its protected mode address

    ;--------------------
    ; Jump to our Kernel!
    ;--------------------
    jmp   CodeDesc:PModeBase            ; jump to our kernel! Note: This assumes Kernel's entry point is at 1 MB

    ;-------------------
    ; We never get here! 
    ;-------------------
    hlt                                 ; halt execution

;--------------------------------------------------------------------------------------------------
; Global Descriptor Table (GDT)
;--------------------------------------------------------------------------------------------------
GDT1:
;----------------
; null descriptor
;----------------
                      dd  0
                      dd  0
NullDesc              equ 0
;----------------
; code descriptor
;----------------
                      dw  0FFFFh        ; limit low
                      dw  0             ; base low
                      db  0             ; base middle
                      db  10011010b     ; access
                      db  11001111b     ; granularity
                      db  0             ; base high
CodeDesc              equ 8h
;----------------
; data descriptor
;----------------
                      dw  0FFFFh        ; limit low
                      dw  0             ; base low
                      db  0             ; base middle
                      db  10010010b     ; access
                      db  11001111b     ; granularity
                      db  0             ; base high
DataDesc              equ 10h
;-------------------
; pointer to our GDT
;-------------------
GDT2:
                      dw  GDT2-GDT1-1   ; limit (Size of GDT)
                      dd  GDT1          ; base of GDT

;--------------------------------------------------------------------------------------------------
; Working Storage
;--------------------------------------------------------------------------------------------------
FatSegment            equ 2C0h
PModeBase             equ 100000h       ; where the kernel is to be loaded to in protected mode
RModeBase             equ 3000h         ; where the kernel is to be loaded to in real mode
RootOffset            equ 2E00h
RootSegment           equ 2E0h

LoadingMsg            db  0Dh
                      db  0Ah
                      db  "AsmOSx86 v0.0.1 Stage 2"
                      db  00h

Stage3Msg             db  0Dh
                      db  0Ah
                      db  " Hit Enter to Jump to Kernel!"
                      db  00h

FailureMsg            db  0Dh
                      db  0Ah
                      db  "*** FATAL: MISSING OR CURRUPT KERNEL.BIN. Press Any Key to Reboot"
                      db  0Dh
                      db  0Ah
                      db  0Ah
                      db  00h


AbsoluteHead          db  00h
AbsoluteSector        db  00h
AbsoluteTrack         db  00h
BytesPerSector        dw  512
Cluster               dw  0000h
DataSector            dw  0000h
DriveNumber           db  0
HeadsPerCylinder      dw  2
Stage3Name            db  "KERNEL  BIN" ; kernel name (Must be 11 bytes)
Stage3Size            dw  0             ; size of kernel image in sectors
NumberOfFATs          db  2
ReservedSectors       dw  1
RootEntries           dw  224
SectorsPerCluster     db  1
SectorsPerFAT         dw  9
SectorsPerTrack       dw  18