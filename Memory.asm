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
;   - Shared physical-page allocation foundation
;   - Simple kernel-owned stack-like heap
;   - Current-task user memory routing
;
; Public API
;   - MemoryInit
;   - MemoryPhysicalGet
;   - MemoryPhysicalFree
;   - MemoryKernelGet
;   - MemoryKernelFree
;   - MemoryTaskInfo
;   - MemoryTaskGet
;   - MemoryTaskFree
;
; Notes
;   - The shared physical-page pool currently manages a fixed, identity-mapped
;     staging range. Kernel and task allocators will migrate to it separately.
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
MEM_PHYSICAL_POOL_START equ 00800000h
MEM_PHYSICAL_POOL_END equ 01000000h
MEM_PHYSICAL_PAGE_COUNT equ (MEM_PHYSICAL_POOL_END-MEM_PHYSICAL_POOL_START)/PG_PAGE_SIZE
MEM_PHYSICAL_BITMAP_BYTES equ MEM_PHYSICAL_PAGE_COUNT/8

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
MemoryPhysicalRequestPages dd 0         ; input: contiguous physical pages requested/freed
MemoryPhysicalAddress dd 0              ; input/output: first physical page address
MemoryPhysicalStatus dd 0               ; output: MEM_STATUS_*
MemoryPhysicalPageIndex dd 0            ; work: physical-pool page index
MemoryPhysicalRunStart dd 0             ; work: first page index in candidate run
MemoryPhysicalRunLength dd 0            ; work: free pages in candidate run
MemoryPhysicalMarkLeft dd 0              ; work: pages left to mark
MemoryPhysicalBitSet dd 0                ; output: 1 when selected bitmap bit is set
MemoryPhysicalBitmap:
  times MEM_PHYSICAL_BITMAP_BYTES db 0

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
  call  MemoryPhysicalInit
  mov   dword[MemoryStatus],MEM_STATUS_OK
  ret

;--------------------------------------------------------------------------------------------------
; MemoryPhysicalGet
;   Input:
;     MemoryPhysicalRequestPages = number of contiguous physical pages requested.
;   Output:
;     MemoryPhysicalStatus  = MEM_STATUS_*.
;     MemoryPhysicalAddress = first allocated physical page, or 0.
;   Notes:
;     Allocated pages are cleared before they are returned.
;--------------------------------------------------------------------------------------------------
MemoryPhysicalGet:
  mov   dword[MemoryPhysicalStatus],MEM_STATUS_BAD_ARG
  mov   dword[MemoryPhysicalAddress],0
  mov   eax,[MemoryPhysicalRequestPages]
  test  eax,eax
  jz    MemoryPhysicalGet6
  cmp   eax,MEM_PHYSICAL_PAGE_COUNT
  ja    MemoryPhysicalGet5
  mov   dword[MemoryPhysicalPageIndex],0
  mov   dword[MemoryPhysicalRunStart],0
  mov   dword[MemoryPhysicalRunLength],0
MemoryPhysicalGet1:
  call  MemoryPhysicalTestBit
  cmp   dword[MemoryPhysicalBitSet],0
  jne   MemoryPhysicalGet3
  cmp   dword[MemoryPhysicalRunLength],0
  jne   MemoryPhysicalGet2
  mov   eax,[MemoryPhysicalPageIndex]
  mov   [MemoryPhysicalRunStart],eax
MemoryPhysicalGet2:
  inc   dword[MemoryPhysicalRunLength]
  mov   eax,[MemoryPhysicalRunLength]
  cmp   eax,[MemoryPhysicalRequestPages]
  je    MemoryPhysicalGet7
  jmp   MemoryPhysicalGet4
MemoryPhysicalGet3:
  mov   dword[MemoryPhysicalRunLength],0
MemoryPhysicalGet4:
  inc   dword[MemoryPhysicalPageIndex]
  cmp   dword[MemoryPhysicalPageIndex],MEM_PHYSICAL_PAGE_COUNT
  jb    MemoryPhysicalGet1
MemoryPhysicalGet5:
  mov   dword[MemoryPhysicalStatus],MEM_STATUS_NO_MEMORY
MemoryPhysicalGet6:
  ret
MemoryPhysicalGet7:
  mov   eax,[MemoryPhysicalRunStart]
  mov   [MemoryPhysicalPageIndex],eax
  mov   eax,[MemoryPhysicalRequestPages]
  mov   [MemoryPhysicalMarkLeft],eax
MemoryPhysicalGet8:
  call  MemoryPhysicalSetBit
  inc   dword[MemoryPhysicalPageIndex]
  dec   dword[MemoryPhysicalMarkLeft]
  jnz   MemoryPhysicalGet8
  mov   eax,[MemoryPhysicalRunStart]
  mov   ebx,PG_PAGE_SIZE
  mul   ebx
  add   eax,MEM_PHYSICAL_POOL_START
  mov   [MemoryPhysicalAddress],eax
  mov   [MemoryClearPtr],eax
  mov   eax,[MemoryPhysicalRequestPages]
  mov   ebx,PG_PAGE_SIZE
  mul   ebx
  mov   [MemoryClearLeft],eax
  call  MemoryClear
  mov   dword[MemoryPhysicalStatus],MEM_STATUS_OK
  ret

;--------------------------------------------------------------------------------------------------
; MemoryPhysicalFree
;   Input:
;     MemoryPhysicalAddress      = first physical page to free.
;     MemoryPhysicalRequestPages = number of contiguous physical pages to free.
;   Output:
;     MemoryPhysicalStatus = MEM_STATUS_*.
;   Notes:
;     The complete range is validated before any bitmap bits are cleared.
;--------------------------------------------------------------------------------------------------
MemoryPhysicalFree:
  mov   dword[MemoryPhysicalStatus],MEM_STATUS_BAD_ARG
  mov   eax,[MemoryPhysicalRequestPages]
  test  eax,eax
  jz    MemoryPhysicalFree3
  cmp   eax,MEM_PHYSICAL_PAGE_COUNT
  ja    MemoryPhysicalFree3
  mov   eax,[MemoryPhysicalAddress]
  cmp   eax,MEM_PHYSICAL_POOL_START
  jb    MemoryPhysicalFree3
  cmp   eax,MEM_PHYSICAL_POOL_END
  jae   MemoryPhysicalFree3
  test  eax,PG_PAGE_SIZE-1
  jnz   MemoryPhysicalFree3
  sub   eax,MEM_PHYSICAL_POOL_START
  mov   ebx,PG_PAGE_SIZE
  xor   edx,edx
  div   ebx
  mov   [MemoryPhysicalPageIndex],eax
  add   eax,[MemoryPhysicalRequestPages]
  cmp   eax,MEM_PHYSICAL_PAGE_COUNT
  ja    MemoryPhysicalFree3
  mov   eax,[MemoryPhysicalRequestPages]
  mov   [MemoryPhysicalMarkLeft],eax
MemoryPhysicalFree1:
  call  MemoryPhysicalTestBit
  cmp   dword[MemoryPhysicalBitSet],1
  jne   MemoryPhysicalFree3
  inc   dword[MemoryPhysicalPageIndex]
  dec   dword[MemoryPhysicalMarkLeft]
  jnz   MemoryPhysicalFree1
  mov   eax,[MemoryPhysicalAddress]
  sub   eax,MEM_PHYSICAL_POOL_START
  mov   ebx,PG_PAGE_SIZE
  xor   edx,edx
  div   ebx
  mov   [MemoryPhysicalPageIndex],eax
  mov   eax,[MemoryPhysicalRequestPages]
  mov   [MemoryPhysicalMarkLeft],eax
MemoryPhysicalFree2:
  call  MemoryPhysicalClearBit
  inc   dword[MemoryPhysicalPageIndex]
  dec   dword[MemoryPhysicalMarkLeft]
  jnz   MemoryPhysicalFree2
  mov   dword[MemoryPhysicalStatus],MEM_STATUS_OK
MemoryPhysicalFree3:
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
; MemoryPhysicalInit
;   Output:
;     Clears the physical-page allocation bitmap.
;--------------------------------------------------------------------------------------------------
MemoryPhysicalInit:
  mov   dword[MemoryPhysicalRequestPages],0
  mov   dword[MemoryPhysicalAddress],0
  mov   dword[MemoryPhysicalStatus],MEM_STATUS_OK
  mov   eax,MemoryPhysicalBitmap
  mov   [MemoryClearPtr],eax
  mov   dword[MemoryClearLeft],MEM_PHYSICAL_BITMAP_BYTES
  call  MemoryClear
  ret

;--------------------------------------------------------------------------------------------------
; MemoryPhysicalTestBit
;   Input:
;     MemoryPhysicalPageIndex = physical-pool page index.
;   Output:
;     MemoryPhysicalBitSet = 1 when allocated, otherwise 0.
;--------------------------------------------------------------------------------------------------
MemoryPhysicalTestBit:
  mov   dword[MemoryPhysicalBitSet],0
  mov   eax,[MemoryPhysicalPageIndex]
  mov   ecx,eax
  and   ecx,7
  shr   eax,3
  movzx ebx,byte[MemoryPhysicalBitmap+eax]
  mov   eax,1
  shl   eax,cl
  test  ebx,eax
  jz    MemoryPhysicalTestBit1
  mov   dword[MemoryPhysicalBitSet],1
MemoryPhysicalTestBit1:
  ret

;--------------------------------------------------------------------------------------------------
; MemoryPhysicalSetBit
;   Input:
;     MemoryPhysicalPageIndex = physical-pool page index.
;--------------------------------------------------------------------------------------------------
MemoryPhysicalSetBit:
  mov   eax,[MemoryPhysicalPageIndex]
  mov   ecx,eax
  and   ecx,7
  shr   eax,3
  lea   edi,[MemoryPhysicalBitmap+eax]
  mov   ebx,1
  shl   ebx,cl
  or    [edi],bl
  ret

;--------------------------------------------------------------------------------------------------
; MemoryPhysicalClearBit
;   Input:
;     MemoryPhysicalPageIndex = physical-pool page index.
;--------------------------------------------------------------------------------------------------
MemoryPhysicalClearBit:
  mov   eax,[MemoryPhysicalPageIndex]
  mov   ecx,eax
  and   ecx,7
  shr   eax,3
  lea   edi,[MemoryPhysicalBitmap+eax]
  mov   ebx,1
  shl   ebx,cl
  not   ebx
  and   [edi],bl
  ret

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
