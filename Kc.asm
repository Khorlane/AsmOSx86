;**************************************************************************************************
; Kc.asm
;   Kernel Call Interface core for AsmOSx86
;
; Purpose
;   Provide the first memory-backed kernel-call dispatcher.
;
;   Userland does not exist yet, so this is currently callable from kernel
;   test paths only. The contract is intentionally shaped like the future
;   user/kernel service boundary.
;
; Contains
;   - Global kernel-call communication fields
;   - Kernel-call status constants
;   - Kernel-call service numbers
;   - Dispatch, validation, and lookup logic
;   - Small initial service handlers for testing the boundary
;
; Notes (LOCKED-IN)
;   - Kernel calls use memory-backed inputs and outputs.
;   - Registers are scratch only.
;   - User programs must not call subsystem routines directly in the future.
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; Kernel Call Status Constants
;--------------------------------------------------------------------------------------------------
KC_STATUS_OK       equ 0
KC_STATUS_INVALID  equ 1
KC_STATUS_BAD_ARG  equ 2

;--------------------------------------------------------------------------------------------------
; Kernel Call Numbers
;--------------------------------------------------------------------------------------------------
KcTmGetUptime      equ 1
KcVdWriteStr       equ 2
KcTsYield          equ 3
KcTsLoadProgram    equ 4
KcTsExit           equ 5

;--------------------------------------------------------------------------------------------------
; Kernel Call Communication Fields
;--------------------------------------------------------------------------------------------------
align 4
KcNumber           dd 0                 ; input: requested kernel call number
KcStatus           dd 0                 ; output: status code
KcArg0             dd 0                 ; input: argument 0
KcArg1             dd 0                 ; input: argument 1
KcArg2             dd 0                 ; input: argument 2
KcArg3             dd 0                 ; input: argument 3
KcResult0          dd 0                 ; output: result 0
KcResult1          dd 0                 ; output: result 1
KcHandler          dd 0                 ; work: resolved handler address
pKcTable           dd 0                 ; work: current table entry pointer
KcTableLeft        dd 0                 ; work: remaining table entries

;--------------------------------------------------------------------------------------------------
; Kernel Call Dispatch Table
;--------------------------------------------------------------------------------------------------
align 4
KcTable:
  dd KcTmGetUptime, KcTmGetUptimeHandler
  dd KcVdWriteStr,  KcVdWriteStrHandler
  dd KcTsYield,     KcTsYieldHandler
  dd KcTsLoadProgram,KcTsLoadProgramHandler
  dd KcTsExit,      KcTsExitHandler
KcTableEnd:
KcTableCount equ (KcTableEnd-KcTable)/8

;--------------------------------------------------------------------------------------------------
; KcDispatch
;   Input:
;     KcNumber = requested kernel call number
;     KcArg0..KcArg3 = service-specific arguments
;   Output:
;     KcStatus = KC_STATUS_OK or error
;     KcResult0..KcResult1 = service-specific results
;   Notes:
;     Dispatches through KcTable after validation and lookup.
;--------------------------------------------------------------------------------------------------
KcDispatch:
  call  KcValidate
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   KcDispatchDone
  call  KcLookup
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   KcDispatchDone
  mov   eax,[KcHandler]
  call  eax
KcDispatchDone:
  ret

;--------------------------------------------------------------------------------------------------
; KcValidate
;   Input:
;     KcNumber = requested kernel call number
;   Output:
;     KcStatus = KC_STATUS_OK if basic validation succeeds, else error
;   Notes:
;     Current validation only rejects call number zero.
;     Future validation should check caller/task state and argument ranges.
;--------------------------------------------------------------------------------------------------
KcValidate:
  mov   dword[KcStatus],KC_STATUS_INVALID
  mov   eax,[KcNumber]
  test  eax,eax
  jz    KcValidateDone
  mov   dword[KcStatus],KC_STATUS_OK
KcValidateDone:
  ret

;--------------------------------------------------------------------------------------------------
; KcLookup
;   Input:
;     KcNumber = requested kernel call number
;   Output:
;     KcStatus  = KC_STATUS_OK if found, else KC_STATUS_INVALID
;     KcHandler = handler address if found, else 0
;   Notes:
;     Linear scan is intentional for the first skeleton.
;--------------------------------------------------------------------------------------------------
KcLookup:
  mov   dword[KcStatus],KC_STATUS_INVALID
  mov   dword[KcHandler],0
  mov   eax,KcTable
  mov   [pKcTable],eax
  mov   eax,KcTableCount
  mov   [KcTableLeft],eax
KcLookup1:
  mov   eax,[KcTableLeft]
  test  eax,eax
  jz    KcLookupDone
  mov   edi,[pKcTable]
  mov   eax,[edi]
  cmp   eax,[KcNumber]
  je    KcLookup2
  add   edi,8
  mov   [pKcTable],edi
  mov   eax,[KcTableLeft]
  dec   eax
  mov   [KcTableLeft],eax
  jmp   KcLookup1
KcLookup2:
  mov   eax,[edi+4]
  mov   [KcHandler],eax
  mov   dword[KcStatus],KC_STATUS_OK
KcLookupDone:
  ret

;--------------------------------------------------------------------------------------------------
; KcTmGetUptimeHandler
;   Output:
;     KcStatus  = KC_STATUS_OK
;     KcResult0 = uptime seconds
;     KcResult1 = 0
;   Notes:
;     Wraps UptimeNow through the kernel-call boundary.
;--------------------------------------------------------------------------------------------------
KcTmGetUptimeHandler:
  call  UptimeNow
  mov   eax,[UptimeOutSec]
  mov   [KcResult0],eax
  mov   dword[KcResult1],0
  mov   dword[KcStatus],KC_STATUS_OK
  ret

;--------------------------------------------------------------------------------------------------
; KcVdWriteStrHandler
;   Input:
;     KcArg0 = pointer to kernel Str
;   Output:
;     KcStatus = KC_STATUS_OK or KC_STATUS_BAD_ARG
;   Notes:
;     Current early version trusts the pointer if nonzero.
;     Future userland version must validate that the pointer is inside caller memory.
;--------------------------------------------------------------------------------------------------
KcVdWriteStrHandler:
  mov   eax,[KcArg0]
  test  eax,eax
  jz    KcVdWriteStrHandler1
  mov   [pVdStr],eax
  call  VdPutStr
  mov   dword[KcStatus],KC_STATUS_OK
  ret
KcVdWriteStrHandler1:
  mov   dword[KcStatus],KC_STATUS_BAD_ARG
  ret

;--------------------------------------------------------------------------------------------------
; KcTsYieldHandler
;   Output:
;     KcStatus = KC_STATUS_OK
;   Notes:
;     Marks a cooperative scheduling point and lets TaskYield switch stacks.
;--------------------------------------------------------------------------------------------------
KcTsYieldHandler:
  mov   dword[KcStatus],KC_STATUS_OK
  call  TaskYield
  ret

;--------------------------------------------------------------------------------------------------
; KcTsLoadProgramHandler
;   Input:
;     KcArg0 = mock program id.
;     KcArg1 = task table index to prepare.
;     KcArg2 = stack slot index to assign.
;   Output:
;     KcStatus  = KC_STATUS_OK or KC_STATUS_BAD_ARG
;     KcResult0 = TaskProgramStatus
;     KcResult1 = 0
;   Notes:
;     Loads a kernel-resident mock program image into the fixed user slot.
;--------------------------------------------------------------------------------------------------
KcTsLoadProgramHandler:
  mov   eax,[KcArg0]
  mov   [TaskProgramId],eax
  mov   eax,[KcArg1]
  mov   [TaskProgramTaskIndex],eax
  mov   eax,[KcArg2]
  mov   [TaskProgramStackSlot],eax
  call  TaskProgramLoad
  mov   eax,[TaskProgramStatus]
  mov   [KcResult0],eax
  mov   dword[KcResult1],0
  test  eax,eax
  jnz   KcTsLoadProgramHandler1
  mov   dword[KcStatus],KC_STATUS_OK
  ret
KcTsLoadProgramHandler1:
  mov   dword[KcStatus],KC_STATUS_BAD_ARG
  ret

;--------------------------------------------------------------------------------------------------
; KcTsExitHandler
;   Input:
;     KcArg0 = task exit code.
;   Output:
;     Does not normally return to the exiting task.
;   Notes:
;     Records the exit code and dispatches the next ready task.
;--------------------------------------------------------------------------------------------------
KcTsExitHandler:
  mov   eax,[KcArg0]
  mov   [TaskExitCode],eax
  mov   dword[KcStatus],KC_STATUS_OK
  call  TaskExit
  ret
