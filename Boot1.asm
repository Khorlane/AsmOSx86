;**************************************************************************************************
; Boot1.asm - Stage 1 Boot Loader
;   A simple boot sector that:
;   1. is exactly 512 bytes long
;   2. has the Magic Word at the end (0xAA55)
;   3. reads the AsmOSx86 file manifest
;   4. loads Boot2 from its manifest sector range
;   5. transfers control to Boot2 at 0050:0000
;
; nasm -f bin Boot1.asm -o Boot1.bin -l Boot1.lst
;**************************************************************************************************

[bits 16]                               ; we are in 16 bit real mode
    org   0                             ; we will set registers later
    jmp   Booter                        ; jump to start of bootloader

;--------------------------------------------------------------------------------------------------
; Boot Sector Header
;   The boot code no longer treats the image as FAT12. This header remains a
;   BIOS-friendly 1.44MB floppy description while sector 1 contains the
;   AsmOSx86 file manifest.
;--------------------------------------------------------------------------------------------------

                                        ; Hex Offset from beginning of Boot Sector
OEM                   db "AsmOSx86"     ; 0x003  8 bytes padded with spaces
BytesPerSector        dw 512            ; 0x00B  2 bytes
SectorsPerCluster     db 1              ; 0x00D  1 byte
ReservedSectors       dw 1              ; 0x00E  2 bytes
NumberOfFATs          db 2              ; 0x010  1 bytes
RootEntries           dw 224            ; 0x011  2 bytes
TotalSectors          dw 2880           ; 0x013  2 bytes
Media                 db 0f0h           ; 0x015  1 byte
SectorsPerFAT         dw 9              ; 0x016  2 bytes
SectorsPerTrack       dw 18             ; 0x018  2 bytes DOS 3.31 BPB
HeadsPerCylinder      dw 2              ; 0x01A  2 bytes DOS 3.31 BPB
HiddenSectors         dd 0              ; 0x01C  4 bytes DOS 3.31 BPB
TotalSectorsBig       dd 0              ; 0x020  4 bytes DOS 3.31 BPB
DriveNumber           db 0              ; 0x024  1 byte  Extended BIOS Parameter Block
Unused                db 0              ; 0x025  1 byte  Extended BIOS Parameter Block
ExtBootSignature      db 029h           ; 0x026  1 byte  Extended BIOS Parameter Block
SerialNumber          dd 0a0a1a2a3h     ; 0x027  4 bytes Extended BIOS Parameter Block
VolumeLabel           db "AsmOSx86   "  ; 0x028 11 bytes Extended BIOS Parameter Block
FileSystem            db "ASMFS   "     ; 0x036  8 bytes Extended BIOS Parameter Block padded with spaces

;--------------------------------------------------------------------------------------------------
; Prints a string
; DS => SI: 0 terminated string
;--------------------------------------------------------------------------------------------------
Print:
    mov   ah,0Eh                        ; BIOS INT 10h teletype output
PrintLoop:
    lodsb                               ; Load byte at DS:SI into AL
    or    al,al                         ; If AL = 0
    jz    PrintDone                     ;  then we're done
    int   10h                           ; Put character on the screen
    jmp   PrintLoop                     ; Repeat until null terminator found
PrintDone:
    ret

;--------------------------------------------------------------------------------------------------
; Convert LBA to CHS
; AX => LBA Address to convert
;--------------------------------------------------------------------------------------------------
LBACHS:
    xor   dx,dx                         ; DL = Remainder of
    div   word [SectorsPerTrack]        ;  AX / SectorsPerTrack
    inc   dl                            ;   Plus 1
    mov   byte [AbsoluteSector],dl      ;    Save DL
    xor   dx,dx                         ; DL = Remainder of
    div   word [HeadsPerCylinder]       ;  AX / HeadsPerCylinder
    mov   byte [AbsoluteHead],dl        ;   Save DL
    mov   byte [AbsoluteTrack],al       ; Save AL
    ret

;--------------------------------------------------------------------------------------------------
; Reads a series of sectors
; CX    => Number of sectors to read
; AX    => Starting sector
; ES:BX => Buffer to read to
;--------------------------------------------------------------------------------------------------
ReadSector:
    mov   di,0005h                      ; five retries for error
ReadSectorLoop:
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
    jnc   ReadSectorOk                  ; test for read error
    xor   ax,ax                         ; BIOS reset disk
    int   13h                           ; invoke BIOS
    dec   di                            ; decrement error counter
    pop   cx
    pop   bx
    pop   ax
    jnz   ReadSectorLoop                ; attempt to read again
    int   18h
ReadSectorOk:
    mov   si,ProgressMsg
    call  Print
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
    cli                                 ; Disable interrupts, we don't need them yet
    mov   ax,07C0h                      ; setup
    mov   ds,ax                         ;  registers
    mov   es,ax                         ;   to point
    mov   fs,ax                         ;    to our
    mov   gs,ax                         ;     segment
    mov   [DriveNumber],dl              ; BIOS boot drive
    mov   ax,0000h                      ; set the
    mov   ss,ax                         ;  stack to
    mov   sp,0FFFFh                     ;   somewhere safe
    mov   si,LoadingMsg                 ; print stage message
    call  Print
    mov   ax,07C0h                      ; read manifest
    mov   es,ax                         ;  to 07C0:0200
    mov   bx,MANIFEST_OFFSET
    mov   ax,MANIFEST_SECTOR
    mov   cx,1
    call  ReadSector
    cmp   dword[MANIFEST_OFFSET],MANIFEST_SIGNATURE
    jne   BooterFailed
    mov   di,MANIFEST_OFFSET+MANIFEST_ENTRY_OFFSET
    mov   cx,[MANIFEST_OFFSET+MANIFEST_ENTRY_COUNT]
BooterFindBoot2:
    mov   [ManifestEntryPtr],di
    mov   si,Boot2Name
    mov   dx,11
BooterFindBoot2Cmp:
    mov   al,[si]
    cmp   al,[di]
    jne   BooterFindBoot2Next
    inc   si
    inc   di
    dec   dx
    jnz   BooterFindBoot2Cmp
    mov   di,[ManifestEntryPtr]
    mov   ax,[di+MANIFEST_ENTRY_START_SECTOR]
    mov   [Boot2StartSector],ax
    mov   ax,[di+MANIFEST_ENTRY_SECTOR_COUNT]
    mov   [Boot2SectorCount],ax
    test  ax,ax
    jz    BooterFailed
    jmp   BooterLoadBoot2
BooterFindBoot2Next:
    mov   di,[ManifestEntryPtr]
    add   di,MANIFEST_ENTRY_SIZE
    loop  BooterFindBoot2
BooterFailed:
    mov   si,FailureMsg
    call  Print
    int   18h
BooterLoadBoot2:
    mov   ax,BOOT2_LOAD_SEGMENT         ; load Boot2
    mov   es,ax                         ;  at 0050:0000
    xor   bx,bx
    mov   ax,[Boot2StartSector]         ; manifest disk sector
    mov   cx,[Boot2SectorCount]         ; manifest read count
    call  ReadSector
    mov   si,Stage2Msg                  ; print jump message
    call  Print
    mov   ah,00h                        ; wait
    int   16h                           ;  for keypress
    mov   si,NewLineMsg                 ; print
    call  Print                         ;  new line
    push  word BOOT2_LOAD_SEGMENT       ; Jump to Boot2 at 0050:0000
    push  word 0000h
    retf

;--------------------------------------------------------------------------------------------------
; Working Storage
;--------------------------------------------------------------------------------------------------
BOOT2_LOAD_SEGMENT   equ 0050h
MANIFEST_SECTOR      equ 1
MANIFEST_OFFSET      equ 0200h
MANIFEST_SIGNATURE   equ 464D5341h
MANIFEST_ENTRY_COUNT equ 6
MANIFEST_ENTRY_OFFSET equ 16
MANIFEST_ENTRY_SIZE  equ 32
MANIFEST_ENTRY_START_SECTOR equ 12
MANIFEST_ENTRY_SECTOR_COUNT equ 20

AbsoluteHead         db 00h
AbsoluteSector       db 00h
AbsoluteTrack        db 00h
Boot2Name            db "BOOT2   BIN"
Boot2StartSector     dw 0
Boot2SectorCount     dw 0
ManifestEntryPtr     dw 0
FailureMsg           db 0Dh,0Ah,"*** FATAL: BOOT2.BIN not found",00h
LoadingMsg           db 0Dh,0Ah,"AsmOSx86 v0.0.2a Stage 1",00h
NewLineMsg           db 0Dh,0Ah,00h
ProgressMsg          db ".",00h
Stage2Msg            db 0Dh,0Ah," Hit Enter, Jump to Stage 2 ",00h

;--------------------------------------------------------------------------------------------------
; Make it a Boot Sector! (must be exactly 512 bytes)
;--------------------------------------------------------------------------------------------------
    times 510-($-$$)  db 0              ; make boot sector exactly 512 bytes
                      dw 0AA55h         ; Magic Word that makes this a boot sector
