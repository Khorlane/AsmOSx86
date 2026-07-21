;**************************************************************************************************
; Task.asm
;   Cooperative task metadata and stack-slot support for AsmOSx86.
;
; Purpose
;   Provide the first kernel-owned task table and fixed low-memory stack-slot model.
;
; Contains
;   - Task state constants
;   - Task record layout constants
;   - Task table storage
;   - Helpers for resolving task records and stack-slot bounds
;   - File-backed user-program loading plumbing
;
; Notes
;   - Task metadata is kernel-owned.
;   - Task stacks live in the low-memory stack-slot arena.
;   - Registers are scratch only.
;   - Persistent inputs/outputs use Task* globals.
;**************************************************************************************************

[bits 32]

;--------------------------------------------------------------------------------------------------
; Task State Constants
;--------------------------------------------------------------------------------------------------
TASK_STATE_FREE      equ 0
TASK_STATE_READY     equ 1
TASK_STATE_RUNNING   equ 2
TASK_STATE_BLOCKED   equ 3
TASK_STATE_EXITED    equ 4

;--------------------------------------------------------------------------------------------------
; Task Record Layout
;--------------------------------------------------------------------------------------------------
TASK_STATE           equ 0
TASK_SAVED_ESP       equ 4
TASK_STACK_SLOT      equ 8
TASK_STACK_BOTTOM    equ 12
TASK_STACK_TOP       equ 16
TASK_ENTRY           equ 20
TASK_KCBLOCK_PTR     equ 24
TASK_EXIT_CODE       equ 28
TASK_RUN_COUNT       equ 32
TASK_RECORD_SIZE     equ 36

;--------------------------------------------------------------------------------------------------
; Task Table and Stack-Slot Constants
;--------------------------------------------------------------------------------------------------
MAX_TASKS            equ 8
STACK_SLOT_SIZE      equ 00001000h
STACK_ARENA_TOP      equ 00090000h
STACK_ARENA_BOTTOM   equ 00001000h
STACK_SLOT_COUNT     equ 143

;--------------------------------------------------------------------------------------------------
; User Program Loader Constants
;--------------------------------------------------------------------------------------------------
TASK_PROGRAM_STATUS_OK          equ 0
TASK_PROGRAM_STATUS_NOT_FOUND   equ 1
TASK_PROGRAM_STATUS_BAD_TASK    equ 2
TASK_PROGRAM_STATUS_BAD_STACK   equ 3
TASK_PROGRAM_STATUS_BAD_IMAGE   equ 4
TASK_PROGRAM_STATUS_FS_ERROR    equ 5
USER_PROGRAM_LOAD_BASE          equ 00200000h
USER_PROGRAM_SLOT_SIZE          equ 00001000h
USER_PROGRAM1_LOAD_BASE         equ USER_PROGRAM_LOAD_BASE
USER_PROGRAM2_LOAD_BASE         equ USER_PROGRAM_LOAD_BASE+USER_PROGRAM_SLOT_SIZE
USER_PROGRAM3_LOAD_BASE         equ USER_PROGRAM_LOAD_BASE+(USER_PROGRAM_SLOT_SIZE*2)
USER_PROGRAM_KCBLOCK_SIZE       equ 32
USER_PROGRAM_IMAGE_SIZE         equ USER_PROGRAM_SLOT_SIZE-USER_PROGRAM_KCBLOCK_SIZE

;--------------------------------------------------------------------------------------------------
; Task Globals
;--------------------------------------------------------------------------------------------------
align 4
TaskCurrentIndex     dd 0               ; current task index
TaskNextIndex        dd 0               ; next task index
TaskIndex            dd 0               ; input: task index for lookup helpers
TaskScanIndex        dd 0               ; work: scheduler table scan index
TaskScanLeft         dd 0               ; work: scheduler entries left to scan
TaskStackSlot        dd 0               ; input: stack slot index
TaskStackBottom      dd 0               ; output: stack slot bottom address
TaskStackTop         dd 0               ; output: stack slot top address
pTaskRecord          dd 0               ; output: selected task record pointer
TaskPut4DecVal       dd 0               ; input: value 0..9999
pTaskPut4DecDst      dd 0               ; input: destination payload pointer
TaskInitPtr          dd 0               ; work: table clear pointer
TaskInitLeft         dd 0               ; work: table clear byte count
pTaskProgramName     dd 0               ; input: pointer to kernel Str filename
TaskProgramTaskIndex dd 0               ; input: task table index to prepare
TaskProgramStackSlot dd 0               ; input: stack slot index to assign
TaskProgramStatus    dd 0               ; output: TASK_PROGRAM_STATUS_*
TaskProgramEntryPtr  dd 0               ; output: loaded program entry address
TaskProgramKcBlockPtr dd 0              ; output: loaded program KcBlock address
TaskProgramLoadBase  dd 0               ; work: selected program load base
TaskProgramHandle    dd 0               ; work: open file handle
TaskProgramClearPtr   dd 0              ; work: user slot clear pointer
TaskProgramClearLeft  dd 0              ; work: user slot clear byte count
TaskExitCode         dd 0               ; input: current task exit code
String  TaskProgramExitStr1,"Task 1 exit 0000"
String  TaskProgramExitStr2,"Task 2 exit 0000"
String  TaskProgramExitStr3,"Task 3 exit 0000"
TaskTable:
  times MAX_TASKS * TASK_RECORD_SIZE db 0

;--------------------------------------------------------------------------------------------------
; TaskGetRecord
;   Input:
;     TaskIndex = task index, 0..MAX_TASKS-1.
;   Output:
;     pTaskRecord = selected task record, or 0 if TaskIndex is invalid.
;--------------------------------------------------------------------------------------------------
TaskGetRecord:
  mov   dword[pTaskRecord],0
  mov   eax,[TaskIndex]
  cmp   eax,MAX_TASKS
  jae   TaskGetRecordDone
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  mov   [pTaskRecord],edi
TaskGetRecordDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskGetCurrentRecord
;   Output:
;     pTaskRecord = current task record, or 0 if TaskCurrentIndex is invalid.
;--------------------------------------------------------------------------------------------------
TaskGetCurrentRecord:
  mov   eax,[TaskCurrentIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  ret

;--------------------------------------------------------------------------------------------------
; TaskGetNextRecord
;   Output:
;     pTaskRecord = next task record, or 0 if TaskNextIndex is invalid.
;--------------------------------------------------------------------------------------------------
TaskGetNextRecord:
  mov   eax,[TaskNextIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  ret

;--------------------------------------------------------------------------------------------------
; TaskGetStackBounds
;   Input:
;     TaskStackSlot = stack slot index, 0..STACK_SLOT_COUNT-1.
;   Output:
;     TaskStackTop    = exclusive top address for the slot, or 0 if invalid.
;     TaskStackBottom = inclusive bottom address for the slot, or 0 if invalid.
;   Notes:
;     Slot 0 is the kernel stack. Later slots may be assigned to resident tasks.
;--------------------------------------------------------------------------------------------------
TaskGetStackBounds:
  mov   dword[TaskStackTop],0
  mov   dword[TaskStackBottom],0
  mov   eax,[TaskStackSlot]
  cmp   eax,STACK_SLOT_COUNT
  jae   TaskGetStackBoundsDone
  mov   ebx,STACK_SLOT_SIZE
  mul   ebx
  mov   ebx,STACK_ARENA_TOP
  sub   ebx,eax
  mov   [TaskStackTop],ebx
  sub   ebx,STACK_SLOT_SIZE
  mov   [TaskStackBottom],ebx
TaskGetStackBoundsDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskPut4Dec
;   Input:
;     TaskPut4DecVal  = value 0..9999.
;     pTaskPut4DecDst = destination payload pointer.
;   Output:
;     [pTaskPut4DecDst original..original+3] = four ASCII decimal digits.
;--------------------------------------------------------------------------------------------------
TaskPut4Dec:
  mov   edi,[pTaskPut4DecDst]
  mov   eax,[TaskPut4DecVal]
  xor   edx,edx
  mov   ebx,1000
  div   ebx
  add   al,'0'
  mov   [edi],al
  mov   eax,edx
  xor   edx,edx
  mov   ebx,100
  div   ebx
  add   al,'0'
  mov   [edi+1],al
  mov   eax,edx
  xor   edx,edx
  mov   ebx,10
  div   ebx
  add   al,'0'
  mov   [edi+2],al
  mov   al,dl
  add   al,'0'
  mov   [edi+3],al
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramLoad
;   Input:
;     pTaskProgramName     = pointer to kernel Str filename.
;     TaskProgramTaskIndex = task table index to prepare.
;     TaskProgramStackSlot = stack slot index to assign.
;   Output:
;     TaskProgramStatus     = TASK_PROGRAM_STATUS_*.
;     TaskProgramEntryPtr   = loaded program entry address.
;     TaskProgramKcBlockPtr = loaded program KcBlock address.
;   Notes:
;     Reads a flat user-program binary into a fixed user load slot and seeds a
;     ready task record. It does not start or schedule the task.
;--------------------------------------------------------------------------------------------------
TaskProgramLoad:
  mov   dword[TaskProgramEntryPtr],0
  mov   dword[TaskProgramKcBlockPtr],0
  mov   dword[TaskProgramLoadBase],0
  mov   dword[TaskProgramHandle],0
  mov   eax,[pTaskProgramName]
  test  eax,eax
  jz    TaskProgramLoad4
  mov   eax,[TaskProgramTaskIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskProgramLoad1
  mov   eax,[TaskProgramStackSlot]
  mov   [TaskStackSlot],eax
  call  TaskGetStackBounds
  mov   eax,[TaskStackTop]
  test  eax,eax
  jz    TaskProgramLoad2
  call  TaskProgramGetLoadBase
  mov   eax,[TaskProgramLoadBase]
  test  eax,eax
  jz    TaskProgramLoad4
  call  TaskProgramClearSlot
  mov   eax,[pTaskProgramName]
  mov   [pFsOpenName],eax
  call  FsOpen
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   TaskProgramLoad5
  mov   eax,[FsOpenHandle]
  mov   [TaskProgramHandle],eax
  mov   [FsReadHandle],eax
  mov   eax,[TaskProgramLoadBase]
  mov   [pFsReadBuffer],eax
  mov   dword[FsReadCount],USER_PROGRAM_IMAGE_SIZE
  call  FsRead
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   TaskProgramLoad6
  mov   edi,[pTaskRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
  mov   eax,[TaskProgramStackSlot]
  mov   [edi+TASK_STACK_SLOT],eax
  mov   eax,[TaskStackBottom]
  mov   [edi+TASK_STACK_BOTTOM],eax
  mov   eax,[TaskStackTop]
  mov   [edi+TASK_STACK_TOP],eax
  sub   eax,4
  mov   [edi+TASK_SAVED_ESP],eax
  mov   ebx,[TaskProgramLoadBase]
  mov   [TaskProgramEntryPtr],ebx
  mov   [eax],ebx
  mov   [edi+TASK_ENTRY],ebx
  mov   ebx,[TaskProgramLoadBase]
  add   ebx,USER_PROGRAM_SLOT_SIZE-USER_PROGRAM_KCBLOCK_SIZE
  mov   [TaskProgramKcBlockPtr],ebx
  mov   [edi+TASK_KCBLOCK_PTR],ebx
  mov   dword[edi+TASK_EXIT_CODE],0
  mov   dword[edi+TASK_RUN_COUNT],0
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_OK
  call  TaskProgramCloseFile
  jmp   TaskProgramLoad3
TaskProgramLoad1:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_TASK
  jmp   TaskProgramLoad3
TaskProgramLoad2:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_STACK
  jmp   TaskProgramLoad3
TaskProgramLoad4:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_IMAGE
  jmp   TaskProgramLoad3
TaskProgramLoad5:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_NOT_FOUND
  jmp   TaskProgramLoad3
TaskProgramLoad6:
  call  TaskProgramCloseFile
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_FS_ERROR
TaskProgramLoad3:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramGetLoadBase
;   Input:
;     TaskProgramTaskIndex = task index.
;   Output:
;     TaskProgramLoadBase = fixed load base, or 0 if the task index cannot map
;     to a user-program slot.
;--------------------------------------------------------------------------------------------------
TaskProgramGetLoadBase:
  mov   dword[TaskProgramLoadBase],0
  mov   eax,[TaskProgramTaskIndex]
  test  eax,eax
  jz    TaskProgramGetLoadBaseDone
  dec   eax
  cmp   eax,3
  jae   TaskProgramGetLoadBaseDone
  mov   ebx,USER_PROGRAM_SLOT_SIZE
  mul   ebx
  add   eax,USER_PROGRAM_LOAD_BASE
  mov   [TaskProgramLoadBase],eax
TaskProgramGetLoadBaseDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramCloseFile
;   Input:
;     TaskProgramHandle = open file handle, or 0.
;   Output:
;     Closes the file if a handle was opened.
;--------------------------------------------------------------------------------------------------
TaskProgramCloseFile:
  mov   eax,[TaskProgramHandle]
  test  eax,eax
  jz    TaskProgramCloseFileDone
  mov   [FsCloseHandle],eax
  call  FsClose
  mov   dword[TaskProgramHandle],0
TaskProgramCloseFileDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramClearSlot
;   Input:
;     TaskProgramLoadBase = selected user-program load base.
;   Output:
;     Clears the full 4K user-program slot.
;--------------------------------------------------------------------------------------------------
TaskProgramClearSlot:
  mov   eax,[TaskProgramLoadBase]
  mov   [TaskProgramClearPtr],eax
  mov   dword[TaskProgramClearLeft],USER_PROGRAM_SLOT_SIZE
TaskProgramClearSlot1:
  mov   eax,[TaskProgramClearLeft]
  test  eax,eax
  jz    TaskProgramClearSlotDone
  mov   edi,[TaskProgramClearPtr]
  mov   byte[edi],0
  inc   edi
  mov   [TaskProgramClearPtr],edi
  dec   eax
  mov   [TaskProgramClearLeft],eax
  jmp   TaskProgramClearSlot1
TaskProgramClearSlotDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramInit
;   Output:
;     Clears the task table and records the current kernel console context as task 0.
;   Notes:
;     Used by console-driven user-program smoke tests before loading mock images.
;--------------------------------------------------------------------------------------------------
TaskProgramInit:
  mov   eax,TaskTable
  mov   [TaskInitPtr],eax
  mov   eax,MAX_TASKS * TASK_RECORD_SIZE
  mov   [TaskInitLeft],eax
TaskProgramInit1:
  mov   eax,[TaskInitLeft]
  test  eax,eax
  jz    TaskProgramInit2
  mov   edi,[TaskInitPtr]
  mov   byte[edi],0
  inc   edi
  mov   [TaskInitPtr],edi
  mov   eax,[TaskInitLeft]
  dec   eax
  mov   [TaskInitLeft],eax
  jmp   TaskProgramInit1
TaskProgramInit2:
  mov   dword[TaskCurrentIndex],0
  mov   dword[TaskNextIndex],0
  mov   dword[TaskIndex],0
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_RUNNING
  mov   dword[edi+TASK_STACK_SLOT],0
  mov   dword[TaskStackSlot],0
  call  TaskGetStackBounds
  mov   eax,[TaskStackBottom]
  mov   [edi+TASK_STACK_BOTTOM],eax
  mov   eax,[TaskStackTop]
  mov   [edi+TASK_STACK_TOP],eax
  mov   [edi+TASK_SAVED_ESP],esp
  mov   dword[edi+TASK_ENTRY],0
  mov   dword[edi+TASK_KCBLOCK_PTR],0
  mov   dword[edi+TASK_EXIT_CODE],0
  mov   dword[edi+TASK_RUN_COUNT],0
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramStart
;   Output:
;     Starts cooperative dispatch of ready tasks and returns when task 0 is selected again.
;--------------------------------------------------------------------------------------------------
TaskProgramStart:
  call  TaskYield
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramPrintExitCodes
;   Output:
;     Prints recorded exit codes for user-test tasks 1, 2, and 3.
;   Notes:
;     Debug helper for the console-driven UserTest path.
;--------------------------------------------------------------------------------------------------
TaskProgramPrintExitCodes:
  mov   dword[TaskIndex],1
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  mov   eax,[edi+TASK_EXIT_CODE]
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskProgramExitStr1+14]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[TaskProgramExitStr1]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  mov   dword[TaskIndex],2
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  mov   eax,[edi+TASK_EXIT_CODE]
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskProgramExitStr2+14]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[TaskProgramExitStr2]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  mov   dword[TaskIndex],3
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  mov   eax,[edi+TASK_EXIT_CODE]
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskProgramExitStr3+14]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[TaskProgramExitStr3]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
  ret

;--------------------------------------------------------------------------------------------------
; TaskExit
;   Input:
;     TaskExitCode = current task exit code.
;   Output:
;     Marks the current task exited, records its exit code, and dispatches next ready task.
;--------------------------------------------------------------------------------------------------
TaskExit:
  mov   eax,[TaskCurrentIndex]
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  mov   eax,[TaskExitCode]
  mov   [edi+TASK_EXIT_CODE],eax
  mov   eax,[edi+TASK_RUN_COUNT]
  inc   eax
  mov   [edi+TASK_RUN_COUNT],eax
  mov   dword[edi+TASK_STATE],TASK_STATE_EXITED
  call  TaskYield
  ret

;--------------------------------------------------------------------------------------------------
; TaskYield
;   Output:
;     Saves the current task ESP, selects the next ready task, loads its ESP,
;     and returns through that task's saved stack.
;   Notes:
;     Low-level transition routine: intentionally saves and loads ESP.
;     Cooperative scheduler scans the task table in round-robin order.
;--------------------------------------------------------------------------------------------------
TaskYield:
  mov   eax,[TaskCurrentIndex]
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  mov   [edi+TASK_SAVED_ESP],esp
  cmp   dword[edi+TASK_STATE],TASK_STATE_EXITED
  je    TaskYield1
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
  mov   eax,[TaskCurrentIndex]
  inc   eax
  cmp   eax,MAX_TASKS
  jb    TaskYield2
  xor   eax,eax
  jmp   TaskYield2
TaskYield1:
  mov   eax,[TaskCurrentIndex]
  inc   eax
  cmp   eax,MAX_TASKS
  jb    TaskYield2
  xor   eax,eax
TaskYield2:
  mov   [TaskScanIndex],eax
  mov   dword[TaskScanLeft],MAX_TASKS
TaskYield3:
  mov   eax,[TaskScanLeft]
  test  eax,eax
  jz    TaskYield6
  mov   eax,[TaskScanIndex]
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  cmp   dword[edi+TASK_STATE],TASK_STATE_READY
  je    TaskYield5
  mov   eax,[TaskScanIndex]
  inc   eax
  cmp   eax,MAX_TASKS
  jb    TaskYield4
  xor   eax,eax
TaskYield4:
  mov   [TaskScanIndex],eax
  mov   eax,[TaskScanLeft]
  dec   eax
  mov   [TaskScanLeft],eax
  jmp   TaskYield3
TaskYield5:
  mov   eax,[TaskScanIndex]
  jmp   TaskYield7
TaskYield6:
  xor   eax,eax
TaskYield7:
  mov   [TaskNextIndex],eax
  mov   [TaskCurrentIndex],eax
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  mov   dword[edi+TASK_STATE],TASK_STATE_RUNNING
  mov   esp,[edi+TASK_SAVED_ESP]
  ret
