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
;   - CR3/CR0 paging enable path
;   - Minimal halt handlers for page fault and general protection fault
;
; Notes
;   - Maps the first 16 MiB as present, writable pages.
;   - The shared user virtual range can be remapped to task image pages.
;   - User/supervisor enforcement is not enabled yet because all code still
;     runs in ring 0.
;   - Paging does not enable hardware IRQs.
;   - Page faults and general protection faults currently halt forever.
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
PG_USER_PTE     equ 512
PG_USER_MAX_PAGES equ 16
PG_USER_KC_PTE  equ PG_USER_PTE+PG_USER_MAX_PAGES

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
PgUserPhysBase  dd 0                    ; input: physical page backing user virtual base
PgUserPageCount dd 0                    ; input: number of user pages to map
PgUserKcPhysBase dd 0                   ; input: physical page backing user KcBlock
PgUserPageLeft  dd 0                    ; work: user pages left to map
PgUserMappedCount dd 0                  ; work: user pages mapped
PgUserClearLeft dd 0                    ; work: user PTEs left to clear
PgUserPteAddr   dd 0                    ; work: current user PTE address
PgUserMapPhys   dd 0                    ; work: current user physical page
PgFaultVector   dd 0                    ; work: IDT vector to install
PgFaultHandler  dd 0                    ; work: fault handler address
PgFaultFrameEsp dd 0                    ; work: ESP at CPU-pushed fault frame
PgFaultCs       dd 0                    ; debug: CS from CPU-pushed fault frame
PgLastFaultVector dd 0                  ; debug: last fault vector entered
PgLastFaultIsUser dd 0                  ; debug: 1 if fault frame came from ring 3

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
; PgMapUserProgram
;   Input:
;     PgUserPhysBase  = first physical 4K page backing the user virtual base.
;     PgUserPageCount = number of contiguous user pages to map.
;     PgUserKcPhysBase = physical 4K page backing the user KcBlock.
;   Output:
;     Shared user virtual range and KcBlock page are mapped and CR3 is reloaded.
;--------------------------------------------------------------------------------------------------
PgMapUserProgram:
  mov   eax,[PgUserPageCount]
  test  eax,eax
  jnz   PgMapUserProgram1
  mov   eax,1
PgMapUserProgram1:
  cmp   eax,PG_USER_MAX_PAGES
  jbe   PgMapUserProgram3
  mov   eax,PG_USER_MAX_PAGES
PgMapUserProgram3:
  mov   [PgUserPageLeft],eax
  mov   [PgUserMappedCount],eax
  mov   eax,[PgUserPhysBase]
  and   eax,0FFFFF000h
  mov   [PgUserMapPhys],eax
  mov   eax,PgTable0+(PG_USER_PTE*4)
  mov   [PgUserPteAddr],eax
PgMapUserProgram2:
  mov   eax,[PgUserMapPhys]
  or    eax,PG_USER_FLAGS
  mov   edi,[PgUserPteAddr]
  mov   [edi],eax
  add   edi,4
  mov   [PgUserPteAddr],edi
  mov   eax,[PgUserMapPhys]
  add   eax,PG_PAGE_SIZE
  mov   [PgUserMapPhys],eax
  mov   eax,[PgUserPageLeft]
  dec   eax
  mov   [PgUserPageLeft],eax
  jnz   PgMapUserProgram2
  mov   eax,PG_USER_MAX_PAGES
  sub   eax,[PgUserMappedCount]
  mov   [PgUserClearLeft],eax
PgMapUserProgram4:
  mov   eax,[PgUserClearLeft]
  test  eax,eax
  jz    PgMapUserProgram5
  mov   edi,[PgUserPteAddr]
  xor   eax,eax
  mov   [edi],eax
  add   edi,4
  mov   [PgUserPteAddr],edi
  mov   eax,[PgUserClearLeft]
  dec   eax
  mov   [PgUserClearLeft],eax
  jmp   PgMapUserProgram4
PgMapUserProgram5:
  mov   eax,[PgUserKcPhysBase]
  and   eax,0FFFFF000h
  or    eax,PG_KCBLOCK_FLAGS
  mov   [PgTable0+(PG_USER_KC_PTE*4)],eax
  mov   eax,PgDirectory
  mov   cr3,eax
  ret

;--------------------------------------------------------------------------------------------------
; Internal Routines
;--------------------------------------------------------------------------------------------------

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
  mov   dword[PgLastFaultVector],PG_GP_FAULT_VECTOR
  call  PgClassifyFault
  cmp   dword[PgLastFaultIsUser],1
  jne   PgGeneralProtectionFaultHalt
  mov   [TaskInterruptFrameEsp],esp
  mov   dword[TaskExitCode],PG_USER_GP_EXIT_CODE
  call  TaskExitFromInterrupt
PgGeneralProtectionFaultHalt:
  cli
PgGeneralProtectionFault1:
  hlt
  jmp   PgGeneralProtectionFault1

;--------------------------------------------------------------------------------------------------
; PgPageFault
;   Output:
;     Kernel faults halt forever. User faults terminate the current task.
;--------------------------------------------------------------------------------------------------
PgPageFault:
  mov   [PgFaultFrameEsp],esp
  mov   dword[PgLastFaultVector],PG_PAGE_FAULT_VECTOR
  call  PgClassifyFault
  cmp   dword[PgLastFaultIsUser],1
  jne   PgPageFaultHalt
  mov   [TaskInterruptFrameEsp],esp
  mov   dword[TaskExitCode],PG_USER_PF_EXIT_CODE
  call  TaskExitFromInterrupt
PgPageFaultHalt:
  cli
PgPageFault1:
  hlt
  jmp   PgPageFault1

;--------------------------------------------------------------------------------------------------
; PgClassifyFault
;   Output:
;     PgLastFaultIsUser = 1 if the CPU-pushed fault CS has RPL 3, else 0.
;--------------------------------------------------------------------------------------------------
PgClassifyFault:
  mov   dword[PgLastFaultIsUser],0
  mov   ebx,[PgFaultFrameEsp]
  test  ebx,ebx
  jz    PgClassifyFaultDone
  movzx eax,word[ebx+8]
  mov   [PgFaultCs],eax
  and   eax,00000003h
  cmp   eax,3
  jne   PgClassifyFaultDone
  mov   dword[PgLastFaultIsUser],1
PgClassifyFaultDone:
  ret
