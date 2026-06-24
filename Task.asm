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
TASK_RECORD_SIZE     equ 28

;--------------------------------------------------------------------------------------------------
; Task Table and Stack-Slot Constants
;--------------------------------------------------------------------------------------------------
MAX_TASKS            equ 8
STACK_SLOT_SIZE      equ 00001000h
STACK_ARENA_TOP      equ 00090000h
STACK_ARENA_BOTTOM   equ 00001000h
STACK_SLOT_COUNT     equ 143

;--------------------------------------------------------------------------------------------------
; Task Globals
;--------------------------------------------------------------------------------------------------
align 4
TaskCurrentIndex     dd 0               ; current task index
TaskNextIndex        dd 0               ; next task index
TaskIndex            dd 0               ; input: task index for lookup helpers
TaskStackSlot        dd 0               ; input: stack slot index
TaskStackBottom      dd 0               ; output: stack slot bottom address
TaskStackTop         dd 0               ; output: stack slot top address
pTaskRecord          dd 0               ; output: selected task record pointer
TaskTestACount       dd 0               ; POC task A private counter
TaskTestBCount       dd 0               ; POC task B private counter
TaskPut4DecVal       dd 0               ; input: value 0..9999
pTaskPut4DecDst      dd 0               ; input: destination payload pointer
TaskEntryPtr         dd 0               ; work: seeded task entry pointer
TaskInitPtr          dd 0               ; work: table clear pointer
TaskInitLeft         dd 0               ; work: table clear byte count
String  TaskTestStrA,"A 0000",0Dh,0Ah
String  TaskTestStrB,"B 0000",0Dh,0Ah
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
; TaskInitTest
;   Output:
;     Initializes task records and seeded stacks for the TaskTest POC.
;   Notes:
;     Task 0 is the kernel stack slot.
;     Task 1 and Task 2 are kernel-resident stand-in task payloads.
;--------------------------------------------------------------------------------------------------
TaskInitTest:
  mov   eax,TaskTable
  mov   [TaskInitPtr],eax
  mov   eax,MAX_TASKS * TASK_RECORD_SIZE
  mov   [TaskInitLeft],eax
TaskInitTestClear:
  mov   eax,[TaskInitLeft]
  test  eax,eax
  jz    TaskInitTestSetup0
  mov   edi,[TaskInitPtr]
  mov   byte[edi],0
  inc   edi
  mov   [TaskInitPtr],edi
  mov   eax,[TaskInitLeft]
  dec   eax
  mov   [TaskInitLeft],eax
  jmp   TaskInitTestClear
TaskInitTestSetup0:
  mov   dword[TaskTestACount],0
  mov   dword[TaskTestBCount],9
  mov   dword[TaskCurrentIndex],0
  mov   dword[TaskNextIndex],1
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
  mov   dword[TaskIndex],1
  mov   dword[TaskStackSlot],1
  mov   eax,TaskTestA
  call  TaskInitTestTask
  mov   dword[TaskIndex],2
  mov   dword[TaskStackSlot],2
  mov   eax,TaskTestB
  call  TaskInitTestTask
  ret

;--------------------------------------------------------------------------------------------------
; TaskInitTestTask
;   Input:
;     TaskIndex     = task table index to initialize.
;     TaskStackSlot = stack slot index to assign.
;     EAX           = kernel-resident task entry for this POC helper.
;   Output:
;     Selected task record receives state, stack bounds, seeded ESP, and entry.
;   Notes:
;     This helper is internal to TaskInitTest. The EAX entry input is local scratch,
;     not a public routine contract.
;--------------------------------------------------------------------------------------------------
TaskInitTestTask:
  mov   [TaskEntryPtr],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
  mov   eax,[TaskStackSlot]
  mov   [edi+TASK_STACK_SLOT],eax
  call  TaskGetStackBounds
  mov   eax,[TaskStackBottom]
  mov   [edi+TASK_STACK_BOTTOM],eax
  mov   eax,[TaskStackTop]
  mov   [edi+TASK_STACK_TOP],eax
  sub   eax,4
  mov   [edi+TASK_SAVED_ESP],eax
  mov   ebx,[TaskEntryPtr]
  mov   [eax],ebx
  mov   [edi+TASK_ENTRY],ebx
  mov   dword[edi+TASK_KCBLOCK_PTR],0
  ret

;--------------------------------------------------------------------------------------------------
; TaskStartTest
;   Output:
;     Starts the TaskTest POC by switching to task 1's seeded stack.
;   Notes:
;     Low-level transition routine: intentionally loads ESP and returns into
;     the selected task's stack.
;--------------------------------------------------------------------------------------------------
TaskStartTest:
  mov   dword[TaskCurrentIndex],1
  mov   dword[TaskIndex],1
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_RUNNING
  mov   esp,[edi+TASK_SAVED_ESP]
  ret

;--------------------------------------------------------------------------------------------------
; TaskYield
;   Output:
;     Saves the current task ESP, selects the other POC task, loads its ESP,
;     and returns through that task's saved stack.
;   Notes:
;     Low-level transition routine: intentionally saves and loads ESP.
;     First POC scheduler alternates task 1 and task 2 only.
;--------------------------------------------------------------------------------------------------
TaskYield:
  mov   eax,[TaskCurrentIndex]
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  mov   [edi+TASK_SAVED_ESP],esp
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
  mov   eax,[TaskCurrentIndex]
  cmp   eax,1
  je    TaskYieldNext2
  mov   eax,1
  jmp   TaskYieldSetNext
TaskYieldNext2:
  mov   eax,2
TaskYieldSetNext:
  mov   [TaskNextIndex],eax
  mov   [TaskCurrentIndex],eax
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  mov   dword[edi+TASK_STATE],TASK_STATE_RUNNING
  mov   esp,[edi+TASK_SAVED_ESP]
  ret

;--------------------------------------------------------------------------------------------------
; TaskTestA
;   Output:
;     Prints "A 0001" style lines through KcDispatch, then yields.
;--------------------------------------------------------------------------------------------------
TaskTestA:
  mov   eax,[TaskTestACount]
  inc   eax
  cmp   eax,10000
  jb    TaskTestA1
  mov   eax,1
TaskTestA1:
  mov   [TaskTestACount],eax
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskTestStrA+4]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  mov   dword[KcNumber],KcVdWriteStr
  mov   eax,TaskTestStrA
  mov   [KcArg0],eax
  call  KcDispatch
  mov   dword[TimerDelayMs],500
  call  TimerSpinDelayMs
  mov   dword[KcNumber],KcTsYield
  call  KcDispatch
  jmp   TaskTestA

;--------------------------------------------------------------------------------------------------
; TaskTestB
;   Output:
;     Prints "B 0001" style lines through KcDispatch, then yields.
;--------------------------------------------------------------------------------------------------
TaskTestB:
  mov   eax,[TaskTestBCount]
  inc   eax
  cmp   eax,10000
  jb    TaskTestB1
  mov   eax,1
TaskTestB1:
  mov   [TaskTestBCount],eax
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskTestStrB+4]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  mov   dword[KcNumber],KcVdWriteStr
  mov   eax,TaskTestStrB
  mov   [KcArg0],eax
  call  KcDispatch
  mov   dword[TimerDelayMs],500
  call  TimerSpinDelayMs
  mov   dword[KcNumber],KcTsYield
  call  KcDispatch
  jmp   TaskTestB
