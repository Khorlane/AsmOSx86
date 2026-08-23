;**************************************************************************************************
; Memory.asm
;   Kernel memory-management layer for AsmOSx86.
;
; Purpose
;   Provide a single memory-management boundary that can route requests to
;   task-owned user memory today and kernel-owned memory later.
;
; Contains
;   - Memory status constants
;   - Memory service globals
;   - Current-task user memory routing
;
; Public API
;   - MemoryInit
;   - MemoryTaskInfo
;   - MemoryTaskGet
;   - MemoryTaskFree
;
; Notes
;   - This first version intentionally preserves the existing task-memory
;     behavior.
;   - Kernel-owned dynamic allocation belongs here next, not in Fs.asm.
;   - Registers are scratch only.
;   - Persistent inputs/outputs use Memory* globals.
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; Memory Status Constants
;--------------------------------------------------------------------------------------------------
MEM_STATUS_OK        equ 0
MEM_STATUS_BAD_ARG   equ 1
MEM_STATUS_NO_MEMORY equ 2

;--------------------------------------------------------------------------------------------------
; Memory Globals
;--------------------------------------------------------------------------------------------------
align 4
MemoryRequestBytes   dd 0               ; input: bytes requested
MemoryPointer        dd 0               ; input/output: memory pointer
MemoryBytes          dd 0               ; output: page-rounded byte count
MemoryMappedBytes    dd 0               ; output: mapped bytes for info calls
MemoryMaxBytes       dd 0               ; output: maximum bytes for info calls
MemoryStatus         dd 0               ; output: MEM_STATUS_*

;--------------------------------------------------------------------------------------------------
; External Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; MemoryInit
;   Output:
;     MemoryStatus = MEM_STATUS_OK.
;--------------------------------------------------------------------------------------------------
MemoryInit:
  mov   dword[MemoryRequestBytes],0
  mov   dword[MemoryPointer],0
  mov   dword[MemoryBytes],0
  mov   dword[MemoryMappedBytes],0
  mov   dword[MemoryMaxBytes],0
  mov   dword[MemoryStatus],MEM_STATUS_OK
  ret

;--------------------------------------------------------------------------------------------------
; MemoryTaskInfo
;   Output:
;     MemoryStatus      = MEM_STATUS_*.
;     MemoryMappedBytes = bytes currently mapped for this task's user image.
;     MemoryMaxBytes    = maximum bytes available in the user image range.
;--------------------------------------------------------------------------------------------------
MemoryTaskInfo:
  call  TaskMemoryInfo
  mov   eax,[TaskMemoryStatus]
  mov   [MemoryStatus],eax
  mov   eax,[TaskMemoryMappedBytes]
  mov   [MemoryMappedBytes],eax
  mov   eax,[TaskMemoryMaxBytes]
  mov   [MemoryMaxBytes],eax
  ret

;--------------------------------------------------------------------------------------------------
; MemoryTaskGet
;   Input:
;     MemoryRequestBytes = requested byte count.
;   Output:
;     MemoryStatus  = MEM_STATUS_*.
;     MemoryPointer = allocated user virtual address.
;     MemoryBytes   = page-rounded allocated byte count.
;--------------------------------------------------------------------------------------------------
MemoryTaskGet:
  mov   dword[MemoryPointer],0
  mov   dword[MemoryBytes],0
  mov   eax,[MemoryRequestBytes]
  mov   [TaskMemoryRequestBytes],eax
  call  TaskMemoryGet
  mov   eax,[TaskMemoryStatus]
  mov   [MemoryStatus],eax
  mov   eax,[TaskMemoryPointer]
  mov   [MemoryPointer],eax
  mov   eax,[TaskMemoryBytes]
  mov   [MemoryBytes],eax
  ret

;--------------------------------------------------------------------------------------------------
; MemoryTaskFree
;   Input:
;     MemoryPointer      = memory pointer returned by MemoryTaskGet.
;     MemoryRequestBytes = byte count to free.
;   Output:
;     MemoryStatus = MEM_STATUS_*.
;     MemoryBytes  = page-rounded freed byte count.
;--------------------------------------------------------------------------------------------------
MemoryTaskFree:
  mov   dword[MemoryBytes],0
  mov   eax,[MemoryPointer]
  mov   [TaskMemoryPointer],eax
  mov   eax,[MemoryRequestBytes]
  mov   [TaskMemoryRequestBytes],eax
  call  TaskMemoryFree
  mov   eax,[TaskMemoryStatus]
  mov   [MemoryStatus],eax
  mov   eax,[TaskMemoryBytes]
  mov   [MemoryBytes],eax
  ret
