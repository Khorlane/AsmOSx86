;**************************************************************************************************
; Kc.asm
;   Kernel Call Interface core for AsmOSx86
;
; Purpose
;   Provide memory-backed kernel-call dispatcher.
;
;   Kernel tests may call KcDispatch directly through the global Kc fields.
;   Userland enters through KcUserDispatch, which copies arguments/results
;   through the current task's KcBlock.
;
;   The contract is intentionally shaped as the user/kernel service boundary.
;
; Contains
;   - Global kernel-call communication fields
;   - Kernel-call status constants
;   - Kernel-call service numbers
;   - Dispatch, validation, and lookup logic
;   - Ring 3 interrupt-gate entry
;   - Small initial service handlers for testing the boundary
;
; Public API
;   - KcInit
;   - KcDispatch
;   - KcUserDispatch
;
; Notes
;   - Kernel calls use memory-backed inputs and outputs.
;   - Registers are scratch only.
;   - User programs must not call subsystem routines directly in the future.
;   - KcDispatch is for kernel-originated calls and may receive kernel pointers.
;   - KcUserDispatch is for user-originated calls and must validate user pointers.
;   - Handler routines are internal dispatch-table entries.
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
KcFsOpen           equ 6
KcFsRead           equ 7
KcFsClose          equ 8
KcTmSleep          equ 9
KcKbRead           equ 10

;--------------------------------------------------------------------------------------------------
; Future User Kernel-Call Interrupt Constants
;--------------------------------------------------------------------------------------------------
KC_USER_INT_VECTOR equ 080h
KC_USER_INT_ATTR   equ 0EE00h           ; Present DPL 3 32-bit interrupt gate

;--------------------------------------------------------------------------------------------------
; User Kernel-Call Block Layout
;--------------------------------------------------------------------------------------------------
KC_BLOCK_NUMBER    equ 0
KC_BLOCK_STATUS    equ 4
KC_BLOCK_ARG0      equ 8
KC_BLOCK_ARG1      equ 12
KC_BLOCK_ARG2      equ 16
KC_BLOCK_ARG3      equ 20
KC_BLOCK_RESULT0   equ 24
KC_BLOCK_RESULT1   equ 28

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
KcCallFromUser     dd 0                 ; 1 while dispatching a user KcBlock call
KcInterruptEnabled dd 1                 ; input: 1 enables non-switching int 80h path
KcInterruptEntered dd 0                 ; debug: count of int 80h entries
KcInterruptRejected dd 0                ; debug: count of rejected int 80h calls
KcHandler          dd 0                 ; work: resolved handler address
pKcTable           dd 0                 ; work: current table entry pointer
KcTableLeft        dd 0                 ; work: remaining table entries
KcIdtEntry         dd 0                 ; work: selected IDT entry pointer

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
  dd KcFsOpen,      KcFsOpenHandler
  dd KcFsRead,      KcFsReadHandler
  dd KcFsClose,     KcFsCloseHandler
  dd KcTmSleep,     KcTmSleepHandler
  dd KcKbRead,      KcKbReadHandler
KcTableEnd:
KcTableCount equ (KcTableEnd-KcTable)/8

;--------------------------------------------------------------------------------------------------
; External Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; KcInit
;   Output:
;     Installs the ring 3 kernel-call interrupt gate.
;   Notes:
;     User programs enter the kernel through int 80h. Switching and blocking
;     calls use interrupt-aware task routines.
;--------------------------------------------------------------------------------------------------
KcInit:
  mov   eax,KC_USER_INT_VECTOR
  mov   ebx,8
  mul   ebx
  lea   edi,[IDT1+eax]
  mov   [KcIdtEntry],edi
  mov   eax,KcUserInterruptEntry
  mov   [edi],ax
  mov   ax,CODE_DESC
  mov   [edi+2],ax
  mov   ax,KC_USER_INT_ATTR
  mov   [edi+4],ax
  mov   eax,KcUserInterruptEntry
  shr   eax,16
  mov   [edi+6],ax
  ret

;--------------------------------------------------------------------------------------------------
; KcDispatch
;   Input:
;     KcNumber = requested kernel call number
;     KcArg0..KcArg3 = service-specific arguments
;   Output:
;     KcStatus = KC_STATUS_OK or error
;     KcResult0..KcResult1 = service-specific results
;   Notes:
;     Kernel-originated dispatch path. Kernel callers may pass kernel pointers.
;     Userland must enter through KcUserDispatch so pointer validation can run.
;--------------------------------------------------------------------------------------------------
KcDispatch:
  mov   dword[KcResult0],0
  mov   dword[KcResult1],0
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
; KcUserDispatch
;   Input:
;     Current task's TASK_KCBLOCK_PTR points to a 32-byte user kernel-call block.
;   Output:
;     Copies KcStatus/KcResult0/KcResult1 back to the current task's block when
;     the call returns to the same task.
;   Notes:
;     Fixed gateway entry lives at 00100005h in Kernel.asm.
;     User pointer arguments must be validated by service-specific handlers
;     before they are used as kernel addresses.
;--------------------------------------------------------------------------------------------------
KcUserDispatch:
  call  TaskGetCurrentRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    KcUserDispatchDone
  mov   esi,[edi+TASK_KCBLOCK_PTR]
  test  esi,esi
  jz    KcUserDispatchDone
  mov   eax,[esi+KC_BLOCK_NUMBER]
  cmp   eax,KcTsYield
  je    KcUserDispatchYield
  cmp   eax,KcTsExit
  je    KcUserDispatchExit
  cmp   eax,KcTmSleep
  je    KcUserDispatchSleep
  mov   [KcNumber],eax
  mov   eax,[esi+KC_BLOCK_ARG0]
  mov   [KcArg0],eax
  mov   eax,[esi+KC_BLOCK_ARG1]
  mov   [KcArg1],eax
  mov   eax,[esi+KC_BLOCK_ARG2]
  mov   [KcArg2],eax
  mov   eax,[esi+KC_BLOCK_ARG3]
  mov   [KcArg3],eax
  mov   dword[KcCallFromUser],1
  call  KcDispatch
  mov   dword[KcCallFromUser],0
  call  TaskGetCurrentRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    KcUserDispatchDone
  mov   esi,[edi+TASK_KCBLOCK_PTR]
  test  esi,esi
  jz    KcUserDispatchDone
  mov   eax,[KcStatus]
  mov   [esi+KC_BLOCK_STATUS],eax
  mov   eax,[KcResult0]
  mov   [esi+KC_BLOCK_RESULT0],eax
  mov   eax,[KcResult1]
  mov   [esi+KC_BLOCK_RESULT1],eax
KcUserDispatchDone:
  ret
KcUserDispatchYield:
  mov   dword[esi+KC_BLOCK_STATUS],KC_STATUS_OK
  call  TaskYield
  ret
KcUserDispatchExit:
  mov   eax,[esi+KC_BLOCK_ARG0]
  mov   [TaskExitCode],eax
  mov   dword[esi+KC_BLOCK_STATUS],KC_STATUS_OK
  call  TaskExit
  ret
KcUserDispatchSleep:
  mov   eax,[esi+KC_BLOCK_ARG0]
  mov   [TaskSleepMs],eax
  mov   dword[esi+KC_BLOCK_STATUS],KC_STATUS_OK
  mov   dword[esi+KC_BLOCK_RESULT0],0
  mov   dword[esi+KC_BLOCK_RESULT1],0
  call  TaskSleep
  ret

;--------------------------------------------------------------------------------------------------
; KcUserInterruptEntry
;   Output:
;     Returns from the future ring 3 kernel-call interrupt gate.
;   Notes:
;     Non-switching calls dispatch through the existing KcBlock path.
;     Scheduler/blocking calls use interrupt-aware task switch routines because
;     they may resume a different task instead of returning to the caller.
;--------------------------------------------------------------------------------------------------
KcUserInterruptEntry:
  mov   [TaskInterruptFrameEsp],esp
  mov   esi,0
  cmp   dword[KcInterruptEnabled],1
  jne   KcUserInterruptEntryDone
  inc   dword[KcInterruptEntered]
  call  TaskGetCurrentRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    KcUserInterruptReject
  mov   esi,[edi+TASK_KCBLOCK_PTR]
  test  esi,esi
  jz    KcUserInterruptReject
  mov   eax,[esi+KC_BLOCK_NUMBER]
  cmp   eax,KcTsYield
  je    KcUserInterruptYield
  cmp   eax,KcTsExit
  je    KcUserInterruptExit
  cmp   eax,KcTmSleep
  je    KcUserInterruptSleep
  cmp   eax,KcKbRead
  je    KcUserInterruptKeyRead
  call  KcUserDispatch
  jmp   KcUserInterruptEntryDone
KcUserInterruptYield:
  mov   dword[esi+KC_BLOCK_STATUS],KC_STATUS_OK
  call  TaskYieldFromInterrupt
  jmp   KcUserInterruptEntryDone
KcUserInterruptExit:
  mov   eax,[esi+KC_BLOCK_ARG0]
  mov   [TaskExitCode],eax
  mov   dword[esi+KC_BLOCK_STATUS],KC_STATUS_OK
  call  TaskExitFromInterrupt
  jmp   KcUserInterruptEntryDone
KcUserInterruptSleep:
  mov   eax,[esi+KC_BLOCK_ARG0]
  mov   [TaskSleepMs],eax
  mov   dword[esi+KC_BLOCK_STATUS],KC_STATUS_OK
  mov   dword[esi+KC_BLOCK_RESULT0],0
  mov   dword[esi+KC_BLOCK_RESULT1],0
  call  TaskSleepFromInterrupt
  jmp   KcUserInterruptEntryDone
KcUserInterruptKeyRead:
  call  TaskKeyboardReadFromInterrupt
  mov   eax,[TaskKeyType]
  mov   [esi+KC_BLOCK_RESULT0],eax
  mov   eax,[TaskKeyChar]
  mov   [esi+KC_BLOCK_RESULT1],eax
  mov   dword[esi+KC_BLOCK_STATUS],KC_STATUS_OK
  jmp   KcUserInterruptEntryDone
KcUserInterruptReject:
  inc   dword[KcInterruptRejected]
  test  esi,esi
  jz    KcUserInterruptEntryDone
  mov   dword[esi+KC_BLOCK_STATUS],KC_STATUS_INVALID
KcUserInterruptEntryDone:
  iretd

;--------------------------------------------------------------------------------------------------
; Internal Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; KcValidate
;   Input:
;     KcNumber = requested kernel call number
;   Output:
;     KcStatus = KC_STATUS_OK if basic validation succeeds, else error
;   Notes:
;     Basic validation rejects call number zero.
;     KcLookup rejects unknown nonzero call numbers.
;     Service handlers validate their own argument shape and user pointers.
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
; KcValidateUserStrArg0
;   Input:
;     KcArg0 = Str pointer.
;   Output:
;     KcStatus = KC_STATUS_OK or KC_STATUS_BAD_ARG.
;   Notes:
;     Kernel-originated KcDispatch calls skip user range checks.
;--------------------------------------------------------------------------------------------------
KcValidateUserStrArg0:
  mov   dword[KcStatus],KC_STATUS_OK
  mov   eax,[KcCallFromUser]
  test  eax,eax
  jz    KcValidateUserStrArg0Done
  mov   eax,[KcArg0]
  mov   [TaskUserPtr],eax
  mov   dword[TaskUserSize],2
  call  TaskValidateUserRange
  mov   eax,[TaskUserOk]
  test  eax,eax
  jz    KcValidateUserStrArg0Bad
  mov   esi,[KcArg0]
  movzx eax,word[esi]
  add   eax,2
  mov   [TaskUserSize],eax
  call  TaskValidateUserRange
  mov   eax,[TaskUserOk]
  test  eax,eax
  jz    KcValidateUserStrArg0Bad
  mov   dword[KcStatus],KC_STATUS_OK
  ret
KcValidateUserStrArg0Bad:
  mov   dword[KcStatus],KC_STATUS_BAD_ARG
KcValidateUserStrArg0Done:
  ret

;--------------------------------------------------------------------------------------------------
; KcValidateUserReadBuffer
;   Input:
;     KcArg1 = destination buffer pointer.
;     KcArg2 = requested byte count.
;   Output:
;     KcStatus = KC_STATUS_OK or KC_STATUS_BAD_ARG.
;   Notes:
;     Kernel-originated KcDispatch calls skip user range checks.
;--------------------------------------------------------------------------------------------------
KcValidateUserReadBuffer:
  mov   dword[KcStatus],KC_STATUS_OK
  mov   eax,[KcCallFromUser]
  test  eax,eax
  jz    KcValidateUserReadBufferDone
  mov   eax,[KcArg1]
  mov   [TaskUserPtr],eax
  mov   eax,[KcArg2]
  mov   [TaskUserSize],eax
  call  TaskValidateUserRange
  mov   eax,[TaskUserOk]
  test  eax,eax
  jnz   KcValidateUserReadBufferDone
  mov   dword[KcStatus],KC_STATUS_BAD_ARG
KcValidateUserReadBufferDone:
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
; KcTmSleepHandler
;   Input:
;     KcArg0 = sleep duration in milliseconds.
;   Output:
;     KcStatus  = KC_STATUS_OK.
;     KcResult0 = 0.
;     KcResult1 = 0.
;   Notes:
;     Cooperative sleep blocks the current task and resumes when a later
;     scheduler pass observes that the wake deadline has passed.
;--------------------------------------------------------------------------------------------------
KcTmSleepHandler:
  mov   eax,[KcArg0]
  mov   [TaskSleepMs],eax
  mov   dword[KcResult0],0
  mov   dword[KcResult1],0
  mov   dword[KcStatus],KC_STATUS_OK
  call  TaskSleep
  ret

;--------------------------------------------------------------------------------------------------
; KcKbReadHandler
;   Output:
;     KcStatus  = KC_STATUS_OK or KC_STATUS_BAD_ARG.
;     KcResult0 = KEY_* event type.
;     KcResult1 = ASCII character for KEY_CHAR, otherwise 0.
;   Notes:
;     User-originated calls block cooperatively until one key event is available.
;--------------------------------------------------------------------------------------------------
KcKbReadHandler:
  mov   eax,[KcCallFromUser]
  test  eax,eax
  jz    KcKbReadHandlerBad
  call  TaskKeyboardRead
  mov   eax,[TaskKeyType]
  mov   [KcResult0],eax
  mov   eax,[TaskKeyChar]
  mov   [KcResult1],eax
  mov   dword[KcStatus],KC_STATUS_OK
  ret
KcKbReadHandlerBad:
  mov   dword[KcResult0],KEY_NONE
  mov   dword[KcResult1],0
  mov   dword[KcStatus],KC_STATUS_BAD_ARG
  ret

;--------------------------------------------------------------------------------------------------
; KcVdWriteStrHandler
;   Input:
;     KcArg0 = pointer to kernel Str
;   Output:
;     KcStatus = KC_STATUS_OK or KC_STATUS_BAD_ARG
;   Notes:
;     Userland pointers must be inside the caller's user virtual range.
;--------------------------------------------------------------------------------------------------
KcVdWriteStrHandler:
  mov   eax,[KcArg0]
  test  eax,eax
  jz    KcVdWriteStrHandler1
  call  KcValidateUserStrArg0
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   KcVdWriteStrHandler1
  mov   eax,[KcArg0]
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
;     KcArg0 = pointer to kernel Str filename.
;     KcArg1 = task table index to prepare.
;     KcArg2 = stack slot index to assign.
;   Output:
;     KcStatus  = KC_STATUS_OK or KC_STATUS_BAD_ARG
;     KcResult0 = TaskProgramStatus
;     KcResult1 = 0
;   Notes:
;     Loads a raw user program from the filesystem and prepares a task.
;--------------------------------------------------------------------------------------------------
KcTsLoadProgramHandler:
  mov   eax,[KcArg0]
  test  eax,eax
  jz    KcTsLoadProgramHandler1
  call  KcValidateUserStrArg0
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   KcTsLoadProgramHandler1
  mov   eax,[KcArg0]
  mov   [pTaskProgramName],eax
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

;--------------------------------------------------------------------------------------------------
; KcFsOpenHandler
;   Input:
;     KcArg0 = pointer to kernel Str filename.
;   Output:
;     KcStatus  = KC_STATUS_OK or KC_STATUS_BAD_ARG
;     KcResult0 = FS_STATUS_*
;     KcResult1 = file handle, or 0.
;--------------------------------------------------------------------------------------------------
KcFsOpenHandler:
  mov   eax,[KcArg0]
  test  eax,eax
  jz    KcFsOpenHandler1
  call  KcValidateUserStrArg0
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   KcFsOpenHandler1
  mov   eax,[KcArg0]
  mov   [pFsOpenName],eax
  call  FsOpen
  mov   eax,[FsStatus]
  mov   [KcResult0],eax
  mov   eax,[FsOpenHandle]
  mov   [KcResult1],eax
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_BAD_ARG
  je    KcFsOpenHandler1
  mov   dword[KcStatus],KC_STATUS_OK
  ret
KcFsOpenHandler1:
  mov   dword[KcResult0],FS_STATUS_BAD_ARG
  mov   dword[KcResult1],0
  mov   dword[KcStatus],KC_STATUS_BAD_ARG
  ret

;--------------------------------------------------------------------------------------------------
; KcFsReadHandler
;   Input:
;     KcArg0 = file handle.
;     KcArg1 = destination buffer.
;     KcArg2 = requested byte count.
;   Output:
;     KcStatus  = KC_STATUS_OK or KC_STATUS_BAD_ARG
;     KcResult0 = FS_STATUS_*
;     KcResult1 = bytes read.
;--------------------------------------------------------------------------------------------------
KcFsReadHandler:
  mov   eax,[KcArg0]
  test  eax,eax
  jz    KcFsReadHandler1
  mov   [FsReadHandle],eax
  mov   eax,[KcArg1]
  test  eax,eax
  jz    KcFsReadHandler1
  mov   [pFsReadBuffer],eax
  mov   eax,[KcArg2]
  test  eax,eax
  jz    KcFsReadHandler1
  call  KcValidateUserReadBuffer
  mov   eax,[KcStatus]
  cmp   eax,KC_STATUS_OK
  jne   KcFsReadHandler1
  mov   eax,[KcArg2]
  mov   [FsReadCount],eax
  call  FsRead
  mov   eax,[FsStatus]
  mov   [KcResult0],eax
  mov   eax,[FsReadBytes]
  mov   [KcResult1],eax
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_BAD_ARG
  je    KcFsReadHandler1
  mov   dword[KcStatus],KC_STATUS_OK
  ret
KcFsReadHandler1:
  mov   dword[KcResult0],FS_STATUS_BAD_ARG
  mov   dword[KcResult1],0
  mov   dword[KcStatus],KC_STATUS_BAD_ARG
  ret

;--------------------------------------------------------------------------------------------------
; KcFsCloseHandler
;   Input:
;     KcArg0 = file handle.
;   Output:
;     KcStatus  = KC_STATUS_OK
;     KcResult0 = FS_STATUS_*
;     KcResult1 = 0.
;--------------------------------------------------------------------------------------------------
KcFsCloseHandler:
  mov   eax,[KcArg0]
  test  eax,eax
  jz    KcFsCloseHandler1
  mov   [FsCloseHandle],eax
  call  FsClose
  mov   eax,[FsStatus]
  mov   [KcResult0],eax
  mov   dword[KcResult1],0
  mov   dword[KcStatus],KC_STATUS_OK
  ret
KcFsCloseHandler1:
  mov   dword[KcResult0],FS_STATUS_BAD_HANDLE
  mov   dword[KcResult1],0
  mov   dword[KcStatus],KC_STATUS_BAD_ARG
  ret
