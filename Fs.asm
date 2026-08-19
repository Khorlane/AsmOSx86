;**************************************************************************************************
; Fs.asm
;   File service and early storage plumbing for AsmOSx86.
;
; Purpose
;   Provide a small memory-backed file service surface for kernel and future
;   userland callers.
;
; Contains
;   - File service open/read/close
;   - Read-only AsmOSx86 manifest lookup
;   - Tiny block-device routing
;   - Bare-bones floppy sector reads
;
; Public API
;   - FsInit
;   - FsOpen
;   - FsRead
;   - FsClose
;
; Notes
;   - This is intentionally simple and optimistic.
;   - It assumes a 1.44MB AsmOSx86 raw floppy image in drive A:.
;   - It uses a low-memory DMA bounce buffer at 00008000h.
;   - Manifest and floppy routines are internal implementation details.
;**************************************************************************************************

[bits 32]

;**************************************************************************************************
; Filesystem Common
;**************************************************************************************************
KERNEL_SECTOR_SIZE       equ 512
KERNEL_SECTOR_SHIFT      equ 9
FS_STATUS_OK             equ 0
FS_STATUS_NOT_READY      equ 1
FS_STATUS_BAD_ARG        equ 2
FS_STATUS_BAD_HANDLE     equ 3
FS_STATUS_EOF            equ 4
FS_STATUS_NOT_FOUND      equ 5
FS_STATUS_IO_ERROR       equ 6
FS_STATUS_NO_HANDLE      equ 7

align 4
FsWorkCount              dd 0          ; work: generic count
FsWorkIndex              dd 0          ; work: generic index
FsWorkPtr                dd 0          ; work: generic pointer
FsSectorBuffer:
  times KERNEL_SECTOR_SIZE db 0

;**************************************************************************************************
; Filesystem Global
;**************************************************************************************************
FsStatus                 dd 0          ; output: FS_STATUS_*
pFsOpenName              dd 0          ; input: pointer to kernel Str filename
FsOpenHandle             dd 0          ; output: opened handle, or 0
FsOpenSize               dd 0          ; output: opened file size
FsReadHandle             dd 0          ; input: handle to read
pFsReadBuffer            dd 0          ; input: destination buffer
FsReadCount              dd 0          ; input: requested bytes
FsReadBytes              dd 0          ; output: bytes read
FsCloseHandle            dd 0          ; input: handle to close

;**************************************************************************************************
; Kernel calls
;**************************************************************************************************
; Kernel-call handlers live in Kc.asm. They use the Filesystem Global memory
; contract fields above and call the File service routines below.

;**************************************************************************************************
; File service
;**************************************************************************************************
FS_MAX_HANDLES           equ 4
FS_HANDLE_FREE           equ 0
FS_HANDLE_OPEN           equ 1
FS_HANDLE_STATE          equ 0
FS_HANDLE_POSITION       equ 4
FS_HANDLE_SIZE           equ 8
FS_HANDLE_START_SECTOR   equ 12
FS_HANDLE_RECORD_SIZE    equ 16
FS_HANDLE_TABLE_SIZE     equ FS_MAX_HANDLES*FS_HANDLE_RECORD_SIZE

FsHandleIndex            dd 0          ; work: current handle index
pFsHandleRecord          dd 0          ; work/output: selected handle record
pFsHandleClear           dd 0          ; work: handle-table clear pointer
FsHandleClearLeft        dd 0          ; work: handle-table clear bytes left
FsFilePosition           dd 0          ; work: current file position
FsFileSize               dd 0          ; work: current file size
FsFileStartSector        dd 0          ; work: first file sector
FsSectorOffset           dd 0          ; work: offset inside sector
FsBytesThisRead          dd 0          ; work: chunk byte count
FsFileSectorIndex        dd 0          ; work: file-relative sector index
FsHandleTable:
  times FS_HANDLE_TABLE_SIZE db 0

;**************************************************************************************************
; Filesystem driver
;**************************************************************************************************
ASMFS_MANIFEST_SECTOR    equ 1
ASMFS_SIGNATURE          equ 464D5341h
ASMFS_ENTRY_COUNT        equ 6
ASMFS_ENTRY_OFFSET       equ 16
ASMFS_ENTRY_SIZE         equ 32
ASMFS_ENTRY_START_SECTOR equ 12
ASMFS_ENTRY_BYTE_SIZE    equ 16
ASMFS_MANIFEST_BYTES     equ KERNEL_SECTOR_SIZE
ASMFS_NAME_SIZE          equ 11

FsMounted                dd 0          ; 1 once manifest is loaded
FsNameIndex              dd 0          ; work: filename output index
FsNameInputLeft          dd 0          ; work: chars left in input Str
FsNameOutputLimit        dd 0          ; work: 8 before dot, 3 after dot
FsNameOutputBase         dd 0          ; work: output base 0 or 8
FsNamePayload            dd 0          ; work: source payload pointer
FsEntryLeft              dd 0          ; work: manifest entries left
pFsEntry                 dd 0          ; work/output: manifest entry pointer
FsEntryCount             dd 0          ; manifest entry count
FsName83:
  times ASMFS_NAME_SIZE db 0
FsRootBuffer:
  times ASMFS_MANIFEST_BYTES db 0

;**************************************************************************************************
; Block device layer
;**************************************************************************************************
DEV_STATUS_OK            equ 0
DEV_STATUS_BAD_DEVICE    equ 1
DEV_STATUS_IO_ERROR      equ 2
DEV_DEFAULT_BLOCK_DEVICE equ DEV_ID_FLOPPY_A
FLOPPY_A_SECTORS         equ 2880

DevStatus                dd 0          ; output: DEV_STATUS_*
DevBlockDevice           dd 0          ; input/current block device
DevSector                dd 0          ; input: block-device sector
DevBuffer                dd 0          ; input: destination buffer

;**************************************************************************************************
; Device driver
;**************************************************************************************************
FDC_BASE                 equ 03F0h
FDC_DOR                  equ FDC_BASE+2
FDC_MSR                  equ FDC_BASE+4
FDC_DATA                 equ FDC_BASE+5
FDC_CCR                  equ FDC_BASE+7
FDC_CMD_SPECIFY          equ 03h
FDC_CMD_RECALIBRATE      equ 07h
FDC_CMD_SENSE_INT        equ 08h
FDC_CMD_SEEK             equ 0Fh
FDC_CMD_READ_DATA        equ 046h
FDC_DOR_RESET            equ 00000100b
FDC_DOR_DMAIRQ           equ 00001000b
FDC_DOR_MOTOR_A          equ 00010000b
FDC_WAIT_LIMIT           equ 100000
FDC_DMA_BUFFER           equ 00008000h
FLOPPY_SECTORS_PER_TRACK equ 18
FLOPPY_HEADS             equ 2
DMA_MASK                 equ 00Ah
DMA_MODE                 equ 00Bh
DMA_CLEAR                equ 00Ch
DMA_CH2_ADDR             equ 004h
DMA_CH2_COUNT            equ 005h
DMA_CH2_PAGE             equ 081h

FsCurrentLba             dd 0          ; input/work: current logical sector
FsSectorsPerTrack        dd 0          ; floppy sectors per track
FsHeads                  dd 0          ; floppy heads
FlpDorShadow             db 0          ; DOR is write-only
FlpCylinder              db 0          ; CHS cylinder
FlpHead                  db 0          ; CHS head
FlpSector                db 0          ; CHS sector, 1 based
FlpResult0               db 0
FlpResult1               db 0
FlpResult2               db 0
FlpResult3               db 0
FlpResult4               db 0
FlpResult5               db 0
FlpResult6               db 0

;**************************************************************************************************
; File service
;**************************************************************************************************

;--------------------------------------------------------------------------------------------------
; FsInit
;   Output:
;     FsStatus = FS_STATUS_OK
;--------------------------------------------------------------------------------------------------
FsInit:
  mov   dword[FsMounted],0
  mov   dword[FsSectorsPerTrack],FLOPPY_SECTORS_PER_TRACK
  mov   dword[FsHeads],FLOPPY_HEADS
  mov   eax,FsHandleTable
  mov   [pFsHandleClear],eax
  mov   dword[FsHandleClearLeft],FS_HANDLE_TABLE_SIZE
FsInit1:
  mov   eax,[FsHandleClearLeft]
  test  eax,eax
  jz    FsInit2
  mov   edi,[pFsHandleClear]
  mov   byte[edi],0
  inc   edi
  mov   [pFsHandleClear],edi
  dec   eax
  mov   [FsHandleClearLeft],eax
  jmp   FsInit1
FsInit2:
  call  DevInit
  mov   dword[FsStatus],FS_STATUS_OK
  ret

;--------------------------------------------------------------------------------------------------
; FsOpen
;   Input:
;     pFsOpenName = pointer to kernel Str filename.
;   Output:
;     FsStatus     = FS_STATUS_*
;     FsOpenHandle = opened handle, or 0.
;--------------------------------------------------------------------------------------------------
FsOpen:
  mov   dword[FsOpenHandle],0
  mov   dword[FsOpenSize],0
  mov   eax,[pFsOpenName]
  test  eax,eax
  jz    FsOpenBadArg
  call  AsmFsMakeName83
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsOpenDone
  mov   eax,[FsMounted]
  test  eax,eax
  jnz   FsOpen1
  call  AsmFsMount
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsOpenDone
FsOpen1:
  call  AsmFsFindEntry
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsOpenDone
  call  FsFindFreeHandle
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsOpenDone
  mov   edi,[pFsHandleRecord]
  mov   dword[edi+FS_HANDLE_STATE],FS_HANDLE_OPEN
  mov   dword[edi+FS_HANDLE_POSITION],0
  mov   esi,[pFsEntry]
  mov   eax,[esi+ASMFS_ENTRY_START_SECTOR]
  mov   [edi+FS_HANDLE_START_SECTOR],eax
  mov   eax,[esi+ASMFS_ENTRY_BYTE_SIZE]
  mov   [edi+FS_HANDLE_SIZE],eax
  mov   [FsOpenSize],eax
  mov   eax,[FsHandleIndex]
  inc   eax
  mov   [FsOpenHandle],eax
  mov   dword[FsStatus],FS_STATUS_OK
  jmp   FsOpenDone
FsOpenBadArg:
  mov   dword[FsStatus],FS_STATUS_BAD_ARG
FsOpenDone:
  ret

;--------------------------------------------------------------------------------------------------
; FsRead
;   Input:
;     FsReadHandle  = open file handle.
;     pFsReadBuffer = destination buffer.
;     FsReadCount   = requested byte count.
;   Output:
;     FsStatus    = FS_STATUS_*
;     FsReadBytes = bytes read.
;--------------------------------------------------------------------------------------------------
FsRead:
  mov   dword[FsReadBytes],0
  mov   eax,[pFsReadBuffer]
  test  eax,eax
  jz    FsReadBadArg
  mov   eax,[FsReadCount]
  test  eax,eax
  jz    FsReadBadArg
  mov   eax,[FsReadHandle]
  mov   [FsHandleIndex],eax
  dec   dword[FsHandleIndex]
  call  FsGetHandleRecord
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsReadDone
  mov   edi,[pFsHandleRecord]
  mov   eax,[edi+FS_HANDLE_STATE]
  cmp   eax,FS_HANDLE_OPEN
  jne   FsReadBadHandle
  mov   eax,[edi+FS_HANDLE_POSITION]
  mov   [FsFilePosition],eax
  mov   eax,[edi+FS_HANDLE_SIZE]
  mov   [FsFileSize],eax
  mov   eax,[edi+FS_HANDLE_START_SECTOR]
  mov   [FsFileStartSector],eax
FsReadLoop:
  mov   eax,[FsReadCount]
  test  eax,eax
  jz    FsReadOk
  mov   eax,[FsFilePosition]
  cmp   eax,[FsFileSize]
  jae   FsReadEof
  mov   eax,[FsFilePosition]
  and   eax,KERNEL_SECTOR_SIZE-1
  mov   [FsSectorOffset],eax
  mov   ebx,KERNEL_SECTOR_SIZE
  sub   ebx,eax
  mov   [FsBytesThisRead],ebx
  mov   eax,[FsReadCount]
  cmp   eax,[FsBytesThisRead]
  jae   FsRead1
  mov   [FsBytesThisRead],eax
FsRead1:
  mov   eax,[FsFileSize]
  sub   eax,[FsFilePosition]
  cmp   eax,[FsBytesThisRead]
  jae   FsRead2
  mov   [FsBytesThisRead],eax
FsRead2:
  mov   eax,[FsFilePosition]
  shr   eax,KERNEL_SECTOR_SHIFT
  mov   [FsFileSectorIndex],eax
  add   eax,[FsFileStartSector]
  mov   [DevSector],eax
  mov   dword[DevBuffer],FsSectorBuffer
  call  DevReadSector
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsReadDone
  mov   esi,FsSectorBuffer
  add   esi,[FsSectorOffset]
  mov   edi,[pFsReadBuffer]
  add   edi,[FsReadBytes]
  mov   ecx,[FsBytesThisRead]
  rep   movsb
  mov   eax,[FsBytesThisRead]
  add   [FsReadBytes],eax
  add   [FsFilePosition],eax
  sub   [FsReadCount],eax
  jmp   FsReadLoop
FsReadOk:
  mov   edi,[pFsHandleRecord]
  mov   eax,[FsFilePosition]
  mov   [edi+FS_HANDLE_POSITION],eax
  mov   dword[FsStatus],FS_STATUS_OK
  jmp   FsReadDone
FsReadEof:
  mov   edi,[pFsHandleRecord]
  mov   eax,[FsFilePosition]
  mov   [edi+FS_HANDLE_POSITION],eax
  mov   eax,[FsReadBytes]
  test  eax,eax
  jnz   FsReadOk
  mov   dword[FsStatus],FS_STATUS_EOF
  jmp   FsReadDone
FsReadBadArg:
  mov   dword[FsStatus],FS_STATUS_BAD_ARG
  jmp   FsReadDone
FsReadBadHandle:
  mov   dword[FsStatus],FS_STATUS_BAD_HANDLE
FsReadDone:
  ret

;--------------------------------------------------------------------------------------------------
; FsClose
;   Input:
;     FsCloseHandle = open file handle.
;   Output:
;     FsStatus = FS_STATUS_*
;--------------------------------------------------------------------------------------------------
FsClose:
  mov   eax,[FsCloseHandle]
  mov   [FsHandleIndex],eax
  dec   dword[FsHandleIndex]
  call  FsGetHandleRecord
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsCloseDone
  mov   edi,[pFsHandleRecord]
  mov   dword[edi+FS_HANDLE_STATE],FS_HANDLE_FREE
  mov   dword[edi+FS_HANDLE_POSITION],0
  mov   dword[edi+FS_HANDLE_SIZE],0
  mov   dword[edi+FS_HANDLE_START_SECTOR],0
  mov   dword[FsStatus],FS_STATUS_OK
FsCloseDone:
  ret

;--------------------------------------------------------------------------------------------------
; FsGetHandleRecord
;   Input:
;     FsHandleIndex = zero-based handle index.
;   Output:
;     FsStatus        = FS_STATUS_OK or FS_STATUS_BAD_HANDLE.
;     pFsHandleRecord = selected record, or 0.
;--------------------------------------------------------------------------------------------------
FsGetHandleRecord:
  mov   dword[pFsHandleRecord],0
  mov   eax,[FsHandleIndex]
  cmp   eax,FS_MAX_HANDLES
  jae   FsGetHandleRecord1
  mov   ebx,FS_HANDLE_RECORD_SIZE
  mul   ebx
  mov   edi,FsHandleTable
  add   edi,eax
  mov   [pFsHandleRecord],edi
  mov   dword[FsStatus],FS_STATUS_OK
  ret
FsGetHandleRecord1:
  mov   dword[FsStatus],FS_STATUS_BAD_HANDLE
  ret

;--------------------------------------------------------------------------------------------------
; FsFindFreeHandle
;   Output:
;     FsStatus        = FS_STATUS_OK or FS_STATUS_NO_HANDLE.
;     FsHandleIndex   = selected zero-based index.
;     pFsHandleRecord = selected record.
;--------------------------------------------------------------------------------------------------
FsFindFreeHandle:
  mov   dword[FsHandleIndex],0
  mov   dword[pFsHandleRecord],FsHandleTable
FsFindFreeHandle1:
  mov   eax,[FsHandleIndex]
  cmp   eax,FS_MAX_HANDLES
  jae   FsFindFreeHandle2
  mov   edi,[pFsHandleRecord]
  mov   eax,[edi+FS_HANDLE_STATE]
  cmp   eax,FS_HANDLE_FREE
  je    FsFindFreeHandle3
  add   edi,FS_HANDLE_RECORD_SIZE
  mov   [pFsHandleRecord],edi
  inc   dword[FsHandleIndex]
  jmp   FsFindFreeHandle1
FsFindFreeHandle2:
  mov   dword[FsStatus],FS_STATUS_NO_HANDLE
  ret
FsFindFreeHandle3:
  mov   dword[FsStatus],FS_STATUS_OK
  ret

;**************************************************************************************************
; Filesystem driver
;**************************************************************************************************
AsmFsMount:
  mov   dword[DevSector],ASMFS_MANIFEST_SECTOR
  mov   dword[DevBuffer],FsRootBuffer
  call  DevReadSector
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   AsmFsMountDone
  mov   eax,[FsRootBuffer]
  cmp   eax,ASMFS_SIGNATURE
  jne   AsmFsMountBad
  movzx eax,word[FsRootBuffer+ASMFS_ENTRY_COUNT]
  mov   [FsEntryCount],eax
  mov   dword[FsMounted],1
  mov   dword[FsStatus],FS_STATUS_OK
  jmp   AsmFsMountDone
AsmFsMountBad:
  mov   dword[FsStatus],FS_STATUS_NOT_READY
AsmFsMountDone:
  ret

AsmFsMakeName83:
  mov   edi,FsName83
  mov   ecx,ASMFS_NAME_SIZE
AsmFsMakeName831:
  mov   byte[edi],' '
  inc   edi
  dec   ecx
  jnz   AsmFsMakeName831
  mov   esi,[pFsOpenName]
  movzx ecx,word[esi]
  test  ecx,ecx
  jz    AsmFsMakeName83Bad
  add   esi,2
  mov   [FsNamePayload],esi
  mov   [FsNameInputLeft],ecx
  mov   dword[FsNameOutputBase],0
  mov   dword[FsNameIndex],0
  mov   dword[FsNameOutputLimit],8
AsmFsMakeName832:
  mov   eax,[FsNameInputLeft]
  test  eax,eax
  jz    AsmFsMakeName83Ok
  mov   esi,[FsNamePayload]
  mov   al,[esi]
  inc   esi
  mov   [FsNamePayload],esi
  dec   dword[FsNameInputLeft]
  cmp   al,'.'
  je    AsmFsMakeName83Dot
  cmp   al,'a'
  jb    AsmFsMakeName833
  cmp   al,'z'
  ja    AsmFsMakeName833
  sub   al,32
AsmFsMakeName833:
  mov   ebx,[FsNameIndex]
  cmp   ebx,[FsNameOutputLimit]
  jae   AsmFsMakeName832
  add   ebx,[FsNameOutputBase]
  mov   [FsName83+ebx],al
  inc   dword[FsNameIndex]
  jmp   AsmFsMakeName832
AsmFsMakeName83Dot:
  mov   dword[FsNameOutputBase],8
  mov   dword[FsNameIndex],0
  mov   dword[FsNameOutputLimit],3
  jmp   AsmFsMakeName832
AsmFsMakeName83Ok:
  mov   dword[FsStatus],FS_STATUS_OK
  ret
AsmFsMakeName83Bad:
  mov   dword[FsStatus],FS_STATUS_BAD_ARG
  ret

AsmFsFindEntry:
  mov   dword[pFsEntry],FsRootBuffer+ASMFS_ENTRY_OFFSET
  mov   eax,[FsEntryCount]
  mov   [FsEntryLeft],eax
AsmFsFindEntry1:
  mov   eax,[FsEntryLeft]
  test  eax,eax
  jz    AsmFsFindEntryNotFound
  mov   edi,[pFsEntry]
  mov   esi,FsName83
  mov   ecx,ASMFS_NAME_SIZE
AsmFsFindEntryCmp:
  mov   al,[esi]
  cmp   al,[edi]
  jne   AsmFsFindEntryNext
  inc   esi
  inc   edi
  dec   ecx
  jnz   AsmFsFindEntryCmp
  mov   dword[FsStatus],FS_STATUS_OK
  ret
AsmFsFindEntryNext:
  add   dword[pFsEntry],ASMFS_ENTRY_SIZE
  dec   dword[FsEntryLeft]
  jmp   AsmFsFindEntry1
AsmFsFindEntryNotFound:
  mov   dword[pFsEntry],0
  mov   dword[FsStatus],FS_STATUS_NOT_FOUND
  ret

;**************************************************************************************************
; Block device layer
;**************************************************************************************************

;--------------------------------------------------------------------------------------------------
; DevInit
;   Output:
;     DevStatus = DEV_STATUS_OK
;--------------------------------------------------------------------------------------------------
DevInit:
  mov   dword[DevBlockDevice],DEV_DEFAULT_BLOCK_DEVICE
  call  FloppyInit
  mov   dword[DevStatus],DEV_STATUS_OK
  ret

;--------------------------------------------------------------------------------------------------
; DevReadSector
;   Input:
;     DevBlockDevice = block device id.
;     DevSector      = sector to read.
;     DevBuffer      = destination buffer.
;   Output:
;     DevStatus = DEV_STATUS_*
;     FsStatus  = FS_STATUS_*
;--------------------------------------------------------------------------------------------------
DevReadSector:
  mov   eax,[DevBlockDevice]
  cmp   eax,DEV_ID_FLOPPY_A
  jne   DevReadSectorBadDevice
  mov   eax,[DevSector]
  cmp   eax,FLOPPY_A_SECTORS
  jae   DevReadSectorIoError
  mov   [FsCurrentLba],eax
  mov   eax,[DevBuffer]
  mov   [FsWorkPtr],eax
  call  FloppyReadSectorTo
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   DevReadSectorIoError
  mov   dword[DevStatus],DEV_STATUS_OK
  mov   dword[FsStatus],FS_STATUS_OK
  ret
DevReadSectorBadDevice:
  mov   dword[DevStatus],DEV_STATUS_BAD_DEVICE
  mov   dword[FsStatus],FS_STATUS_NOT_READY
  ret
DevReadSectorIoError:
  mov   dword[DevStatus],DEV_STATUS_IO_ERROR
  mov   dword[FsStatus],FS_STATUS_IO_ERROR
  ret

;**************************************************************************************************
; Device driver
;**************************************************************************************************
FloppyInit:
  mov   al,FDC_DOR_RESET | FDC_DOR_DMAIRQ
  mov   [FlpDorShadow],al
  mov   dx,FDC_DOR
  out   dx,al
  mov   dx,FDC_CCR
  xor   al,al
  out   dx,al
  call  FloppySpecify
  ret

FloppyReadSectorTo:
  call  FloppyLbaToChs
  call  FloppyMotorOn
  call  FloppyDmaSetupRead
  call  FloppySeek
  call  FloppyCommandRead
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FloppyReadSectorToDone
  mov   esi,FDC_DMA_BUFFER
  mov   edi,[FsWorkPtr]
  mov   ecx,KERNEL_SECTOR_SIZE
  rep   movsb
  mov   dword[FsStatus],FS_STATUS_OK
FloppyReadSectorToDone:
  ret

FloppyLbaToChs:
  mov   eax,[FsCurrentLba]
  xor   edx,edx
  mov   ebx,[FsSectorsPerTrack]
  test  ebx,ebx
  jnz   FloppyLbaToChs1
  mov   ebx,FLOPPY_SECTORS_PER_TRACK
FloppyLbaToChs1:
  div   ebx
  inc   dl
  mov   [FlpSector],dl
  xor   edx,edx
  mov   ebx,[FsHeads]
  test  ebx,ebx
  jnz   FloppyLbaToChs2
  mov   ebx,FLOPPY_HEADS
FloppyLbaToChs2:
  div   ebx
  mov   [FlpHead],dl
  mov   [FlpCylinder],al
  ret

FloppyMotorOn:
  mov   al,FDC_DOR_RESET | FDC_DOR_DMAIRQ | FDC_DOR_MOTOR_A
  mov   [FlpDorShadow],al
  mov   dx,FDC_DOR
  out   dx,al
  mov   ecx,400000
FloppyMotorOn1:
  dec   ecx
  jnz   FloppyMotorOn1
  ret

FloppySpecify:
  mov   al,FDC_CMD_SPECIFY
  call  FloppyWriteByte
  mov   al,0DFh
  call  FloppyWriteByte
  mov   al,002h
  call  FloppyWriteByte
  ret

FloppySeek:
  mov   al,FDC_CMD_SEEK
  call  FloppyWriteByte
  mov   al,[FlpHead]
  shl   al,2
  call  FloppyWriteByte
  mov   al,[FlpCylinder]
  call  FloppyWriteByte
  call  FloppySenseInterrupt
  ret

FloppySenseInterrupt:
  mov   al,FDC_CMD_SENSE_INT
  call  FloppyWriteByte
  call  FloppyReadByte
  mov   [FlpResult0],al
  call  FloppyReadByte
  mov   [FlpResult1],al
  ret

FloppyCommandRead:
  mov   dword[FsStatus],FS_STATUS_IO_ERROR
  mov   al,FDC_CMD_READ_DATA
  call  FloppyWriteByte
  mov   al,[FlpHead]
  shl   al,2
  call  FloppyWriteByte
  mov   al,[FlpCylinder]
  call  FloppyWriteByte
  mov   al,[FlpHead]
  call  FloppyWriteByte
  mov   al,[FlpSector]
  call  FloppyWriteByte
  mov   al,2
  call  FloppyWriteByte
  mov   al,FLOPPY_SECTORS_PER_TRACK
  call  FloppyWriteByte
  mov   al,01Bh
  call  FloppyWriteByte
  mov   al,0FFh
  call  FloppyWriteByte
  call  FloppyReadResult
  mov   al,[FlpResult0]
  test  al,0C0h
  jnz   FloppyCommandReadDone
  mov   dword[FsStatus],FS_STATUS_OK
FloppyCommandReadDone:
  ret

FloppyReadResult:
  call  FloppyReadByte
  mov   [FlpResult0],al
  call  FloppyReadByte
  mov   [FlpResult1],al
  call  FloppyReadByte
  mov   [FlpResult2],al
  call  FloppyReadByte
  mov   [FlpResult3],al
  call  FloppyReadByte
  mov   [FlpResult4],al
  call  FloppyReadByte
  mov   [FlpResult5],al
  call  FloppyReadByte
  mov   [FlpResult6],al
  ret

FloppyWriteByte:
  mov   ah,al
  mov   ecx,FDC_WAIT_LIMIT
FloppyWriteByte1:
  mov   dx,FDC_MSR
  in    al,dx
  and   al,0C0h
  cmp   al,080h
  je    FloppyWriteByte2
  dec   ecx
  jnz   FloppyWriteByte1
  mov   dword[FsStatus],FS_STATUS_IO_ERROR
  ret
FloppyWriteByte2:
  mov   al,ah
  mov   dx,FDC_DATA
  out   dx,al
  ret

FloppyReadByte:
  mov   ecx,FDC_WAIT_LIMIT
FloppyReadByte1:
  mov   dx,FDC_MSR
  in    al,dx
  and   al,0C0h
  cmp   al,0C0h
  je    FloppyReadByte2
  dec   ecx
  jnz   FloppyReadByte1
  mov   dword[FsStatus],FS_STATUS_IO_ERROR
  xor   al,al
  ret
FloppyReadByte2:
  mov   dx,FDC_DATA
  in    al,dx
  ret

FloppyDmaSetupRead:
  mov   al,006h
  out   DMA_MASK,al
  mov   al,0FFh
  out   DMA_CLEAR,al
  mov   al,046h
  out   DMA_MODE,al
  mov   al,00h
  out   DMA_CH2_ADDR,al
  mov   al,080h
  out   DMA_CH2_ADDR,al
  mov   al,00h
  out   DMA_CH2_PAGE,al
  mov   al,0FFh
  out   DMA_CH2_COUNT,al
  mov   al,001h
  out   DMA_CH2_COUNT,al
  mov   al,002h
  out   DMA_MASK,al
  ret
