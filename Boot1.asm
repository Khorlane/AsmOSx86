;**************************************************************************************************
; Boot1.asm - Stage 1 Boot Loader
;   A Simple Boot Sector that:
;   1. is exactly 512 bytes long
;   2. has the Magic Word at the end (0xAA55)
;   3. has code to load our Stage 2 code
;   4. is placed in the 'boot sector' giving us a bootable floppy
;
; nasm -f bin Boot1.asm -o Boot1.bin -l Boot1.lst
;**************************************************************************************************

[bits 16]                               ; we are in 16 bit real mode
    org   0                             ; we will set regisers later
    jmp   Booter                        ; jump to start of bootloader

;--------------------------------------------------------------------------------------------------
; BIOS Parameter Block
;   and yes, this block must start at offset 0x003
;   and yes, these are the required fields
;   and yes, they must be in this order
;   you can change the names (obviously)
;--------------------------------------------------------------------------------------------------

; The BIOS Parameter Block 'must' begin 3 bytes from start.
; The JMP instruction (above) is exacly the required 3 bytes long.

                                        ; Hex Offset from beginning of Boot Sector
OEM                   db "AsmOSx86"     ; 0x003  8 bytes padded with spaces
BytesPerSector        dw 512            ; 0x00B  2 bytes
SectorsPerCluster     db 1              ; 0x00D  1 byte
ReservedSectors       dw 1              ; 0x00E  2 bytes
NumberOfFATs          db 2              ; 0x010  1 bytes
RootEntries           dw 224            ; 0x011  2 bytes
TotalSectors          dw 2880           ; 0x013  2 bytes
Media                 db 0xf0           ; 0x015  1 byte
SectorsPerFAT         dw 9              ; 0x016  2 bytes
SectorsPerTrack       dw 18             ; 0x018  2 bytes DOS 3.31 BPB
HeadsPerCylinder      dw 2              ; 0x01A  2 bytes DOS 3.31 BPB
HiddenSectors         dd 0              ; 0x01C  4 bytes DOS 3.31 BPB
TotalSectorsBig       dd 0              ; 0x020  4 bytes DOS 3.31 BPB
DriveNumber           db 0              ; 0x024  1 byte  Extended BIOS Parameter Block
Unused                db 0              ; 0x025  1 byte  Extended BIOS Parameter Block
ExtBootSignature      db 0x29           ; 0x026  1 byte  Extended BIOS Parameter Block
SerialNumber          dd 0xa0a1a2a3     ; 0x027  4 bytes Extended BIOS Parameter Block
VolumeLabel           db "AsmOSx86   "  ; 0x028 11 bytes Extended BIOS Parameter Block
FileSystem            db "FAT12   "     ; 0x036  8 bytes Extended BIOS Parameter Block padded with spaces

;--------------------------------------------------------------------------------------------------
; Prints a string
; DS => SI: 0 terminated string
;--------------------------------------------------------------------------------------------------
Print:
    mov   ah,0Eh                        ; set function code 0E (BIOS INT 10h - Teletype output) 
PrintLoop:
    LODSB                               ; Load byte at address DS:(E)SI into AL
    or    al,al                         ; If AL = 0
    jz    PrintDone                     ;   then we're done
    int   10h                           ; Put character on the screen using bios interrupt 10
    jmp   PrintLoop                     ; Repeat until null terminator found
  PrintDone:
    ret                                 ; we are done, so return

;--------------------------------------------------------------------------------------------------
; Convert CHS to LBA
; Given: AX = Cluster to be read
; LBA = (Cluster - 2) * sectors per cluster
;--------------------------------------------------------------------------------------------------
ClusterLBA:
    sub   ax,0x0002                     ; Adjust cluster to be zero based
    xor   cx,cx                         ; CX =
    mov   cl,byte [SectorsPerCluster]   ;  SectorsPerCluster
    mul   cx                            ; AX = AX * CX
    add   ax,word [DataSector]          ; AX = AX + Data Sector
    ret

;--------------------------------------------------------------------------------------------------
; Convert LBA to CHS
; AX => LBA Address to convert
; absolute sector = (LBA %  sectors per track) + 1
; absolute head   = (LBA /  sectors per track) MOD number of heads
; absolute track  =  LBA / (sectors per track * number of heads)
;--------------------------------------------------------------------------------------------------
LBACHS:
    xor   dx,dx                         ; DL = Remainder of
    div   word [SectorsPerTrack]        ;  AX \ SectorsPerTrack
    inc   dl                            ;   Plus 1
    mov   byte [AbsoluteSector],DL      ;    Save DL 
    xor   dx,dx                         ; DL = Remainder of
    div   word [HeadsPerCylinder]       ;  AX \ HeadsPerCylinder
    mov   byte [AbsoluteHead],DL        ;   Save DL
    mov   byte [AbsoluteTrack],AL       ; Save AL (what's left after the above dividing)
    ret

;--------------------------------------------------------------------------------------------------
; Reads a series of sectors
; CX    => Number of sectors to read
; AX    => Starting sector
; ES:BX => Buffer to read to
;--------------------------------------------------------------------------------------------------
ReadSector:
    mov   di,0x0005                     ; five retries for error
ReadSectorLoop:
    push  ax
    push  bx
    push  cx
    call  LBACHS                        ; convert starting sector to CHS
    mov   ah,0x02                       ; BIOS read sector
    mov   al,0x01                       ; read one sector
    mov   ch,byte [AbsoluteTrack]       ; track
    mov   cl,byte [AbsoluteSector]      ; sector
    mov   dh,byte [AbsoluteHead]        ; head
    mov   dl,byte [DriveNumber]         ; drive
    int   0x13                          ; invoke BIOS
    jnc   ReadSectorOk                  ; test for read error
    xor   ax,ax                         ; BIOS reset disk
    int   0x13                          ; invoke BIOS
    dec   di                            ; decrement error counter
    pop   cx
    pop   bx
    pop   ax
    jnz   ReadSectorLoop                ; attempt to read again
    int   0x18
ReadSectorOk:
    mov   si,ProgressMsg
    call  Print                         ;
    pop   cx
    pop   bx
    pop   ax
    add   bx,word [BytesPerSector]      ; queue next buffer
    inc   ax                            ; queue next sector
    loop  ReadSector                    ; read next sector
    ret

;--------------------------------------------------------------------------------------------------
; Boot Loader Entry Point
;--------------------------------------------------------------------------------------------------
Booter:
    ;-------------------------------------------------------
    ;- code located at 0000:7C00, adjust segment registers
    ;-------------------------------------------------------
    cli                                 ; Disable interrupts, we don't need them yet
    mov   ax,0x07C0                     ; setup
    mov   ds,ax                         ;  registers
    mov   es,ax                         ;   to point
    mov   fs,ax                         ;    to our
    mov   gs,ax                         ;     segment

    ;--------------
    ;- create stack
    ;--------------
    mov   ax,0x0000                     ; set the
    mov   ss,ax                         ;  stack to
    mov   sp,0xFFFF                     ;   somewhere safe

    ;-------------------------
    ;- Display loading message
    ;-------------------------
    mov   si,LoadingMsg                 ; si points to first byte in message
    call  Print                         ; print message

    ;--------------------------
    ; Load root directory table  
    ;--------------------------
    ; compute size of root directory and store in "cx"
    xor   cx,cx                         ; zero out cx
    xor   dx,dx                         ; zero out dx
    mov   ax,0x0020                     ; 32 byte directory entry
    mul   word [RootEntries]            ; total size of directory
    div   word [BytesPerSector]         ; sectors used by directory
    xchg  ax,cx                         ; swap ax cx
    ; compute location of root directory and store in "ax"
    mov   al,byte [NumberOfFATs]        ; number of FATs
    mul   word [SectorsPerFAT]          ; sectors used by FATs
    add   ax,word [ReservedSectors]     ; adjust for bootsector
    mov   word [DataSector],AX          ; base of root directory
    add   word [DataSector],CX
    ; read root directory into memory (7C00:0200)
    mov   bx,0x0200                     ; read root dir
    call  ReadSector                    ;  above bootcode

    ;------------------------------------
    ; Find Stage 2 file in Root Directory
    ;------------------------------------
    mov   cx,word [RootEntries]         ; load loop counter
    mov   di,0x0200                     ; locate first root entry
FindFat:
    push  cx                            ; save loop counter on the stack
    mov   cx,0x000B                     ; eleven character name
    mov   si,Stage2Name                 ; Stage2 file name to find
    push  di
    rep   cmpsb                         ; test for entry match
    pop   di
    je    LoadFat                       ; found our file, now load it
    pop   cx                            ; pop our loop counter
    add   di,0x0020                     ; queue next directory entry
    loop  FindFat                       ; keep looking
    jmp   FindFatFailed                 ; file not found, this is bad!

    ;--------------------------
    ; Load FAT
    ;--------------------------
LoadFat:
    ; save starting cluster of boot image
    mov   dx,word [DI + 0x001A]         ; save file's
    mov   word [Cluster],DX             ;  first cluster

    ; compute size of FAT and store in "cx"
    xor   ax,ax
    mov   al,byte [NumberOfFATs]        ; number of FATs
    mul   word [SectorsPerFAT]          ; sectors used by FATs
    mov   cx,ax

    ; compute location of FAT and store in "ax"
    mov   ax,word [ReservedSectors]     ; adjust for bootsector

    ; read FAT into memory (7C00:0200)
    mov   bx,0x0200                     ; read FAT
    call  ReadSector                    ;  into memory above our bootcode

;--------------------------------------------------------------------------------------------------
; Load Stage 2
;--------------------------------------------------------------------------------------------------
    ; read Stage2 file into memory (0050:0000)
    mov   ax,0x0050                     ; set segment register
    mov   es,ax                         ;  to 50h
    mov   bx,0x0000                     ; push our starting address (0h)
    push  bx                            ;  onto the stack

LoadStage2:
    mov   ax,word [Cluster]             ; cluster to read
    pop   bx                            ; buffer to read into
    call  ClusterLBA                    ; convert cluster to LBA
    xor   cx,cx                         ; CL =
    mov   cl,byte [SectorsPerCluster]   ;  sectors to read
    call  ReadSector                    ; read a sector
    push  bx                            ; push buffer ptr to stack

    ; compute next cluster
    mov   ax,word [Cluster]             ; identify current cluster
    mov   cx,ax                         ; copy current cluster
    mov   dx,ax                         ; copy current cluster
    shr   dx,0x0001                     ; divide by two
    add   cx,dx                         ; sum for (3/2)
    mov   bx,0x0200                     ; location of FAT in memory
    add   bx,cx                         ; index into FAT
    mov   dx,word [BX]                  ; read two bytes from FAT, indexed by BX
    test  ax,0x0001                     ; test under mask, if cluster number is odd
    jnz   LoadStage2OddCluster          ;  then process Odd Cluster

LoadStage2EvenCluster:
    and   dx,0000111111111111b          ; take low  twelve bits DX x'ABCD' -> x'0BCD'
    jmp   LoadStage2CheckDone

LoadStage2OddCluster:
    shr   dx,0x0004                     ; take high twelve bits DX x'ABCD' -> x'0ABC'

LoadStage2CheckDone:
    mov   word [Cluster],DX             ; store new cluster
    cmp   dx,0x0FF0                     ; If DX is less than EOF (0x0FF0)
    jb    LoadStage2                    ;   then keep going (JB = Jump Below)

;--------------------------------------------------------------------------------------------------
; Jump to Stage 2 code
;--------------------------------------------------------------------------------------------------
    mov   si,Stage2Msg                  ; si points to first byte in message
    call  Print                         ; print message
    mov   ah,0X00                       ; wait
    INT   0x16                          ;  for keypress
    mov   si,NewLineMsg                 ; print
    CALL  Print                         ;  new line
    push  word 0x0050                   ; Jump to our Stage 2 code that we put at 0050:0000
    push  word 0x0000                   ;   by using a Far Return which pops IP(0h) then CS(50h)
    retf                                ;   and poof, we're executing our Stage 2 code!

;--------------------------------------------------------------------------------------------------
; Failed to find FAT (File Allocation Table)
;--------------------------------------------------------------------------------------------------
FindFatFailed:
    mov   si,FailureMsg                 ; print
    call  Print                         ;  failure message
    mov   ah,0x00                       ; wait for
    int   0x16                          ;  keypress
    int   0x19                          ; warm boot computer

;--------------------------------------------------------------------------------------------------
; Working Storage
;--------------------------------------------------------------------------------------------------
    AbsoluteHead      db 0x00
    AbsoluteSector    db 0x00
    AbsoluteTrack     db 0x00
    Cluster           dw 0x0000
    DataSector        dw 0x0000
    FailureMsg        db 0x0D, 0x0A, "MISSING BOOT2.BIN", 0x0D, 0x0A, 0x00
    LoadingMsg        db 0x0D, 0x0A, "AsmOSx86 v0.0.2 Stage 1", 0x00
    NewLineMsg        db 0x0D, 0x0A, 0x00
    ProgressMsg       db ".", 0x00
    Stage2Msg         db 0x0D, 0x0A, " Hit Enter, Jump to Stage 2 ", 0x00
    Stage2Name        db "BOOT2   BIN"

;--------------------------------------------------------------------------------------------------
; Make it a Boot Sector! (must be exactly 512 bytes)
;--------------------------------------------------------------------------------------------------
    TIMES 510-($-$$)  db 0              ; make boot sector exactly 512 bytes
                      dw 0xAA55         ; Magic Word that makes this a boot sector