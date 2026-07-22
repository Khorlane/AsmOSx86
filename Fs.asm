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
;   - Read-only FAT12 root-directory lookup
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
;   - It assumes a 1.44MB FAT12 floppy in drive A:.
;   - It uses a low-memory DMA bounce buffer at 00008000h.
;   - FAT12 and floppy routines are internal implementation details.
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; File Service Status Constants
;--------------------------------------------------------------------------------------------------
FS_STATUS_OK          equ 0
FS_STATUS_NOT_READY   equ 1
FS_STATUS_BAD_ARG     equ 2
FS_STATUS_BAD_HANDLE  equ 3
FS_STATUS_EOF         equ 4
FS_STATUS_NOT_FOUND   equ 5
FS_STATUS_IO_ERROR    equ 6
FS_STATUS_NO_HANDLE   equ 7

;--------------------------------------------------------------------------------------------------
; File Service Constants
;--------------------------------------------------------------------------------------------------
FS_MAX_HANDLES        equ 4
FS_HANDLE_FREE        equ 0
FS_HANDLE_OPEN        equ 1
FS_HANDLE_STATE       equ 0
FS_HANDLE_POSITION    equ 4
FS_HANDLE_SIZE        equ 8
FS_HANDLE_CLUSTER     equ 12
FS_HANDLE_RECORD_SIZE equ 16
FS_HANDLE_TABLE_SIZE  equ FS_MAX_HANDLES*FS_HANDLE_RECORD_SIZE

FAT12_BYTES_PER_SECTOR equ 512
FAT12_ROOT_ENTRY_SIZE  equ 32
FAT12_NAME_SIZE        equ 11
FAT12_ROOT_MAX_BYTES   equ 7168
FAT12_FAT_MAX_BYTES    equ 4608
FAT12_EOC              equ 0FF0h

FDC_BASE              equ 03F0h
FDC_DOR               equ FDC_BASE+2
FDC_MSR               equ FDC_BASE+4
FDC_DATA              equ FDC_BASE+5
FDC_CCR               equ FDC_BASE+7
FDC_CMD_SPECIFY       equ 03h
FDC_CMD_RECALIBRATE   equ 07h
FDC_CMD_SENSE_INT     equ 08h
FDC_CMD_SEEK          equ 0Fh
FDC_CMD_READ_DATA     equ 046h
FDC_DOR_RESET         equ 00000100b
FDC_DOR_DMAIRQ        equ 00001000b
FDC_DOR_MOTOR_A       equ 00010000b
FDC_WAIT_LIMIT        equ 100000
FDC_DMA_BUFFER        equ 00008000h

DMA_MASK              equ 00Ah
DMA_MODE              equ 00Bh
DMA_CLEAR             equ 00Ch
DMA_CH2_ADDR          equ 004h
DMA_CH2_COUNT         equ 005h
DMA_CH2_PAGE          equ 081h

;--------------------------------------------------------------------------------------------------
; File Service Globals
;--------------------------------------------------------------------------------------------------
align 4
FsStatus             dd 0              ; output: FS_STATUS_*
pFsOpenName          dd 0              ; input: pointer to kernel Str filename
FsOpenHandle         dd 0              ; output: opened handle, or 0
FsReadHandle         dd 0              ; input: handle to read
pFsReadBuffer        dd 0              ; input: destination buffer
FsReadCount          dd 0              ; input: requested bytes
FsReadBytes          dd 0              ; output: bytes read
FsCloseHandle        dd 0              ; input: handle to close
FsMounted            dd 0              ; 1 once FAT/root are loaded
FsHandleIndex        dd 0              ; work: current handle index
pFsHandleRecord      dd 0              ; work/output: selected handle record
pFsHandleClear       dd 0              ; work: handle-table clear pointer
FsHandleClearLeft    dd 0              ; work: handle-table clear bytes left
FsWorkCount          dd 0              ; work: generic count
FsWorkIndex          dd 0              ; work: generic index
FsWorkPtr            dd 0              ; work: generic pointer
FsWorkPtr2           dd 0              ; work: generic pointer
FsCopyLeft           dd 0              ; work: bytes left to copy
FsCopySrc            dd 0              ; work: copy source
FsCopyDst            dd 0              ; work: copy destination
FsCopyCount          dd 0              ; work: copy byte count
FsFilePosition       dd 0              ; work: current file position
FsFileSize           dd 0              ; work: current file size
FsFileCluster        dd 0              ; work: first/current file cluster
FsSectorOffset       dd 0              ; work: offset inside sector
FsBytesThisRead      dd 0              ; work: chunk byte count
FsFileSectorIndex    dd 0              ; work: file-relative sector index
FsCurrentCluster     dd 0              ; work/output: cluster for sector index
FsCurrentLba         dd 0              ; input/work: current logical sector
FsNameIndex          dd 0              ; work: filename output index
FsNameInputLeft      dd 0              ; work: chars left in input Str
FsNameOutputLimit    dd 0              ; work: 8 before dot, 3 after dot
FsNameOutputBase     dd 0              ; work: output base 0 or 8
FsNamePayload        dd 0              ; work: source payload pointer
FsFatOffset          dd 0              ; work: FAT entry byte offset
FsRootEntryLeft      dd 0              ; work: root entries left
pFsRootEntry         dd 0              ; work/output: root entry pointer
FsRootStartLba       dd 0              ; FAT12 root-directory start LBA
FsRootSectors        dd 0              ; FAT12 root-directory sectors
FsFatStartLba        dd 0              ; FAT12 FAT start LBA
FsFatSectors         dd 0              ; FAT12 sectors per FAT
FsDataStartLba       dd 0              ; FAT12 first data-sector LBA
FsRootEntries        dd 0              ; FAT12 max root entries
FsSectorsPerCluster  dd 0              ; FAT12 sectors per cluster
FsSectorsPerTrack    dd 0              ; floppy sectors per track
FsHeads              dd 0              ; floppy heads
FlpDorShadow         db 0              ; DOR is write-only
FlpCylinder          db 0              ; CHS cylinder
FlpHead              db 0              ; CHS head
FlpSector            db 0              ; CHS sector, 1 based
FlpResult0           db 0
FlpResult1           db 0
FlpResult2           db 0
FlpResult3           db 0
FlpResult4           db 0
FlpResult5           db 0
FlpResult6           db 0
FsName83:
  times FAT12_NAME_SIZE db 0
FsHandleTable:
  times FS_HANDLE_TABLE_SIZE db 0
FsSectorBuffer:
  times FAT12_BYTES_PER_SECTOR db 0
FsFatBuffer:
  times FAT12_FAT_MAX_BYTES db 0
FsRootBuffer:
  times FAT12_ROOT_MAX_BYTES db 0

;--------------------------------------------------------------------------------------------------
; FsInit
;   Output:
;     FsStatus = FS_STATUS_OK
;--------------------------------------------------------------------------------------------------
FsInit:
  mov   dword[FsMounted],0
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
  call  FloppyInit
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
  mov   eax,[pFsOpenName]
  test  eax,eax
  jz    FsOpenBadArg
  call  Fat12MakeName83
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsOpenDone
  mov   eax,[FsMounted]
  test  eax,eax
  jnz   FsOpen1
  call  Fat12Mount
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsOpenDone
FsOpen1:
  call  Fat12FindRootEntry
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
  mov   esi,[pFsRootEntry]
  movzx eax,word[esi+26]
  mov   [edi+FS_HANDLE_CLUSTER],eax
  mov   eax,[esi+28]
  mov   [edi+FS_HANDLE_SIZE],eax
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
  mov   eax,[edi+FS_HANDLE_CLUSTER]
  mov   [FsFileCluster],eax
FsReadLoop:
  mov   eax,[FsReadCount]
  test  eax,eax
  jz    FsReadOk
  mov   eax,[FsFilePosition]
  cmp   eax,[FsFileSize]
  jae   FsReadEof
  mov   eax,[FsFilePosition]
  and   eax,FAT12_BYTES_PER_SECTOR-1
  mov   [FsSectorOffset],eax
  mov   ebx,FAT12_BYTES_PER_SECTOR
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
  shr   eax,9
  mov   [FsFileSectorIndex],eax
  call  Fat12ClusterForSector
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   FsReadDone
  call  Fat12ClusterToLba
  call  FloppyReadSector
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
  mov   dword[edi+FS_HANDLE_CLUSTER],0
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

;--------------------------------------------------------------------------------------------------
; FAT12 Driver
;--------------------------------------------------------------------------------------------------
Fat12Mount:
  mov   dword[FsCurrentLba],0
  mov   dword[FsWorkPtr],FsSectorBuffer
  call  FloppyReadSectorTo
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   Fat12MountDone
  movzx eax,word[FsSectorBuffer+11]
  cmp   eax,FAT12_BYTES_PER_SECTOR
  jne   Fat12MountBad
  movzx eax,byte[FsSectorBuffer+13]
  mov   [FsSectorsPerCluster],eax
  movzx eax,word[FsSectorBuffer+14]
  mov   [FsFatStartLba],eax
  movzx eax,byte[FsSectorBuffer+16]
  mov   [FsWorkCount],eax
  movzx eax,word[FsSectorBuffer+17]
  mov   [FsRootEntries],eax
  movzx eax,word[FsSectorBuffer+22]
  mov   [FsFatSectors],eax
  movzx eax,word[FsSectorBuffer+24]
  mov   [FsSectorsPerTrack],eax
  movzx eax,word[FsSectorBuffer+26]
  mov   [FsHeads],eax
  mov   eax,[FsRootEntries]
  mov   ebx,FAT12_ROOT_ENTRY_SIZE
  mul   ebx
  add   eax,FAT12_BYTES_PER_SECTOR-1
  shr   eax,9
  mov   [FsRootSectors],eax
  mov   eax,[FsFatSectors]
  mov   ebx,[FsWorkCount]
  mul   ebx
  add   eax,[FsFatStartLba]
  mov   [FsRootStartLba],eax
  add   eax,[FsRootSectors]
  mov   [FsDataStartLba],eax
  call  Fat12ReadFat
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   Fat12MountDone
  call  Fat12ReadRoot
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   Fat12MountDone
  mov   dword[FsMounted],1
  mov   dword[FsStatus],FS_STATUS_OK
  jmp   Fat12MountDone
Fat12MountBad:
  mov   dword[FsStatus],FS_STATUS_NOT_READY
Fat12MountDone:
  ret

Fat12ReadFat:
  mov   dword[FsWorkIndex],0
  mov   dword[FsWorkPtr],FsFatBuffer
Fat12ReadFat1:
  mov   eax,[FsWorkIndex]
  cmp   eax,[FsFatSectors]
  jae   Fat12ReadFat2
  add   eax,[FsFatStartLba]
  mov   [FsCurrentLba],eax
  call  FloppyReadSectorTo
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   Fat12ReadFatDone
  add   dword[FsWorkPtr],FAT12_BYTES_PER_SECTOR
  inc   dword[FsWorkIndex]
  jmp   Fat12ReadFat1
Fat12ReadFat2:
  mov   dword[FsStatus],FS_STATUS_OK
Fat12ReadFatDone:
  ret

Fat12ReadRoot:
  mov   dword[FsWorkIndex],0
  mov   dword[FsWorkPtr],FsRootBuffer
Fat12ReadRoot1:
  mov   eax,[FsWorkIndex]
  cmp   eax,[FsRootSectors]
  jae   Fat12ReadRoot2
  add   eax,[FsRootStartLba]
  mov   [FsCurrentLba],eax
  call  FloppyReadSectorTo
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   Fat12ReadRootDone
  add   dword[FsWorkPtr],FAT12_BYTES_PER_SECTOR
  inc   dword[FsWorkIndex]
  jmp   Fat12ReadRoot1
Fat12ReadRoot2:
  mov   dword[FsStatus],FS_STATUS_OK
Fat12ReadRootDone:
  ret

Fat12MakeName83:
  mov   edi,FsName83
  mov   ecx,FAT12_NAME_SIZE
Fat12MakeName831:
  mov   byte[edi],' '
  inc   edi
  dec   ecx
  jnz   Fat12MakeName831
  mov   esi,[pFsOpenName]
  movzx ecx,word[esi]
  test  ecx,ecx
  jz    Fat12MakeName83Bad
  add   esi,2
  mov   [FsNamePayload],esi
  mov   [FsNameInputLeft],ecx
  mov   dword[FsNameOutputBase],0
  mov   dword[FsNameIndex],0
  mov   dword[FsNameOutputLimit],8
Fat12MakeName832:
  mov   eax,[FsNameInputLeft]
  test  eax,eax
  jz    Fat12MakeName83Ok
  mov   esi,[FsNamePayload]
  mov   al,[esi]
  inc   esi
  mov   [FsNamePayload],esi
  dec   dword[FsNameInputLeft]
  cmp   al,'.'
  je    Fat12MakeName83Dot
  cmp   al,'a'
  jb    Fat12MakeName833
  cmp   al,'z'
  ja    Fat12MakeName833
  sub   al,32
Fat12MakeName833:
  mov   ebx,[FsNameIndex]
  cmp   ebx,[FsNameOutputLimit]
  jae   Fat12MakeName832
  add   ebx,[FsNameOutputBase]
  mov   [FsName83+ebx],al
  inc   dword[FsNameIndex]
  jmp   Fat12MakeName832
Fat12MakeName83Dot:
  mov   dword[FsNameOutputBase],8
  mov   dword[FsNameIndex],0
  mov   dword[FsNameOutputLimit],3
  jmp   Fat12MakeName832
Fat12MakeName83Ok:
  mov   dword[FsStatus],FS_STATUS_OK
  ret
Fat12MakeName83Bad:
  mov   dword[FsStatus],FS_STATUS_BAD_ARG
  ret

Fat12FindRootEntry:
  mov   dword[pFsRootEntry],FsRootBuffer
  mov   eax,[FsRootEntries]
  mov   [FsRootEntryLeft],eax
Fat12FindRootEntry1:
  mov   eax,[FsRootEntryLeft]
  test  eax,eax
  jz    Fat12FindRootEntryNotFound
  mov   edi,[pFsRootEntry]
  mov   al,[edi]
  test  al,al
  jz    Fat12FindRootEntryNotFound
  cmp   al,0E5h
  je    Fat12FindRootEntryNext
  mov   al,[edi+11]
  test  al,00011000b
  jnz   Fat12FindRootEntryNext
  mov   esi,FsName83
  mov   ecx,FAT12_NAME_SIZE
Fat12FindRootEntryCmp:
  mov   al,[esi]
  cmp   al,[edi]
  jne   Fat12FindRootEntryNext
  inc   esi
  inc   edi
  dec   ecx
  jnz   Fat12FindRootEntryCmp
  mov   dword[FsStatus],FS_STATUS_OK
  ret
Fat12FindRootEntryNext:
  add   dword[pFsRootEntry],FAT12_ROOT_ENTRY_SIZE
  dec   dword[FsRootEntryLeft]
  jmp   Fat12FindRootEntry1
Fat12FindRootEntryNotFound:
  mov   dword[pFsRootEntry],0
  mov   dword[FsStatus],FS_STATUS_NOT_FOUND
  ret

Fat12ClusterForSector:
  mov   eax,[FsFileCluster]
  mov   [FsCurrentCluster],eax
  mov   eax,[FsFileSectorIndex]
  mov   [FsWorkCount],eax
Fat12ClusterForSector1:
  mov   eax,[FsWorkCount]
  test  eax,eax
  jz    Fat12ClusterForSector2
  call  Fat12NextCluster
  mov   eax,[FsCurrentCluster]
  cmp   eax,FAT12_EOC
  jae   Fat12ClusterForSectorBad
  dec   dword[FsWorkCount]
  jmp   Fat12ClusterForSector1
Fat12ClusterForSector2:
  mov   dword[FsStatus],FS_STATUS_OK
  ret
Fat12ClusterForSectorBad:
  mov   dword[FsStatus],FS_STATUS_IO_ERROR
  ret

Fat12NextCluster:
  mov   eax,[FsCurrentCluster]
  mov   ebx,eax
  shr   ebx,1
  add   ebx,eax
  mov   [FsFatOffset],ebx
  mov   esi,FsFatBuffer
  add   esi,ebx
  movzx edx,word[esi]
  test  eax,1
  jnz   Fat12NextCluster1
  and   edx,00000FFFh
  jmp   Fat12NextCluster2
Fat12NextCluster1:
  shr   edx,4
Fat12NextCluster2:
  mov   [FsCurrentCluster],edx
  ret

Fat12ClusterToLba:
  mov   eax,[FsCurrentCluster]
  sub   eax,2
  mov   ebx,[FsSectorsPerCluster]
  mul   ebx
  add   eax,[FsDataStartLba]
  mov   [FsCurrentLba],eax
  ret

;--------------------------------------------------------------------------------------------------
; Floppy Block Device
;--------------------------------------------------------------------------------------------------
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

FloppyReadSector:
  mov   dword[FsWorkPtr],FsSectorBuffer
  call  FloppyReadSectorTo
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
  mov   ecx,FAT12_BYTES_PER_SECTOR
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
  mov   ebx,18
FloppyLbaToChs1:
  div   ebx
  inc   dl
  mov   [FlpSector],dl
  xor   edx,edx
  mov   ebx,[FsHeads]
  test  ebx,ebx
  jnz   FloppyLbaToChs2
  mov   ebx,2
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
  mov   al,18
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
