;**************************************************************************************************
; Fs.asm
;   File service and early storage plumbing for AsmOSx86.
;
; Purpose
;   Provide a small memory-backed file service surface for kernel and future
;   userland callers.
;
; Contains
;   - File service status constants
;   - File service communication fields
;   - Tiny handle table skeleton
;   - Placeholders for FAT12 and floppy block-device work
;
; Notes
;   - This first pass intentionally does not read the floppy yet.
;   - FAT12 parsing and protected-mode floppy sector reads can be filled into
;     the marked sections without changing the KcFsOpen/KcFsRead/KcFsClose
;     service shape.
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

;--------------------------------------------------------------------------------------------------
; File Service Constants
;--------------------------------------------------------------------------------------------------
FS_MAX_HANDLES        equ 4
FS_HANDLE_FREE        equ 0
FS_HANDLE_OPEN        equ 1
FS_HANDLE_STATE       equ 0
FS_HANDLE_DEVICE      equ 4
FS_HANDLE_POSITION    equ 8
FS_HANDLE_SIZE        equ 12
FS_HANDLE_CLUSTER     equ 16
FS_HANDLE_RECORD_SIZE equ 20
FS_HANDLE_TABLE_SIZE  equ FS_MAX_HANDLES*FS_HANDLE_RECORD_SIZE

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
pFsHandleClear       dd 0              ; work: handle-table clear pointer
FsHandleClearLeft    dd 0              ; work: handle-table clear bytes left
FsHandleTable:
  times FS_HANDLE_TABLE_SIZE db 0

;--------------------------------------------------------------------------------------------------
; FsInit
;   Output:
;     FsStatus = FS_STATUS_OK
;   Notes:
;     Clears the tiny handle table. No hardware access happens here yet.
;--------------------------------------------------------------------------------------------------
FsInit:
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
  mov   dword[FsStatus],FS_STATUS_OK
  ret

;--------------------------------------------------------------------------------------------------
; FsOpen
;   Input:
;     pFsOpenName = pointer to kernel Str filename.
;   Output:
;     FsStatus     = FS_STATUS_NOT_READY until FAT12/floppy read support exists.
;     FsOpenHandle = opened handle, or 0.
;--------------------------------------------------------------------------------------------------
FsOpen:
  mov   dword[FsOpenHandle],0
  mov   eax,[pFsOpenName]
  test  eax,eax
  jz    FsOpen1
  mov   dword[FsStatus],FS_STATUS_NOT_READY
  ret
FsOpen1:
  mov   dword[FsStatus],FS_STATUS_BAD_ARG
  ret

;--------------------------------------------------------------------------------------------------
; FsRead
;   Input:
;     FsReadHandle  = open file handle.
;     pFsReadBuffer = destination buffer.
;     FsReadCount   = requested byte count.
;   Output:
;     FsStatus    = FS_STATUS_NOT_READY until FAT12/floppy read support exists.
;     FsReadBytes = bytes read.
;--------------------------------------------------------------------------------------------------
FsRead:
  mov   dword[FsReadBytes],0
  mov   eax,[FsReadHandle]
  test  eax,eax
  jz    FsRead1
  mov   eax,[pFsReadBuffer]
  test  eax,eax
  jz    FsRead2
  mov   eax,[FsReadCount]
  test  eax,eax
  jz    FsRead2
  mov   dword[FsStatus],FS_STATUS_NOT_READY
  ret
FsRead1:
  mov   dword[FsStatus],FS_STATUS_BAD_HANDLE
  ret
FsRead2:
  mov   dword[FsStatus],FS_STATUS_BAD_ARG
  ret

;--------------------------------------------------------------------------------------------------
; FsClose
;   Input:
;     FsCloseHandle = open file handle.
;   Output:
;     FsStatus = FS_STATUS_BAD_HANDLE until real handles can be opened.
;--------------------------------------------------------------------------------------------------
FsClose:
  mov   eax,[FsCloseHandle]
  test  eax,eax
  jz    FsClose1
  mov   dword[FsStatus],FS_STATUS_BAD_HANDLE
  ret
FsClose1:
  mov   dword[FsStatus],FS_STATUS_BAD_HANDLE
  ret

;--------------------------------------------------------------------------------------------------
; FAT12 Driver
;--------------------------------------------------------------------------------------------------
; Future home for:
;   - BPB/media validation
;   - Root directory scanning
;   - 8.3 filename matching
;   - FAT12 cluster-chain walking

;--------------------------------------------------------------------------------------------------
; Floppy Block Device
;--------------------------------------------------------------------------------------------------
; Future home for:
;   - FDC reset/specify/recalibrate/seek
;   - DMA channel 2 setup
;   - Sector reads into a low-memory bounce buffer
;   - Motor control using a DOR shadow
