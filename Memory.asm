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
;   - Simple kernel-owned stack-like heap
;   - Current-task user memory routing
;
; Public API
;   - MemoryInit
;   - MemoryKernelGet
;   - MemoryKernelFree
;   - MemoryTaskInfo
;   - MemoryTaskGet
;   - MemoryTaskFree
;
; Notes
;   - Kernel memory is currently a small page-rounded stack-like heap.
;   - User memory routing intentionally preserves the existing task-memory
;     behavior.
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
MEM_KERNEL_HEAP_BYTES equ 00010000h

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
MemoryKernelHeapStart dd 0              ; first kernel heap byte
MemoryKernelHeapEnd  dd 0               ; exclusive kernel heap end
MemoryKernelNext     dd 0               ; next kernel heap byte
MemoryClearPtr       dd 0               ; work: memory clear pointer
MemoryClearLeft      dd 0               ; work: bytes left to clear

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
  mov   eax,KernelEnd
  add   eax,PG_PAGE_SIZE-1
  and   eax,0FFFFF000h
  mov   [MemoryKernelHeapStart],eax
  mov   [MemoryKernelNext],eax
  add   eax,MEM_KERNEL_HEAP_BYTES
  mov   [MemoryKernelHeapEnd],eax
  mov   dword[MemoryStatus],MEM_STATUS_OK
  ret

;--------------------------------------------------------------------------------------------------
; MemoryKernelGet
;   Input:
;     MemoryRequestBytes = requested byte count.
;   Output:
;     MemoryStatus  = MEM_STATUS_*.
;     MemoryPointer = allocated kernel pointer.
;     MemoryBytes   = page-rounded allocated byte count.
;--------------------------------------------------------------------------------------------------
MemoryKernelGet:
  mov   dword[MemoryStatus],MEM_STATUS_BAD_ARG
  mov   dword[MemoryPointer],0
  mov   dword[MemoryBytes],0
  mov   eax,[MemoryRequestBytes]
  test  eax,eax
  jz    MemoryKernelGet2
  add   eax,PG_PAGE_SIZE-1
  and   eax,0FFFFF000h
  mov   [MemoryBytes],eax
  mov   ebx,[MemoryKernelNext]
  add   eax,ebx
  cmp   eax,[MemoryKernelHeapEnd]
  ja    MemoryKernelGet1
  mov   [MemoryKernelNext],eax
  mov   [MemoryPointer],ebx
  mov   [MemoryClearPtr],ebx
  mov   eax,[MemoryBytes]
  mov   [MemoryClearLeft],eax
  call  MemoryClear
  mov   dword[MemoryStatus],MEM_STATUS_OK
  ret
MemoryKernelGet1:
  mov   dword[MemoryStatus],MEM_STATUS_NO_MEMORY
MemoryKernelGet2:
  ret

;--------------------------------------------------------------------------------------------------
; MemoryKernelFree
;   Input:
;     MemoryPointer      = kernel pointer returned by MemoryKernelGet.
;     MemoryRequestBytes = byte count to free.
;   Output:
;     MemoryStatus = MEM_STATUS_*.
;     MemoryBytes  = page-rounded freed byte count.
;   Notes:
;     This first kernel heap is stack-like: only the most recent allocation can
;     be freed.
;--------------------------------------------------------------------------------------------------
MemoryKernelFree:
  mov   dword[MemoryStatus],MEM_STATUS_BAD_ARG
  mov   dword[MemoryBytes],0
  mov   eax,[MemoryRequestBytes]
  test  eax,eax
  jz    MemoryKernelFree1
  add   eax,PG_PAGE_SIZE-1
  and   eax,0FFFFF000h
  mov   [MemoryBytes],eax
  mov   ebx,[MemoryPointer]
  cmp   ebx,[MemoryKernelHeapStart]
  jb    MemoryKernelFree1
  cmp   ebx,[MemoryKernelHeapEnd]
  jae   MemoryKernelFree1
  test  ebx,PG_PAGE_SIZE-1
  jnz   MemoryKernelFree1
  add   eax,ebx
  cmp   eax,[MemoryKernelNext]
  jne   MemoryKernelFree1
  mov   [MemoryKernelNext],ebx
  mov   dword[MemoryStatus],MEM_STATUS_OK
MemoryKernelFree1:
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

;--------------------------------------------------------------------------------------------------
; Internal Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; MemoryClear
;   Input:
;     MemoryClearPtr  = destination pointer.
;     MemoryClearLeft = byte count.
;   Output:
;     MemoryClearPtr advanced and requested bytes set to zero.
;--------------------------------------------------------------------------------------------------
MemoryClear:
  mov   eax,[MemoryClearLeft]
  test  eax,eax
  jz    MemoryClear2
MemoryClear1:
  mov   edi,[MemoryClearPtr]
  mov   byte[edi],0
  inc   edi
  mov   [MemoryClearPtr],edi
  dec   dword[MemoryClearLeft]
  jnz   MemoryClear1
MemoryClear2:
  ret
