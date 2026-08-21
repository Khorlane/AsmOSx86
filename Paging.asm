;**************************************************************************************************
; Paging.asm
;   Early paging setup for AsmOSx86.
;
; Purpose
;   Provide the first protected-mode paging setup while preserving the current
;   flat physical memory behavior through identity mapping.
;
; Contains
;   - Page-fault IDT gate installation
;   - Identity-mapped page directory and page tables
;   - Shared user virtual page-range remapping
;   - CR3/CR0 paging enable path
;   - Minimal page-fault halt handler
;
; Notes
;   - Maps the first 16 MiB as present, writable, supervisor pages.
;   - The shared user virtual range can be remapped to task image pages.
;   - Paging does not enable hardware IRQs.
;   - Page faults currently halt forever.
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; Paging Constants
;--------------------------------------------------------------------------------------------------
PG_PRESENT      equ 00000001h
PG_WRITABLE     equ 00000002h
PG_KERNEL_FLAGS equ PG_PRESENT|PG_WRITABLE
PG_USER_FLAGS   equ PG_PRESENT|PG_WRITABLE
PG_KCBLOCK_FLAGS equ PG_PRESENT|PG_WRITABLE
PG_PAGE_SIZE    equ 00001000h
PG_ENTRY_COUNT  equ 1024
PG_CR0_ENABLE   equ 80000000h
PG_FAULT_VECTOR equ 14
PG_IDT_ATTR     equ 08E00h
PG_USER_PTE     equ 512
PG_USER_MAX_PAGES equ 16
PG_USER_KC_PTE  equ PG_USER_PTE+PG_USER_MAX_PAGES

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
  call  PgInstallPageFaultGate
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
; PgInstallPageFaultGate
;   Output:
;     IDT vector 14 points to PgPageFault.
;--------------------------------------------------------------------------------------------------
PgInstallPageFaultGate:
  mov   edi,IDT1+(PG_FAULT_VECTOR*8)
  mov   eax,PgPageFault
  mov   [edi],ax
  mov   ax,CODE_DESC
  mov   [edi+2],ax
  mov   ax,PG_IDT_ATTR
  mov   [edi+4],ax
  mov   eax,PgPageFault
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
  or    eax,PG_KERNEL_FLAGS
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
; PgPageFault
;   Output:
;     Halts forever after a page fault.
;--------------------------------------------------------------------------------------------------
PgPageFault:
  cli
PgPageFault1:
  hlt
  jmp   PgPageFault1
