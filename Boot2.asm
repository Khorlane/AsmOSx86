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
    jmp   Main                          ; Jump to Main

;--------------------------------------------------------------------------------------------------
; Prints a null terminated string using BIOS call
; DS => SI: null terminated string
;--------------------------------------------------------------------------------------------------
[bits 16]
PutStr:
    pusha                               ; Save registers
    mov   ah,0Eh                        ; Write text in teletype mode
PutStr1:
    lodsb                               ; Load next byte from string from SI to AL
    or    al,al                         ; Does AL=0?
    jz    PutStr2                       ; Yep, null terminator found-bail out
    int   10h                           ; Invoke BIOS to print 1 character
    jmp   PutStr1                       ; Repeat until null terminator found
PutStr2:
    popa                                ; Restore registers
    ret                                 ; We are done, so return

;--------------------------------------------------------------------------------------------------
; Install our GDT
;--------------------------------------------------------------------------------------------------
[bits 16]
InstallGDT:
    pusha                               ; Save registers
    lgdt  [GDT2]                        ; Load GDT into GDTR
    popa                                ; Restore registers
    ret                                 ; All done!

;--------------------------------------------------------------------------------------------------
; Enable A20 line of 8042 keyboard controller to access memory above 1 MB
;--------------------------------------------------------------------------------------------------
[bits 16]
EnableA20:
    pusha
    ; Disable the keyboard interface
    call  WaitInput                     ; Ensure that the 8042 input buffer is empty
    mov   al,0ADh                       ; Send 0xAD (Disable Keyboard)
    out   64h,al                        ;  command to 8042 controller command port (0x64)
    ; Instruct the keyboard controller to put its current output port value onto port 0x60
    call  WaitInput                     ; Ensure that the 8042 input buffer is empty
    mov   al,0D0h                       ; Send 0xD0 (Read Output Port and put output port value onto port 60h (0x60))
    out   64h,al                        ;  command to 8042 controller command port (0x64)
    ; Read the current value of the keyboard controller's output port and saving it.
    call  WaitOutput                    ; Ensure value on port 60h is ready to be read
    in    al,60h                        ; Get output port data into register al
    push  ax                            ; Save value by pushing it onto the stack
    ; Instruct the keyboard controller that you are about to write a new value to its output port.
    call  WaitInput                     ; Ensure that the 8042 input buffer is empty
    mov   al,0D1h                       ; Send 0xD1 (Write Output Port from port 60h (0x60))   
    out   64h,al                        ;  command to 8042 controller command port (0x64)
    ; Enable the A20 line
    call  WaitInput                     ; Ensure that the 8042 input buffer is empty
    pop   ax                            ; Get saved output port data from stack
    or    al,2                          ; Flip only bit 1 on (enable A20)
    out   60h,al                        ; Write modified value back to the output port
    ; Re-enable the keyboard interface
    call  WaitInput                     ; Ensure that the 8042 input buffer is empty
    mov   al,0AEh                       ; Send 0xAE (Enable Keyboard)
    out   64h,al                        ;  command to 8042 controller command port (0x64)
    ; The A20 line should now be enabled and we can access memory above 1 MB
    call  WaitInput                     ; Ensure that the 8042 input buffer is empty
    popa
    ret

;------------------------------
; Helper routines for EnableA20
;------------------------------
[bits 16]
WaitInput:
    in    al,64h                        ; Wait for
    test  al,2                          ;  input buffer
    jnz   WaitInput                     ;   to clear
    ret

WaitOutput:
    in    al,64h                        ; Wait for
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
    sub   ax,0002h                      ; Zero base cluster number
    xor   cx,cx                         ; Put Sectors per
    mov   cl,byte [SectorsPerCluster]   ;  cluster in cx
    mul   cx                            ; ax = ax * sectors per cluster  
    add   ax,word [DataSector]          ; ax = ax + data sector
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
    xor   dx,dx                         ; Prepare dx:ax for operation
    div   word [SectorsPerTrack]        ; Calculate
    inc   dl                            ; Adjust for sector 0
    mov   byte [AbsoluteSector],dl
    xor   dx,dx                         ; Prepare dx:ax for operation
    div   word [HeadsPerCylinder]       ; Calculate
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
    mov   di,0005h                      ; Five retries for error
ReadSector1:
    push  ax
    push  bx
    push  cx
    call  LBACHS                        ; Convert starting sector to CHS
    mov   ah,02h                        ; BIOS read sector
    mov   al,01h                        ; Read one sector
    mov   ch,byte [AbsoluteTrack]       ; Track
    mov   cl,byte [AbsoluteSector]      ; Sector
    mov   dh,byte [AbsoluteHead]        ; Head
    mov   dl,byte [DriveNumber]         ; Drive
    int   13h                           ; Invoke BIOS
    jnc   ReadSector2                   ; Test for read error
    xor   ax,ax                         ; BIOS reset disk
    int   13h                           ; Invoke BIOS
    dec   di                            ; Decrement error counter
    pop   cx
    pop   bx
    pop   ax
    jnz   ReadSector1                   ; Attempt to read again
    int   18h
ReadSector2:
    pop   cx
    pop   bx
    pop   ax
    add   bx,word [BytesPerSector]      ; Queue next buffer
    inc   ax                            ; Queue next sector
    loop  ReadSector                    ; Read next sector
    ret

;------------------------------------
; Load Root Directory Table to 07E00h
;------------------------------------
[bits 16]
LoadRootDir:
    pusha                               ; Store registers
    push  es
    ; compute size of root directory and store in "CX"
    xor   cx,cx                         ; Clear registers
    xor   dx,dx
    mov   ax,32                         ; 32 byte directory entry
    mul   word [RootEntries]            ; Total size of directory
    div   word [BytesPerSector]         ; Sectors used by directory
    xchg  ax,cx                         ; Move into AX
    ; compute location of root directory and store in "AX"
    mov   al,byte [NumberOfFATs]        ; Number of FATs
    mul   word [SectorsPerFAT]          ; Sectors used by FATs
    add   ax,word [ReservedSectors]
    mov   word [DataSector],ax          ; Base of root directory
    add   word [DataSector],cx
    ; read root directory into 07E00h
    push  word RootSegment
    pop   es
    mov   bx,0                          ; Copy root dir
    call  ReadSector                    ; Read in directory table
    pop   es
    popa                                ; Restore registers and return
    ret

;-----------------------------
; Loads FAT table to 07C00h
; ES:DI = Root Directory Table
;-----------------------------
[bits 16]
LoadFAT:
    pusha                               ; Store registers
    push  es
    ; compute size of FAT and store in "CX"
    xor   ax,ax
    mov   al,byte [NumberOfFATs]        ; Number of FATs
    mul   word [SectorsPerFAT]          ; Sectors used by FATs
    mov   cx,ax
    ; compute location of FAT and store in "ax"
    mov   ax,word [ReservedSectors]
    ; read FAT into memory (Overwrite our bootloader at 07C00h)
    push  word FatSegment
    pop   es
    xor   bx,bx
    call  ReadSector 
    pop   es
    popa                                ; Restore registers and return
    ret

;----------------------------------------------------------------
; Search for filename in root table
; parm DS:SI = File name
; ret  AX    = File index number in directory table. -1 if error
;----------------------------------------------------------------
[bits 16]
FindFile:
    push  cx                            ; Store registers
    push  dx
    push  bx
    mov   bx,si                         ; Copy filename for later
    ; browse root directory for binary image
    mov   cx,word [RootEntries]         ; Load loop counter
    mov   di,RootOffset                 ; Locate first root entry at 1 MB mark
    cld                                 ; Clear direction flag
FindFile1:
    push  cx
    mov   cx,11                         ; Eleven character name. Image name is in SI
    mov   si,bx                         ; Image name is in BX
    push  di
    rep   cmpsb                         ; Test for entry match
    pop   di
    je    FindFile2
    pop   cx
    add   di,32                         ; Queue next directory entry
    loop  FindFile1
    ; Not Found
    pop   bx                            ; Restore registers and return
    pop   dx
    pop   cx
    mov   ax,-1                         ; Set error code
    ret
FindFile2:
    pop   ax                            ; Return value into AX contains entry of file
    pop   bx                            ; Restore registers and return
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
    xor   cx,cx                         ; Size of file in sectors
    push  cx
    push  bx                            ; BX => BP points to buffer to write to; store it for later
    push  bp
    call  FindFile                      ; Find our file. ES:SI contains our filename
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
    push  word RootSegment              ; Root segment loc
    pop   es
    mov   dx,word [es:di + 0001Ah]      ; DI points to file entry in root directory table. Refrence the table...
    mov   word [Cluster],dx             ; File's first cluster
    pop   bx                            ; Get location to write to so we dont screw up the stack
    pop   es
    push  bx                            ; Store location for later again
    push  es
    call  LoadFAT
LoadFile2:
    ; load the cluster
    mov   ax,word [Cluster]             ; Cluster to read
    pop   es                            ; bx:bp=es:bx
    pop   bx
    call  ClusterLBA
    xor   cx,cx
    mov   cl,byte [SectorsPerCluster]
    call  ReadSector 
    pop   cx
    inc   cx                            ; Add one more sector to counter
    push  cx
    push  bx
    push  es
    mov   ax,FatSegment                 ; Start reading from fat
    mov   es,ax
    xor   bx,bx
    ; get next cluster
    mov   ax,word [Cluster]             ; Identify current cluster
    mov   cx,ax                         ; Copy current cluster
    mov   dx,ax
    shr   dx,0001h                      ; Divide by two
    add   cx,dx                         ; Sum for (3/2)
    mov   bx,0                          ; Location of fat in memory
    add   bx,cx
    mov   dx,word [es:bx]
    test  ax,0001h                      ; Test for odd or even cluster
    jnz   LoadFile3
    and   dx,0000111111111111b          ; Even cluster - take low 12 bits
    jmp   LoadFile4
LoadFile3:
    shr   dx,0004h                      ; Odd cluster  - take high 12 bits
LoadFile4:
    mov   word [Cluster],dx
    cmp   dx,0FF0h                      ; Test for end of file marker
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
    cli                                 ; Disable interrupts and never re-enable in this stage
    xor   ax,ax                         ; Zero out AX
    mov   ds,ax                         ; Set data segments to null
    mov   es,ax                         ; Set extra segment to null

    ;-----------------
    ; Set up our Stack
    ;-----------------
    mov   ax,00h                        ; Set stack 
    mov   ss,ax                         ;  segment to 0000h
    mov   sp,0FFFFh                     ;  stack pointer set to FFFFh (last byte of the first 64 KB of memory)

    ;----------------
    ; Install our GDT
    ;----------------
    call  InstallGDT                    ; install our GDT

    ;-----------
    ; Enable A20
    ;-----------
    call  EnableA20                     ; Enable A20 line

    ;----------------------
    ; Print loading message
    ;----------------------
    mov   si,LoadingMsg                 ; Print loading message
    call  PutStr

    ;----------------------
    ; Initialize filesystem
    ;----------------------
    call  LoadRootDir                   ; Load root directory table

    ;----------------------
    ; Read Stage3 from disk
    ;----------------------
    mov   bx,0                          ; BX:BP points to buffer to load to
    mov   bp,RModeBase                  ; Address to load Stage3
    mov   si,Stage3Name                 ; Name of our file to load
    call  LoadFile                      ; Load Stage3 (our kernel)
    mov   [Stage3Size],cx               ; Save the size of Stage3
    cmp   ax,0                          ; Test for success
    je    GoProtected                   ; yep--onto Stage 3!

    ;------------------
    ; This is very bad!
    ;------------------
    mov   si,FailureMsg                 ; Nope--print error
    call  PutStr                        ;
    mov   ah,0                          ; Wait
    int   16h                           ;  for keypress
    int   19h                           ; Warm boot computer
    hlt                                 ; If we get here, something really went wrong

GoProtected:
    mov   si,Stage3Msg
    call  PutStr
    mov   ah,00h                        ; Wait
    int   16h                           ;  for keypress
    ;--------------
    ; Go into pmode
    ;--------------
    mov   eax,cr0                       ; Set bit 0 in cr0--enter pmode
    or    eax,1
    mov   cr0,eax
    jmp   CodeDesc:GoStage3             ; Far jump to fix CS. Remember that the code selector is 08h!

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
    mov   ax,DataDesc                   ; Set data segments to data selector (10h)
    mov   ds,ax
    mov   ss,ax
    mov   es,ax

    ;-----------------
    ; Set up our Stack
    ;-----------------
    mov   esp,90000h                    ; Stack begins from 90000h

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
    rep   movsd                         ; Copy image to its protected mode address

    ;--------------------
    ; Jump to our Kernel!
    ;--------------------
    jmp   CodeDesc:PModeBase            ; Jump to our kernel! Note: This assumes Kernel's entry point is at 1 MB

    ;-------------------
    ; We never get here! 
    ;-------------------
    hlt                                 ; Halt execution

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
                      db  "AsmOSx86 v0.0.2 Stage 2"
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