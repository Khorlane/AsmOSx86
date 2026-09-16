;**************************************************************************************************
; Paging.asm
;   Early paging setup for AsmOSx86.
;
; Purpose
;   Provide the first protected-mode paging setup while preserving the current
;   flat physical memory behavior through identity mapping.
;
; Contains
;   - Fault IDT gate installation
;   - Identity-mapped page directory and page tables
;   - Shared user virtual page-range remapping
;   - General mapping helpers for existing page tables
;   - CR3/CR0 paging enable path
;   - Minimal fault handlers for page fault and general protection fault
;
; Notes
;   - Maps the first 16 MiB as present, writable pages.
;   - The shared user virtual range can be remapped to task image pages.
;   - User/supervisor enforcement is not enabled yet because all code still
;     runs in ring 0.
;   - Paging does not enable hardware IRQs.
;   - Kernel page faults and general protection faults halt forever.
;   - User page faults and general protection faults terminate the current task.
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; Paging Constants
;--------------------------------------------------------------------------------------------------
PG_PRESENT      equ 00000001h
PG_WRITABLE     equ 00000002h
PG_USER_ACCESS  equ 00000004h
PG_CURRENT_PRESENT_WRITABLE equ PG_PRESENT|PG_WRITABLE
PG_FUTURE_KERNEL_FLAGS equ PG_PRESENT|PG_WRITABLE
PG_FUTURE_USER_FLAGS equ PG_PRESENT|PG_WRITABLE|PG_USER_ACCESS
PG_FUTURE_KCBLOCK_FLAGS equ PG_PRESENT|PG_WRITABLE|PG_USER_ACCESS
PG_KERNEL_FLAGS equ PG_CURRENT_PRESENT_WRITABLE
PG_USER_FLAGS   equ PG_FUTURE_USER_FLAGS
PG_KCBLOCK_FLAGS equ PG_FUTURE_KCBLOCK_FLAGS
PG_MIXED_USER_PDE_FLAGS equ PG_PRESENT|PG_WRITABLE|PG_USER_ACCESS
PG_PAGE_SIZE    equ 00001000h
PG_ENTRY_COUNT  equ 1024
PG_CR0_ENABLE   equ 80000000h
PG_IDT_ATTR     equ 08E00h
PG_GP_FAULT_VECTOR equ 13
PG_PAGE_FAULT_VECTOR equ 14
PG_FAULT_POLICY_HALT equ 1
PG_FAULT_POLICY_FUTURE_USER_KILL equ 2
PG_FAULT_POLICY_FUTURE_KERNEL_PANIC equ 3
PG_USER_GP_EXIT_CODE equ 00000F0Dh
PG_USER_PF_EXIT_CODE equ 00000F0Eh
PG_STATUS_OK    equ 0
PG_STATUS_BAD_ARG equ 1
PG_STATUS_NO_TABLE equ 2

;--------------------------------------------------------------------------------------------------
; Paging Permission Intent
;--------------------------------------------------------------------------------------------------
; Current:
;   PG_KERNEL_FLAGS is supervisor-only. PG_USER_FLAGS and PG_KCBLOCK_FLAGS are
;   user-accessible so ring 3 tasks can reach loaded programs and their
;   KcBlock pages.
;   The first page-directory entry is user-accessible because it contains a mix
;   of supervisor-only kernel PTEs and user-accessible task PTEs.
; Future:
;   Kernel identity mappings stay supervisor-only.
;   Fault handlers decide whether a fault is kernel panic or user task death.

;--------------------------------------------------------------------------------------------------
; Fault Policy Intent
;--------------------------------------------------------------------------------------------------
; Current:
;   Faults from ring 0 halt forever.
;   Faults from ring 3 terminate the current user task and return to scheduler.
;   General protection faults catch privileged instructions and bad selectors.

;--------------------------------------------------------------------------------------------------
; Paging Globals
;--------------------------------------------------------------------------------------------------
align 4
PgEntryIndex    dd 0                    ; work: page-table entry index
PgPhysAddr      dd 0                    ; work: identity-mapped physical address
PgTableAddr     dd 0                    ; work: page table address to fill
PgFaultVector   dd 0                    ; work: IDT vector to install
PgFaultHandler  dd 0                    ; work: fault handler address
PgFaultFrameEsp dd 0                    ; work: ESP at CPU-pushed fault frame
PgFaultCs       dd 0                    ; debug: CS from CPU-pushed fault frame
PgFaultEip      dd 0                    ; debug: EIP from CPU-pushed fault frame
PgFaultError    dd 0                    ; debug: error code from CPU-pushed fault frame
PgFaultCr2      dd 0                    ; debug: CR2 linear address for page faults
PgLastFaultVector dd 0                  ; debug: last fault vector entered
PgLastFaultIsUser dd 0                  ; debug: 1 if fault frame came from ring 3
PgMapVirtualAddress dd 0                ; input: page-aligned virtual address
PgMapPhysicalAddress dd 0               ; input: page-aligned physical address
PgMapFlags      dd 0                    ; input: PG_* entry flags
PgMapStatus     dd 0                    ; output: PG_STATUS_*
PgMapPteAddress dd 0                    ; work: selected page-table entry
String  PgUserFaultStr,"User fault 0000 cs 0000 eip 00000000 addr 00000000"

align 4096
PgDirectory:
  times PG_ENTRY_COUNT dd 0
PgTable0:
  times PG_ENTRY_COUNT dd 0
PgTable1:
  times PG_ENTRY_COUNT dd 0
PgTable2:
  times PG_ENTRY_COUNT dd 0
PgTable3:
  times PG_ENTRY_COUNT dd 0

;--------------------------------------------------------------------------------------------------
; External Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; PgInit
;   Output:
;     Installs a page-fault IDT entry, builds low-memory identity mappings,
;     loads CR3, and enables CR0.PG.
;   Notes:
;     Keeps current physical addresses valid by identity-mapping 00000000h
;     through 00FFFFFFh.
;--------------------------------------------------------------------------------------------------
PgInit:
  call  PgInstallFaultGates
  call  PgBuildIdentityMap
  mov   eax,PgDirectory
  mov   cr3,eax
  mov   eax,cr0
  or    eax,PG_CR0_ENABLE
  mov   cr0,eax
  jmp   PgInit1
PgInit1:
  ret

;--------------------------------------------------------------------------------------------------
; PgMapPage
;   Input:
;     PgMapVirtualAddress  = page-aligned virtual address.
;     PgMapPhysicalAddress = page-aligned physical address.
;     PgMapFlags           = writable/user flags for the page-table entry.
;   Output:
;     PgMapStatus = PG_STATUS_*.
;   Notes:
;     Maps one page through an existing page table and reloads CR3. This helper
;     does not allocate page tables.
;--------------------------------------------------------------------------------------------------
PgMapPage:
  mov   dword[PgMapStatus],PG_STATUS_BAD_ARG
  mov   eax,[PgMapVirtualAddress]
  test  eax,PG_PAGE_SIZE-1
  jnz   PgMapPage1
  mov   eax,[PgMapPhysicalAddress]
  test  eax,PG_PAGE_SIZE-1
  jnz   PgMapPage1
  call  PgFindPte
  cmp   dword[PgMapStatus],PG_STATUS_OK
  jne   PgMapPage1
  mov   eax,[PgMapPhysicalAddress]
  mov   ebx,[PgMapFlags]
  and   ebx,00000FFFh
  or    eax,ebx
  or    eax,PG_PRESENT
  mov   edi,[PgMapPteAddress]
  mov   [edi],eax
  mov   eax,PgDirectory
  mov   cr3,eax
PgMapPage1:
  ret

;--------------------------------------------------------------------------------------------------
; PgUnmapPage
;   Input:
;     PgMapVirtualAddress = page-aligned virtual address.
;   Output:
;     PgMapStatus = PG_STATUS_*.
;   Notes:
;     Clears one entry in an existing page table and reloads CR3.
;--------------------------------------------------------------------------------------------------
PgUnmapPage:
  mov   dword[PgMapStatus],PG_STATUS_BAD_ARG
  mov   eax,[PgMapVirtualAddress]
  test  eax,PG_PAGE_SIZE-1
  jnz   PgUnmapPage1
  call  PgFindPte
  cmp   dword[PgMapStatus],PG_STATUS_OK
  jne   PgUnmapPage1
  mov   edi,[PgMapPteAddress]
  mov   dword[edi],0
  mov   eax,PgDirectory
  mov   cr3,eax
PgUnmapPage1:
  ret

;--------------------------------------------------------------------------------------------------
; Internal Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; PgFindPte
;   Input:
;     PgMapVirtualAddress = page-aligned virtual address.
;   Output:
;     PgMapStatus     = PG_STATUS_OK or PG_STATUS_NO_TABLE.
;     PgMapPteAddress = selected page-table entry when successful.
;--------------------------------------------------------------------------------------------------
PgFindPte:
  mov   dword[PgMapStatus],PG_STATUS_NO_TABLE
  mov   dword[PgMapPteAddress],0
  mov   eax,[PgMapVirtualAddress]
  mov   ebx,eax
  shr   eax,22
  shl   eax,2
  mov   edi,PgDirectory
  add   edi,eax
  mov   eax,[edi]
  test  eax,PG_PRESENT
  jz    PgFindPte1
  and   eax,0FFFFF000h
  mov   edi,eax
  shr   ebx,12
  and   ebx,000003FFh
  shl   ebx,2
  add   edi,ebx
  mov   [PgMapPteAddress],edi
  mov   dword[PgMapStatus],PG_STATUS_OK
PgFindPte1:
  ret

;--------------------------------------------------------------------------------------------------
; PgInstallFaultGates
;   Output:
;     IDT vector 13 points to PgGeneralProtectionFault.
;     IDT vector 14 points to PgPageFault.
;--------------------------------------------------------------------------------------------------
PgInstallFaultGates:
  mov   dword[PgFaultVector],PG_GP_FAULT_VECTOR
  mov   dword[PgFaultHandler],PgGeneralProtectionFault
  call  PgInstallFaultGate
  mov   dword[PgFaultVector],PG_PAGE_FAULT_VECTOR
  mov   dword[PgFaultHandler],PgPageFault
  call  PgInstallFaultGate
  ret

;--------------------------------------------------------------------------------------------------
; PgInstallFaultGate
;   Input:
;     PgFaultVector  = IDT vector number.
;     PgFaultHandler = handler address.
;   Output:
;     IDT vector points to the selected handler.
;--------------------------------------------------------------------------------------------------
PgInstallFaultGate:
  mov   eax,[PgFaultVector]
  mov   ebx,8
  mul   ebx
  lea   edi,[IDT1+eax]
  mov   eax,[PgFaultHandler]
  mov   [edi],ax
  mov   ax,CODE_DESC
  mov   [edi+2],ax
  mov   ax,PG_IDT_ATTR
  mov   [edi+4],ax
  mov   eax,[PgFaultHandler]
  shr   eax,16
  mov   [edi+6],ax
  ret

;--------------------------------------------------------------------------------------------------
; PgBuildIdentityMap
;   Output:
;     First four page-directory entries map the first 16 MiB identity.
;--------------------------------------------------------------------------------------------------
PgBuildIdentityMap:
  xor   eax,eax
  mov   [PgPhysAddr],eax
  mov   eax,PgTable0
  mov   [PgTableAddr],eax
  call  PgFillTable
  mov   eax,PgTable1
  mov   [PgTableAddr],eax
  call  PgFillTable
  mov   eax,PgTable2
  mov   [PgTableAddr],eax
  call  PgFillTable
  mov   eax,PgTable3
  mov   [PgTableAddr],eax
  call  PgFillTable
  mov   eax,PgTable0
  or    eax,PG_MIXED_USER_PDE_FLAGS
  mov   [PgDirectory],eax
  mov   eax,PgTable1
  or    eax,PG_KERNEL_FLAGS
  mov   [PgDirectory+4],eax
  mov   eax,PgTable2
  or    eax,PG_KERNEL_FLAGS
  mov   [PgDirectory+8],eax
  mov   eax,PgTable3
  or    eax,PG_KERNEL_FLAGS
  mov   [PgDirectory+12],eax
  ret

;--------------------------------------------------------------------------------------------------
; PgFillTable
;   Input:
;     PgTableAddr = page table address to fill.
;     PgPhysAddr = first physical address for this table.
;   Output:
;     Page table receives 1024 identity entries.
;     PgPhysAddr advances by 4 MiB.
;--------------------------------------------------------------------------------------------------
PgFillTable:
  mov   eax,PG_ENTRY_COUNT
  mov   [PgEntryIndex],eax
  mov   edi,[PgTableAddr]
PgFillTable1:
  mov   eax,[PgPhysAddr]
  or    eax,PG_KERNEL_FLAGS
  mov   [edi],eax
  add   edi,4
  mov   eax,[PgPhysAddr]
  add   eax,PG_PAGE_SIZE
  mov   [PgPhysAddr],eax
  mov   eax,[PgEntryIndex]
  dec   eax
  mov   [PgEntryIndex],eax
  jnz   PgFillTable1
  ret

;--------------------------------------------------------------------------------------------------
; PgGeneralProtectionFault
;   Output:
;     Kernel faults halt forever. User faults terminate the current task.
;--------------------------------------------------------------------------------------------------
PgGeneralProtectionFault:
  mov   [PgFaultFrameEsp],esp
  mov   dword[PgFaultCr2],0
  mov   dword[PgLastFaultVector],PG_GP_FAULT_VECTOR
  call  PgClassifyFault
  cmp   dword[PgLastFaultIsUser],1
  jne   PgGeneralProtectionFault1
  call  PgPrintUserFault
  mov   [TaskInterruptFrameEsp],esp
  mov   dword[TaskExitCode],PG_USER_GP_EXIT_CODE
  call  TaskExitFromInterrupt
PgGeneralProtectionFault1:
  cli
PgGeneralProtectionFault2:
  hlt
  jmp   PgGeneralProtectionFault2

;--------------------------------------------------------------------------------------------------
; PgPageFault
;   Output:
;     Kernel faults halt forever. User faults terminate the current task.
;--------------------------------------------------------------------------------------------------
PgPageFault:
  mov   [PgFaultFrameEsp],esp
  mov   eax,cr2
  mov   [PgFaultCr2],eax
  mov   dword[PgLastFaultVector],PG_PAGE_FAULT_VECTOR
  call  PgClassifyFault
  cmp   dword[PgLastFaultIsUser],1
  jne   PgPageFault1
  call  PgPrintUserFault
  mov   [TaskInterruptFrameEsp],esp
  mov   dword[TaskExitCode],PG_USER_PF_EXIT_CODE
  call  TaskExitFromInterrupt
PgPageFault1:
  cli
PgPageFault2:
  hlt
  jmp   PgPageFault2

;--------------------------------------------------------------------------------------------------
; PgClassifyFault
;   Output:
;     PgLastFaultIsUser = 1 if the CPU-pushed fault CS has RPL 3, else 0.
;--------------------------------------------------------------------------------------------------
PgClassifyFault:
  mov   dword[PgLastFaultIsUser],0
  mov   dword[PgFaultError],0
  mov   dword[PgFaultEip],0
  mov   dword[PgFaultCs],0
  mov   ebx,[PgFaultFrameEsp]
  test  ebx,ebx
  jz    PgClassifyFault1
  mov   eax,[ebx]
  mov   [PgFaultError],eax
  mov   eax,[ebx+4]
  mov   [PgFaultEip],eax
  movzx eax,word[ebx+8]
  mov   [PgFaultCs],eax
  and   eax,00000003h
  cmp   eax,3
  jne   PgClassifyFault1
  mov   dword[PgLastFaultIsUser],1
PgClassifyFault1:
  ret

;--------------------------------------------------------------------------------------------------
; PgPrintUserFault
;   Output:
;     Prints one compact user-fault diagnostic line.
;--------------------------------------------------------------------------------------------------
PgPrintUserFault:
  mov   eax,[PgLastFaultVector]
  mov   [TaskPut4HexVal],eax
  lea   eax,[PgUserFaultStr+13]
  mov   [pTaskPut4HexDst],eax
  call  TaskPut4Hex
  mov   eax,[PgFaultCs]
  mov   [TaskPut4HexVal],eax
  lea   eax,[PgUserFaultStr+21]
  mov   [pTaskPut4HexDst],eax
  call  TaskPut4Hex
  mov   eax,[PgFaultEip]
  shr   eax,16
  mov   [TaskPut4HexVal],eax
  lea   eax,[PgUserFaultStr+30]
  mov   [pTaskPut4HexDst],eax
  call  TaskPut4Hex
  mov   eax,[PgFaultEip]
  mov   [TaskPut4HexVal],eax
  lea   eax,[PgUserFaultStr+34]
  mov   [pTaskPut4HexDst],eax
  call  TaskPut4Hex
  mov   eax,[PgFaultCr2]
  shr   eax,16
  mov   [TaskPut4HexVal],eax
  lea   eax,[PgUserFaultStr+44]
  mov   [pTaskPut4HexDst],eax
  call  TaskPut4Hex
  mov   eax,[PgFaultCr2]
  mov   [TaskPut4HexVal],eax
  lea   eax,[PgUserFaultStr+48]
  mov   [pTaskPut4HexDst],eax
  call  TaskPut4Hex
  lea   eax,[PgUserFaultStr]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret
