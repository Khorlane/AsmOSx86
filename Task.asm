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
;   - Mock user-program image loading plumbing
;   - Kernel-resident task-switch POC payloads
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
; Mock User Program Loader Constants
;--------------------------------------------------------------------------------------------------
TASK_PROGRAM_STATUS_OK          equ 0
TASK_PROGRAM_STATUS_NOT_FOUND   equ 1
TASK_PROGRAM_STATUS_BAD_TASK    equ 2
TASK_PROGRAM_STATUS_BAD_STACK   equ 3
TASK_PROGRAM_STATUS_BAD_IMAGE   equ 4
TASK_PROGRAM_ID                 equ 0
TASK_PROGRAM_SOURCE             equ 4
TASK_PROGRAM_SIZE               equ 8
TASK_PROGRAM_LOAD_BASE          equ 12
TASK_PROGRAM_ENTRY_OFFSET       equ 16
TASK_PROGRAM_KCBLOCK_OFFSET     equ 20
TASK_PROGRAM_RECORD_SIZE        equ 24
TASK_PROGRAM_TABLE_COUNT        equ 3
USER_PROGRAM_LOAD_BASE          equ 00200000h
USER_PROGRAM_SLOT_SIZE          equ 00001000h
USER_PROGRAM1_LOAD_BASE         equ USER_PROGRAM_LOAD_BASE
USER_PROGRAM2_LOAD_BASE         equ USER_PROGRAM_LOAD_BASE+USER_PROGRAM_SLOT_SIZE
USER_PROGRAM3_LOAD_BASE         equ USER_PROGRAM_LOAD_BASE+(USER_PROGRAM_SLOT_SIZE*2)
USER_PROGRAM_KCBLOCK_SIZE       equ 32

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
TaskProgramId        dd 0               ; input: mock program id to load
TaskProgramTaskIndex dd 0               ; input: task table index to prepare
TaskProgramStackSlot dd 0               ; input: stack slot index to assign
TaskProgramStatus    dd 0               ; output: TASK_PROGRAM_STATUS_*
pTaskProgramRecord   dd 0               ; output/work: selected program table record
pTaskProgramScan     dd 0               ; work: program table scan pointer
TaskProgramLeft      dd 0               ; work: program table entries left
TaskProgramEntryPtr  dd 0               ; output: loaded program entry address
TaskProgramKcBlockPtr dd 0              ; output: loaded program KcBlock address
TaskExitCode         dd 0               ; input: current task exit code
String  TaskProgramExitStr1,"Task 1 exit 0000"
String  TaskProgramExitStr2,"Task 2 exit 0000"
String  TaskProgramExitStr3,"Task 3 exit 0000"
TaskProgramTable:
  dd 1,TaskProgram1Image,TaskProgram1ImageEnd-TaskProgram1Image
  dd USER_PROGRAM1_LOAD_BASE,0,TaskProgram1KcBlock-TaskProgram1Image
  dd 2,TaskProgram2Image,TaskProgram2ImageEnd-TaskProgram2Image
  dd USER_PROGRAM2_LOAD_BASE,0,TaskProgram2KcBlock-TaskProgram2Image
  dd 3,TaskProgram3Image,TaskProgram3ImageEnd-TaskProgram3Image
  dd USER_PROGRAM3_LOAD_BASE,0,TaskProgram3KcBlock-TaskProgram3Image
TaskProgram1Image:
  mov   dword[KcNumber],KcTsExit
  mov   dword[KcArg0],55
  mov   eax,KcDispatch
  call  eax
TaskProgram1Image1:
  jmp   TaskProgram1Image1
TaskProgram1KcBlock:
  times USER_PROGRAM_KCBLOCK_SIZE db 0
TaskProgram1ImageEnd:
TaskProgram2Image:
  mov   dword[KcNumber],KcTsExit
  mov   dword[KcArg0],155
  mov   eax,KcDispatch
  call  eax
TaskProgram2Image1:
  jmp   TaskProgram2Image1
TaskProgram2KcBlock:
  times USER_PROGRAM_KCBLOCK_SIZE db 0
TaskProgram2ImageEnd:
TaskProgram3Image:
  mov   dword[KcNumber],KcTsExit
  mov   dword[KcArg0],255
  mov   eax,KcDispatch
  call  eax
TaskProgram3Image1:
  jmp   TaskProgram3Image1
TaskProgram3KcBlock:
  times USER_PROGRAM_KCBLOCK_SIZE db 0
TaskProgram3ImageEnd:
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
; TaskProgramFind
;   Input:
;     TaskProgramId = mock program id to find.
;   Output:
;     TaskProgramStatus  = TASK_PROGRAM_STATUS_OK or TASK_PROGRAM_STATUS_NOT_FOUND.
;     pTaskProgramRecord = selected program record, or 0 if not found.
;--------------------------------------------------------------------------------------------------
TaskProgramFind:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_NOT_FOUND
  mov   dword[pTaskProgramRecord],0
  mov   eax,TaskProgramTable
  mov   [pTaskProgramScan],eax
  mov   dword[TaskProgramLeft],TASK_PROGRAM_TABLE_COUNT
TaskProgramFind1:
  mov   eax,[TaskProgramLeft]
  test  eax,eax
  jz    TaskProgramFind3
  mov   edi,[pTaskProgramScan]
  mov   eax,[edi+TASK_PROGRAM_ID]
  cmp   eax,[TaskProgramId]
  je    TaskProgramFind2
  add   edi,TASK_PROGRAM_RECORD_SIZE
  mov   [pTaskProgramScan],edi
  mov   eax,[TaskProgramLeft]
  dec   eax
  mov   [TaskProgramLeft],eax
  jmp   TaskProgramFind1
TaskProgramFind2:
  mov   [pTaskProgramRecord],edi
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_OK
TaskProgramFind3:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramCopyImage
;   Input:
;     pTaskProgramRecord = selected program table record.
;   Output:
;     TaskProgramStatus = TASK_PROGRAM_STATUS_OK or TASK_PROGRAM_STATUS_BAD_IMAGE.
;--------------------------------------------------------------------------------------------------
TaskProgramCopyImage:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_IMAGE
  mov   esi,[pTaskProgramRecord]
  test  esi,esi
  jz    TaskProgramCopyImage2
  mov   ecx,[esi+TASK_PROGRAM_SIZE]
  test  ecx,ecx
  jz    TaskProgramCopyImage2
  mov   edi,[esi+TASK_PROGRAM_LOAD_BASE]
  mov   esi,[esi+TASK_PROGRAM_SOURCE]
TaskProgramCopyImage1:
  mov   al,[esi]
  mov   [edi],al
  inc   esi
  inc   edi
  dec   ecx
  jnz   TaskProgramCopyImage1
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_OK
TaskProgramCopyImage2:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramLoad
;   Input:
;     TaskProgramId        = mock program id to load.
;     TaskProgramTaskIndex = task table index to prepare.
;     TaskProgramStackSlot = stack slot index to assign.
;   Output:
;     TaskProgramStatus     = TASK_PROGRAM_STATUS_*.
;     TaskProgramEntryPtr   = loaded program entry address.
;     TaskProgramKcBlockPtr = loaded program KcBlock address.
;   Notes:
;     Copies a kernel-resident mock image into the fixed user load slot and
;     seeds a ready task record. It does not start or schedule the task.
;--------------------------------------------------------------------------------------------------
TaskProgramLoad:
  mov   dword[TaskProgramEntryPtr],0
  mov   dword[TaskProgramKcBlockPtr],0
  call  TaskProgramFind
  mov   eax,[TaskProgramStatus]
  test  eax,eax
  jnz   TaskProgramLoad3
  call  TaskProgramCopyImage
  mov   eax,[TaskProgramStatus]
  test  eax,eax
  jnz   TaskProgramLoad3
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
  mov   edi,[pTaskRecord]
  mov   esi,[pTaskProgramRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
  mov   eax,[TaskProgramStackSlot]
  mov   [edi+TASK_STACK_SLOT],eax
  mov   eax,[TaskStackBottom]
  mov   [edi+TASK_STACK_BOTTOM],eax
  mov   eax,[TaskStackTop]
  mov   [edi+TASK_STACK_TOP],eax
  sub   eax,4
  mov   [edi+TASK_SAVED_ESP],eax
  mov   ebx,[esi+TASK_PROGRAM_LOAD_BASE]
  add   ebx,[esi+TASK_PROGRAM_ENTRY_OFFSET]
  mov   [TaskProgramEntryPtr],ebx
  mov   [eax],ebx
  mov   [edi+TASK_ENTRY],ebx
  mov   ebx,[esi+TASK_PROGRAM_LOAD_BASE]
  add   ebx,[esi+TASK_PROGRAM_KCBLOCK_OFFSET]
  mov   [TaskProgramKcBlockPtr],ebx
  mov   [edi+TASK_KCBLOCK_PTR],ebx
  mov   dword[edi+TASK_EXIT_CODE],0
  mov   dword[edi+TASK_RUN_COUNT],0
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_OK
  jmp   TaskProgramLoad3
TaskProgramLoad1:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_TASK
  jmp   TaskProgramLoad3
TaskProgramLoad2:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_STACK
TaskProgramLoad3:
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
