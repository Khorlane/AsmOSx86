;**************************************************************************************************
; Task.asm
;   Cooperative tasking and raw user-program loading for AsmOSx86.
;
; Purpose
;   Provide kernel-owned task records, cooperative scheduling support,
;   low-memory stack-slot assignment, and file-backed user-program loading.
;
; Contains
;   - Task state constants
;   - Task record layout constants
;   - Task table storage
;   - Ready-task selection and cooperative task switching
;   - Stack-slot bounds helpers
;   - Raw user-program loading and task setup
;   - Shared virtual user-program page mapping
;
; Public API
;   - TaskGetCurrentRecord
;   - TaskPut4Dec
;   - TaskValidateUserRange
;   - TaskSetReady
;   - TaskBlock
;   - TaskWake
;   - TaskSleep
;   - TaskKeyboardRead
;   - TaskProgramLoad
;   - TaskProgramInit
;   - TaskProgramGetExitCode
;   - TaskProgramSetArg
;   - TaskProgramStartN
;   - TaskProgramPrintExitCodesN
;   - TaskEnterUserMode
;   - TaskIsUserMode
;   - TaskExit
;   - TaskYield
;
; Notes
;   - Task metadata is kernel-owned.
;   - Task stacks live in the low-memory stack-slot arena.
;   - Loaded user programs reserve physical pages above the kernel.
;   - User tasks run through a shared virtual base range.
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
TASK_STATUS_OK       equ 0
TASK_STATUS_BAD_TASK equ 1
TASK_ENTER_STATUS_DISABLED equ 1
TASK_ENTER_STATUS_NO_TASK  equ 2
TASK_ENTER_STATUS_NO_FRAME equ 3

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
TASK_PROGRAM_PHYS    equ 36
TASK_PROGRAM_PAGES   equ 40
TASK_KCBLOCK_PHYS    equ 44
TASK_WAKE_LO         equ 48
TASK_WAKE_HI         equ 52
TASK_SLEEP_ACTIVE    equ 56
TASK_KEY_WAIT_ACTIVE equ 60
TASK_KEY_TYPE        equ 64
TASK_KEY_CHAR        equ 68
TASK_MODE_KERNEL     equ 0
TASK_MODE_USER       equ 1
TASK_USER_EIP        equ 72
TASK_USER_ESP        equ 76
TASK_USER_CS         equ 80
TASK_USER_DS         equ 84
TASK_USER_SS         equ 88
TASK_USER_EFLAGS     equ 92
TASK_USER_IRET_ESP   equ 96
TASK_MODE            equ 100
TASK_RECORD_SIZE     equ 104

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
USER_PROGRAM_SLOT_SIZE          equ 00001000h
USER_PROGRAM_MAX_PAGES          equ PG_USER_MAX_PAGES
USER_PROGRAM_MAX_SIZE           equ USER_PROGRAM_SLOT_SIZE*USER_PROGRAM_MAX_PAGES
USER_PROGRAM_VIRTUAL_BASE       equ 00200000h
USER_PROGRAM_KCBLOCK_SIZE       equ 32
USER_PROGRAM_KCBLOCK_OFFSET     equ USER_PROGRAM_MAX_SIZE
USER_PROGRAM_KCBLOCK_BASE       equ USER_PROGRAM_VIRTUAL_BASE+USER_PROGRAM_KCBLOCK_OFFSET
USER_PROGRAM_ARG_SIZE           equ 128
USER_PROGRAM_ARG_OFFSET         equ USER_PROGRAM_KCBLOCK_OFFSET+USER_PROGRAM_KCBLOCK_SIZE
USER_PROGRAM_ARG_BASE           equ USER_PROGRAM_VIRTUAL_BASE+USER_PROGRAM_ARG_OFFSET
USER_PROGRAM_INITIAL_EFLAGS     equ 00000002h
USER_PROGRAM_RET_SLOT_SIZE      equ 4
USER_PROGRAM_IRET_FRAME_SIZE    equ 20
USER_IRET_EIP                  equ 0
USER_IRET_CS                   equ 4
USER_IRET_EFLAGS               equ 8
USER_IRET_ESP                  equ 12
USER_IRET_SS                   equ 16

;--------------------------------------------------------------------------------------------------
; User Memory Contract
;--------------------------------------------------------------------------------------------------
; User-originated Kc pointer arguments are valid only when fully contained in:
;   - USER_PROGRAM_VIRTUAL_BASE .. USER_PROGRAM_VIRTUAL_BASE+USER_PROGRAM_MAX_SIZE
;   - USER_PROGRAM_KCBLOCK_BASE .. USER_PROGRAM_KCBLOCK_BASE+USER_PROGRAM_KCBLOCK_SIZE
; The startup argument area immediately after the KcBlock is kernel-populated
; task startup data, not a general Kc validation range.

;--------------------------------------------------------------------------------------------------
; Task Globals
;--------------------------------------------------------------------------------------------------
align 4
TaskCurrentIndex     dd 0               ; current task index
TaskNextIndex        dd 0               ; next task index
TaskIndex            dd 0               ; input: task index for lookup helpers
TaskStateIndex       dd 0               ; input: task index for state helpers
TaskStateStatus      dd 0               ; output: TASK_STATUS_*
TaskSleepMs          dd 0               ; input: cooperative sleep duration
TaskSleepTicks       dd 0               ; work: sleep duration in PIT ticks
TaskWakeNowLo        dd 0               ; work: current ticks low
TaskWakeNowHi        dd 0               ; work: current ticks high
TaskWakeScanIndex    dd 0               ; work: sleep wake scan index
TaskWakeScanLeft     dd 0               ; work: sleep wake scan entries left
TaskKeyType          dd 0               ; output: keyboard event type
TaskKeyChar          dd 0               ; output: keyboard event char
TaskKeyScanIndex     dd 0               ; work: keyboard wait scan index
TaskKeyScanLeft      dd 0               ; work: keyboard wait scan entries left
TaskKeyFoundIndex    dd 0               ; work: keyboard waiter index
TaskKeyFoundPtr      dd 0               ; work: keyboard waiter record
TaskScanIndex        dd 0               ; work: scheduler table scan index
TaskScanLeft         dd 0               ; work: scheduler entries left to scan
TaskStackSlot        dd 0               ; input: stack slot index
TaskStackBottom      dd 0               ; output: stack slot bottom address
TaskStackTop         dd 0               ; output: stack slot top address
pTaskRecord          dd 0               ; output: selected task record pointer
TaskPut4DecVal       dd 0               ; input: value 0..9999
pTaskPut4DecDst      dd 0               ; input: destination payload pointer
TaskUserPtr          dd 0               ; input: user pointer to validate
TaskUserSize         dd 0               ; input: validation byte count
TaskUserLimit        dd 0               ; work: exclusive range limit
TaskUserOk           dd 0               ; output: 1 if range is valid, else 0
TaskInitPtr          dd 0               ; work: table clear pointer
TaskInitLeft         dd 0               ; work: table clear byte count
pTaskProgramName     dd 0               ; input: pointer to kernel Str filename
TaskProgramTaskIndex dd 0               ; input: task table index to prepare
TaskProgramStackSlot dd 0               ; input: stack slot index to assign
TaskProgramStatus    dd 0               ; output: TASK_PROGRAM_STATUS_*
TaskProgramExitCode  dd 0               ; output: selected task exit code
TaskProgramArgPtr    dd 0               ; input: kernel Str argument for loaded task
TaskProgramArgCopySrc dd 0              ; work: task argument copy source
TaskProgramArgCopyPtr dd 0              ; work: task argument copy pointer
TaskProgramArgCopyLeft dd 0             ; work: task argument bytes left
TaskProgramRunCount dd 0                ; input: count of task slots 1..N to run
TaskProgramCheckIndex dd 0              ; work: task completion scan index
TaskProgramPrintIndex dd 0              ; work: task exit-code print index
TaskEnterStatus     dd 0                ; output: TASK_ENTER_STATUS_*
TaskModeIsUser      dd 0                ; output: 1 if pTaskRecord is user mode
TaskProgramEntryPtr  dd 0               ; output: loaded program entry address
TaskProgramKcBlockPtr dd 0              ; output: loaded program KcBlock address
TaskProgramNextLoadBase dd 0            ; work: next dynamic user-program load base
TaskProgramLoadBase  dd 0               ; work: selected program load base
TaskProgramAllocSize  dd 0              ; work: bytes reserved for loaded program
TaskProgramPageCount  dd 0              ; work: pages reserved for loaded program
TaskProgramImageSize dd 0               ; work: raw image size
TaskProgramImageAllocSize dd 0          ; work: bytes reserved for raw image
TaskProgramKcBlockPhysPtr dd 0          ; work: physical KcBlock page address
TaskProgramHandle    dd 0               ; work: open file handle
TaskProgramClearPtr   dd 0              ; work: user slot clear pointer
TaskProgramClearLeft  dd 0              ; work: user slot clear byte count
TaskProgramDone       dd 0              ; work: 1 when test tasks have exited
TaskExitCodeSum       dd 0              ; work: low 16-bit exit-code sum
TaskExitCodeYield     dd 0              ; work: high 16-bit exit-code yield count
TaskExitCode         dd 0               ; input: current task exit code
String  TaskProgramExitStr,"Task 0 exit 0000 0000"
TaskTable:
  times MAX_TASKS * TASK_RECORD_SIZE db 0

;--------------------------------------------------------------------------------------------------
; External Routines
;--------------------------------------------------------------------------------------------------

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
; TaskValidateUserRange
;   Input:
;     TaskUserPtr  = first byte of user range.
;     TaskUserSize = byte count to validate.
;   Output:
;     TaskUserOk = 1 if the range is inside the user program or KcBlock area.
;   Notes:
;     This is convention enforcement today. Future ring 3 paging enforcement
;     should make illegal user memory access fault before kernel use.
;--------------------------------------------------------------------------------------------------
TaskValidateUserRange:
  mov   dword[TaskUserOk],0
  mov   eax,[TaskUserSize]
  test  eax,eax
  jz    TaskValidateUserRangeDone
  mov   ebx,[TaskUserPtr]
  test  ebx,ebx
  jz    TaskValidateUserRangeDone
  add   eax,ebx
  jc    TaskValidateUserRangeDone
  mov   [TaskUserLimit],eax
  cmp   ebx,USER_PROGRAM_VIRTUAL_BASE
  jb    TaskValidateUserRangeKcBlock
  cmp   eax,USER_PROGRAM_VIRTUAL_BASE+USER_PROGRAM_MAX_SIZE
  jbe   TaskValidateUserRangeOk
TaskValidateUserRangeKcBlock:
  cmp   ebx,USER_PROGRAM_KCBLOCK_BASE
  jb    TaskValidateUserRangeDone
  cmp   eax,USER_PROGRAM_KCBLOCK_BASE+USER_PROGRAM_KCBLOCK_SIZE
  ja    TaskValidateUserRangeDone
TaskValidateUserRangeOk:
  mov   dword[TaskUserOk],1
TaskValidateUserRangeDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskSetReady
;   Input:
;     TaskStateIndex = task table index to mark ready.
;   Output:
;     TaskStateStatus = TASK_STATUS_OK or TASK_STATUS_BAD_TASK.
;--------------------------------------------------------------------------------------------------
TaskSetReady:
  call  TaskGetStateRecord
  mov   eax,[TaskStateStatus]
  cmp   eax,TASK_STATUS_OK
  jne   TaskSetReadyDone
  mov   edi,[pTaskRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
TaskSetReadyDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskBlock
;   Input:
;     TaskStateIndex = task table index to mark blocked.
;   Output:
;     TaskStateStatus = TASK_STATUS_OK or TASK_STATUS_BAD_TASK.
;--------------------------------------------------------------------------------------------------
TaskBlock:
  call  TaskGetStateRecord
  mov   eax,[TaskStateStatus]
  cmp   eax,TASK_STATUS_OK
  jne   TaskBlockDone
  mov   edi,[pTaskRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
TaskBlockDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskWake
;   Input:
;     TaskStateIndex = task table index to wake if blocked.
;   Output:
;     TaskStateStatus = TASK_STATUS_OK or TASK_STATUS_BAD_TASK.
;--------------------------------------------------------------------------------------------------
TaskWake:
  call  TaskGetStateRecord
  mov   eax,[TaskStateStatus]
  cmp   eax,TASK_STATUS_OK
  jne   TaskWakeDone
  mov   edi,[pTaskRecord]
  cmp   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
  jne   TaskWakeDone
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
TaskWakeDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskSleep
;   Input:
;     TaskSleepMs = cooperative sleep duration in milliseconds.
;   Output:
;     Blocks the current task until its wake deadline, then yields.
;   Notes:
;     Wake checks happen when TaskYield is entered; no timer IRQ is required.
;--------------------------------------------------------------------------------------------------
TaskSleep:
  mov   eax,[TaskSleepMs]
  cmp   eax,3600000
  jbe   TaskSleep1
  mov   eax,3600000
TaskSleep1:
  mov   ebx,PIT_HZ
  mul   ebx
  add   eax,500
  adc   edx,0
  mov   ecx,1000
  div   ecx
  mov   [TaskSleepTicks],eax
  call  TimerNowTicks
  mov   eax,[TaskCurrentIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskSleepDone
  mov   eax,[TimerOutTicksLo]
  mov   edx,[TimerOutTicksHi]
  add   eax,[TaskSleepTicks]
  adc   edx,0
  mov   [edi+TASK_WAKE_LO],eax
  mov   [edi+TASK_WAKE_HI],edx
  mov   dword[edi+TASK_SLEEP_ACTIVE],1
  mov   eax,[TaskCurrentIndex]
  mov   [TaskStateIndex],eax
  call  TaskBlock
  call  TaskYield
TaskSleepDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskKeyboardRead
;   Output:
;     TaskKeyType = KEY_* event type.
;     TaskKeyChar = ASCII character for KEY_CHAR, otherwise 0.
;   Notes:
;     Blocks the current task until a keyboard event is available.
;     Wake checks happen when TaskYield is entered; no keyboard IRQ is required.
;--------------------------------------------------------------------------------------------------
TaskKeyboardRead:
  mov   dword[TaskKeyType],KEY_NONE
  mov   dword[TaskKeyChar],0
  call  KbGetKey
  movzx eax,byte[KbOutHasKey]
  test  eax,eax
  jz    TaskKeyboardReadBlock
  movzx eax,byte[KbOutType]
  mov   [TaskKeyType],eax
  movzx eax,byte[KbOutChar]
  mov   [TaskKeyChar],eax
  ret
TaskKeyboardReadBlock:
  mov   eax,[TaskCurrentIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskKeyboardReadDone
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],1
  mov   dword[edi+TASK_KEY_TYPE],KEY_NONE
  mov   dword[edi+TASK_KEY_CHAR],0
  mov   eax,[TaskCurrentIndex]
  mov   [TaskStateIndex],eax
  call  TaskBlock
  call  TaskYield
  call  TaskGetCurrentRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskKeyboardReadDone
  mov   eax,[edi+TASK_KEY_TYPE]
  mov   [TaskKeyType],eax
  mov   eax,[edi+TASK_KEY_CHAR]
  mov   [TaskKeyChar],eax
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],0
TaskKeyboardReadDone:
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
;     Reads a raw flat binary into the next physical load area and seeds a
;     ready task record. It does not start the task.
;--------------------------------------------------------------------------------------------------
TaskProgramLoad:
  mov   dword[TaskProgramEntryPtr],0
  mov   dword[TaskProgramKcBlockPtr],0
  mov   dword[TaskProgramLoadBase],0
  mov   dword[TaskProgramAllocSize],0
  mov   dword[TaskProgramPageCount],0
  mov   dword[TaskProgramImageSize],0
  mov   dword[TaskProgramImageAllocSize],0
  mov   dword[TaskProgramKcBlockPhysPtr],0
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
  mov   eax,[pTaskProgramName]
  mov   [pFsOpenName],eax
  call  FsOpen
  mov   eax,[FsStatus]
  cmp   eax,FS_STATUS_OK
  jne   TaskProgramLoad5
  mov   eax,[FsOpenHandle]
  mov   [TaskProgramHandle],eax
  mov   eax,[FsOpenSize]
  mov   [TaskProgramImageSize],eax
  call  TaskProgramValidateImage
  mov   eax,[TaskProgramStatus]
  test  eax,eax
  jnz   TaskProgramLoad6
  call  TaskProgramAlloc
  call  TaskProgramClearSlot
  mov   eax,[TaskProgramHandle]
  mov   [FsReadHandle],eax
  mov   eax,[TaskProgramLoadBase]
  mov   [pFsReadBuffer],eax
  mov   eax,[TaskProgramImageSize]
  mov   [FsReadCount],eax
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
  mov   ebx,USER_PROGRAM_VIRTUAL_BASE
  mov   [TaskProgramEntryPtr],ebx
  mov   [eax],ebx
  mov   [edi+TASK_ENTRY],ebx
  mov   ebx,USER_PROGRAM_KCBLOCK_BASE
  mov   [TaskProgramKcBlockPtr],ebx
  mov   [edi+TASK_KCBLOCK_PTR],ebx
  mov   ebx,[TaskProgramLoadBase]
  mov   [edi+TASK_PROGRAM_PHYS],ebx
  mov   ebx,[TaskProgramPageCount]
  mov   [edi+TASK_PROGRAM_PAGES],ebx
  mov   ebx,[TaskProgramKcBlockPhysPtr]
  mov   [edi+TASK_KCBLOCK_PHYS],ebx
  mov   dword[edi+TASK_USER_EIP],USER_PROGRAM_VIRTUAL_BASE
  mov   eax,[TaskStackTop]
  mov   [edi+TASK_USER_ESP],eax
  mov   dword[edi+TASK_USER_CS],USER_CODE_SEL
  mov   dword[edi+TASK_USER_DS],USER_DATA_SEL
  mov   dword[edi+TASK_USER_SS],USER_DATA_SEL
  mov   dword[edi+TASK_USER_EFLAGS],USER_PROGRAM_INITIAL_EFLAGS
  call  TaskPrepareUserIretFrame
  mov   dword[edi+TASK_MODE],TASK_MODE_USER
  mov   dword[edi+TASK_WAKE_LO],0
  mov   dword[edi+TASK_WAKE_HI],0
  mov   dword[edi+TASK_SLEEP_ACTIVE],0
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],0
  mov   dword[edi+TASK_KEY_TYPE],0
  mov   dword[edi+TASK_KEY_CHAR],0
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
; TaskProgramInit
;   Output:
;     Clears the task table and records the current kernel console context as task 0.
;   Notes:
;     Used by console-driven user-program smoke tests before loading mock images.
;--------------------------------------------------------------------------------------------------
TaskProgramInit:
  mov   eax,KernelEnd
  add   eax,00000FFFh
  and   eax,0FFFFF000h
  mov   [TaskProgramNextLoadBase],eax
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
  mov   dword[edi+TASK_PROGRAM_PHYS],0
  mov   dword[edi+TASK_PROGRAM_PAGES],0
  mov   dword[edi+TASK_KCBLOCK_PHYS],0
  mov   dword[edi+TASK_USER_EIP],0
  mov   dword[edi+TASK_USER_ESP],0
  mov   dword[edi+TASK_USER_CS],0
  mov   dword[edi+TASK_USER_DS],0
  mov   dword[edi+TASK_USER_SS],0
  mov   dword[edi+TASK_USER_EFLAGS],0
  mov   dword[edi+TASK_USER_IRET_ESP],0
  mov   dword[edi+TASK_MODE],TASK_MODE_KERNEL
  mov   dword[edi+TASK_WAKE_LO],0
  mov   dword[edi+TASK_WAKE_HI],0
  mov   dword[edi+TASK_SLEEP_ACTIVE],0
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],0
  mov   dword[edi+TASK_KEY_TYPE],0
  mov   dword[edi+TASK_KEY_CHAR],0
  mov   dword[TaskProgramArgPtr],0
  call  TaskLoadRing0Stack
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramGetExitCode
;   Input:
;     TaskProgramTaskIndex = task table index to inspect.
;   Output:
;     TaskProgramExitCode = selected task exit code, or 0 if invalid.
;--------------------------------------------------------------------------------------------------
TaskProgramGetExitCode:
  mov   dword[TaskProgramExitCode],0
  mov   eax,[TaskProgramTaskIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskProgramGetExitCodeDone
  mov   eax,[edi+TASK_EXIT_CODE]
  mov   [TaskProgramExitCode],eax
TaskProgramGetExitCodeDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramSetArg
;   Input:
;     TaskProgramTaskIndex = task table index to receive the argument.
;     TaskProgramArgPtr    = kernel Str argument, or 0 for an empty argument.
;   Output:
;     Copies the argument Str to USER_PROGRAM_ARG_BASE in the task KcBlock page.
;--------------------------------------------------------------------------------------------------
TaskProgramSetArg:
  mov   eax,[TaskProgramTaskIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskProgramSetArgDone
  mov   eax,[edi+TASK_KCBLOCK_PHYS]
  test  eax,eax
  jz    TaskProgramSetArgDone
  add   eax,USER_PROGRAM_KCBLOCK_SIZE
  mov   [TaskProgramArgCopyPtr],eax
  mov   edi,eax
  mov   word[edi],0
  mov   esi,[TaskProgramArgPtr]
  test  esi,esi
  jz    TaskProgramSetArgDone
  movzx eax,word[esi]
  cmp   eax,USER_PROGRAM_ARG_SIZE-2
  jbe   TaskProgramSetArg1
  mov   eax,USER_PROGRAM_ARG_SIZE-2
TaskProgramSetArg1:
  mov   edi,[TaskProgramArgCopyPtr]
  mov   [edi],ax
  add   esi,2
  mov   [TaskProgramArgCopySrc],esi
  add   edi,2
  mov   [TaskProgramArgCopyPtr],edi
  mov   [TaskProgramArgCopyLeft],eax
TaskProgramSetArg2:
  mov   eax,[TaskProgramArgCopyLeft]
  test  eax,eax
  jz    TaskProgramSetArgDone
  mov   esi,[TaskProgramArgCopySrc]
  mov   edi,[TaskProgramArgCopyPtr]
  mov   al,[esi]
  mov   [edi],al
  inc   esi
  inc   edi
  mov   [TaskProgramArgCopySrc],esi
  mov   [TaskProgramArgCopyPtr],edi
  dec   dword[TaskProgramArgCopyLeft]
  jmp   TaskProgramSetArg2
TaskProgramSetArgDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramStartN
;   Input:
;     TaskProgramRunCount = count of task slots 1..N to wait for.
;   Output:
;     Starts cooperative dispatch of ready tasks and returns when selected tasks exit.
;--------------------------------------------------------------------------------------------------
TaskProgramStartN:
  mov   dword[TaskProgramDone],0
TaskProgramStartN1:
  call  TaskYield
  call  TaskProgramCheckDoneN
  mov   eax,[TaskProgramDone]
  test  eax,eax
  jz    TaskProgramStartN1
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramPrintExitCodesN
;   Input:
;     TaskProgramRunCount = count of task slots 1..N to print.
;   Output:
;     Prints recorded exit codes for task slots 1..N.
;--------------------------------------------------------------------------------------------------
TaskProgramPrintExitCodesN:
  mov   dword[TaskProgramPrintIndex],1
TaskProgramPrintExitCodesN1:
  mov   eax,[TaskProgramPrintIndex]
  cmp   eax,[TaskProgramRunCount]
  ja    TaskProgramPrintExitCodesNDone
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskProgramPrintExitCodesNNext
  mov   eax,[TaskProgramPrintIndex]
  add   al,'0'
  mov   [TaskProgramExitStr+7],al
  mov   eax,[edi+TASK_EXIT_CODE]
  call  TaskProgramSplitExitCode
  mov   eax,[TaskExitCodeSum]
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskProgramExitStr+14]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  mov   eax,[TaskExitCodeYield]
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskProgramExitStr+19]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[TaskProgramExitStr]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
TaskProgramPrintExitCodesNNext:
  inc   dword[TaskProgramPrintIndex]
  jmp   TaskProgramPrintExitCodesN1
TaskProgramPrintExitCodesNDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskEnterUserMode
;   Input:
;     pTaskRecord = selected task record with a prepared TASK_USER_IRET_ESP.
;   Output:
;     TaskEnterStatus = TASK_ENTER_STATUS_DISABLED.
;   Notes:
;     Future ring 3 transition point. This routine intentionally does not
;     consume the iretd frame yet, and no hardware interrupts are required.
;--------------------------------------------------------------------------------------------------
TaskEnterUserMode:
  mov   dword[TaskEnterStatus],TASK_ENTER_STATUS_DISABLED
  ret

;--------------------------------------------------------------------------------------------------
; TaskIsUserMode
;   Input:
;     pTaskRecord = selected task record.
;   Output:
;     TaskModeIsUser = 1 if the selected task is tagged user mode, else 0.
;--------------------------------------------------------------------------------------------------
TaskIsUserMode:
  mov   dword[TaskModeIsUser],0
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskIsUserModeDone
  cmp   dword[edi+TASK_MODE],TASK_MODE_USER
  jne   TaskIsUserModeDone
  mov   dword[TaskModeIsUser],1
TaskIsUserModeDone:
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
  mov   dword[edi+TASK_SLEEP_ACTIVE],0
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
  cmp   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
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
  call  TaskWakeSleepers
  call  TaskWakeKeyboardWaiters
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
  mov   [pTaskRecord],edi
  call  TaskLoadRing0Stack
  call  TaskMapSelectedProgram
  mov   edi,[pTaskRecord]
  mov   esp,[edi+TASK_SAVED_ESP]
  ret

;--------------------------------------------------------------------------------------------------
; Internal Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; TaskLoadRing0Stack
;   Input:
;     pTaskRecord = selected task record.
;   Output:
;     TSS ESP0 tracks the selected task's kernel stack top.
;   Notes:
;     This is future ring-transition groundwork. User tasks still run in ring 0.
;--------------------------------------------------------------------------------------------------
TaskLoadRing0Stack:
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskLoadRing0StackDone
  mov   eax,[edi+TASK_STACK_TOP]
  test  eax,eax
  jz    TaskLoadRing0StackDone
  mov   [Tss32+TSS_ESP0],eax
TaskLoadRing0StackDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskPrepareUserIretFrame
;   Input:
;     pTaskRecord = loaded user task record.
;   Output:
;     TASK_USER_IRET_ESP points to a future iretd frame on the task stack.
;   Notes:
;     Current scheduling still returns through TASK_SAVED_ESP. This frame sits
;     below that return slot and is not consumed yet.
;--------------------------------------------------------------------------------------------------
TaskPrepareUserIretFrame:
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskPrepareUserIretFrameDone
  mov   ebx,[edi+TASK_STACK_TOP]
  sub   ebx,USER_PROGRAM_RET_SLOT_SIZE+USER_PROGRAM_IRET_FRAME_SIZE
  mov   [edi+TASK_USER_IRET_ESP],ebx
  mov   eax,[edi+TASK_USER_EIP]
  mov   [ebx+USER_IRET_EIP],eax
  mov   eax,[edi+TASK_USER_CS]
  mov   [ebx+USER_IRET_CS],eax
  mov   eax,[edi+TASK_USER_EFLAGS]
  mov   [ebx+USER_IRET_EFLAGS],eax
  mov   eax,[edi+TASK_USER_ESP]
  mov   [ebx+USER_IRET_ESP],eax
  mov   eax,[edi+TASK_USER_SS]
  mov   [ebx+USER_IRET_SS],eax
TaskPrepareUserIretFrameDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskWakeSleepers
;   Output:
;     Wakes blocked sleep tasks whose deadlines are at or before current ticks.
;--------------------------------------------------------------------------------------------------
TaskWakeSleepers:
  call  TimerNowTicks
  mov   eax,[TimerOutTicksLo]
  mov   [TaskWakeNowLo],eax
  mov   eax,[TimerOutTicksHi]
  mov   [TaskWakeNowHi],eax
  mov   dword[TaskWakeScanIndex],0
  mov   dword[TaskWakeScanLeft],MAX_TASKS
TaskWakeSleepers1:
  mov   eax,[TaskWakeScanLeft]
  test  eax,eax
  jz    TaskWakeSleepersDone
  mov   eax,[TaskWakeScanIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskWakeSleepersNext
  cmp   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
  jne   TaskWakeSleepersNext
  cmp   dword[edi+TASK_SLEEP_ACTIVE],1
  jne   TaskWakeSleepersNext
  mov   eax,[TaskWakeNowHi]
  cmp   eax,[edi+TASK_WAKE_HI]
  jb    TaskWakeSleepersNext
  ja    TaskWakeSleepersWake
  mov   eax,[TaskWakeNowLo]
  cmp   eax,[edi+TASK_WAKE_LO]
  jb    TaskWakeSleepersNext
TaskWakeSleepersWake:
  mov   dword[edi+TASK_SLEEP_ACTIVE],0
  mov   eax,[TaskWakeScanIndex]
  mov   [TaskStateIndex],eax
  call  TaskWake
TaskWakeSleepersNext:
  inc   dword[TaskWakeScanIndex]
  dec   dword[TaskWakeScanLeft]
  jmp   TaskWakeSleepers1
TaskWakeSleepersDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskWakeKeyboardWaiters
;   Output:
;     Wakes the first task blocked on keyboard input if a key event is available.
;   Notes:
;     Polls the keyboard only when a keyboard waiter exists, so console input is
;     not consumed during ordinary command-line editing.
;--------------------------------------------------------------------------------------------------
TaskWakeKeyboardWaiters:
  mov   dword[TaskKeyFoundIndex],0
  mov   dword[TaskKeyFoundPtr],0
  mov   dword[TaskKeyScanIndex],0
  mov   dword[TaskKeyScanLeft],MAX_TASKS
TaskWakeKeyboardWaitersFind:
  mov   eax,[TaskKeyScanLeft]
  test  eax,eax
  jz    TaskWakeKeyboardWaitersDone
  mov   eax,[TaskKeyScanIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskWakeKeyboardWaitersNext
  cmp   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
  jne   TaskWakeKeyboardWaitersNext
  cmp   dword[edi+TASK_KEY_WAIT_ACTIVE],1
  jne   TaskWakeKeyboardWaitersNext
  mov   eax,[TaskKeyScanIndex]
  mov   [TaskKeyFoundIndex],eax
  mov   [TaskKeyFoundPtr],edi
  jmp   TaskWakeKeyboardWaitersPoll
TaskWakeKeyboardWaitersNext:
  inc   dword[TaskKeyScanIndex]
  dec   dword[TaskKeyScanLeft]
  jmp   TaskWakeKeyboardWaitersFind
TaskWakeKeyboardWaitersPoll:
  call  KbGetKey
  movzx eax,byte[KbOutHasKey]
  test  eax,eax
  jz    TaskWakeKeyboardWaitersDone
  mov   edi,[TaskKeyFoundPtr]
  movzx eax,byte[KbOutType]
  mov   [edi+TASK_KEY_TYPE],eax
  movzx eax,byte[KbOutChar]
  mov   [edi+TASK_KEY_CHAR],eax
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],0
  mov   eax,[TaskKeyFoundIndex]
  mov   [TaskStateIndex],eax
  call  TaskWake
TaskWakeKeyboardWaitersDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskGetStateRecord
;   Input:
;     TaskStateIndex = task table index for a state helper.
;   Output:
;     TaskStateStatus = TASK_STATUS_OK or TASK_STATUS_BAD_TASK.
;     pTaskRecord     = selected task record, or 0.
;--------------------------------------------------------------------------------------------------
TaskGetStateRecord:
  mov   eax,[TaskStateIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskGetStateRecordBad
  mov   dword[TaskStateStatus],TASK_STATUS_OK
  ret
TaskGetStateRecordBad:
  mov   dword[TaskStateStatus],TASK_STATUS_BAD_TASK
  ret

;--------------------------------------------------------------------------------------------------
; TaskMapSelectedProgram
;   Input:
;     pTaskRecord = selected task record.
;   Output:
;     Shared user virtual range maps to the selected task's loaded image, or
;     identity maps USER_PROGRAM_VIRTUAL_BASE for kernel task 0.
;--------------------------------------------------------------------------------------------------
TaskMapSelectedProgram:
  mov   edi,[pTaskRecord]
  mov   eax,[edi+TASK_PROGRAM_PHYS]
  test  eax,eax
  jnz   TaskMapSelectedProgram1
  mov   eax,USER_PROGRAM_VIRTUAL_BASE
  mov   dword[PgUserPageCount],USER_PROGRAM_MAX_PAGES
  mov   dword[PgUserKcPhysBase],USER_PROGRAM_KCBLOCK_BASE
  jmp   TaskMapSelectedProgram2
TaskMapSelectedProgram1:
  mov   ebx,[edi+TASK_PROGRAM_PAGES]
  mov   [PgUserPageCount],ebx
  mov   ebx,[edi+TASK_KCBLOCK_PHYS]
  mov   [PgUserKcPhysBase],ebx
TaskMapSelectedProgram2:
  mov   [PgUserPhysBase],eax
  call  PgMapUserProgram
  ret

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
; TaskProgramValidateImage
;   Output:
;     TaskProgramStatus = TASK_PROGRAM_STATUS_OK or BAD_IMAGE.
;--------------------------------------------------------------------------------------------------
TaskProgramValidateImage:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_IMAGE
  mov   eax,[TaskProgramImageSize]
  test  eax,eax
  jz    TaskProgramValidateImageDone
  cmp   eax,USER_PROGRAM_MAX_SIZE
  ja    TaskProgramValidateImageDone
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_OK
TaskProgramValidateImageDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramAlloc
;   Output:
;     TaskProgramLoadBase = next dynamic user-program load base.
;     TaskProgramAllocSize = allocation bytes.
;     TaskProgramPageCount = allocation pages.
;     TaskProgramNextLoadBase advanced to the next 4K boundary.
;--------------------------------------------------------------------------------------------------
TaskProgramAlloc:
  mov   eax,[TaskProgramNextLoadBase]
  mov   [TaskProgramLoadBase],eax
  mov   eax,[TaskProgramImageSize]
  add   eax,00000FFFh
  and   eax,0FFFFF000h
  mov   [TaskProgramImageAllocSize],eax
  mov   ebx,USER_PROGRAM_SLOT_SIZE
  xor   edx,edx
  div   ebx
  mov   [TaskProgramPageCount],eax
  mov   eax,[TaskProgramLoadBase]
  add   eax,[TaskProgramImageAllocSize]
  mov   [TaskProgramKcBlockPhysPtr],eax
  mov   eax,[TaskProgramImageAllocSize]
  add   eax,USER_PROGRAM_SLOT_SIZE
  mov   [TaskProgramAllocSize],eax
  mov   eax,[TaskProgramLoadBase]
  add   eax,[TaskProgramAllocSize]
  add   eax,00000FFFh
  and   eax,0FFFFF000h
  mov   [TaskProgramNextLoadBase],eax
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
;     Clears the current user-program allocation.
;--------------------------------------------------------------------------------------------------
TaskProgramClearSlot:
  mov   eax,[TaskProgramLoadBase]
  mov   [TaskProgramClearPtr],eax
  mov   eax,[TaskProgramAllocSize]
  mov   [TaskProgramClearLeft],eax
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
; TaskProgramCheckDoneN
;   Input:
;     TaskProgramRunCount = count of task slots 1..N to check.
;   Output:
;     TaskProgramDone = 1 when task slots 1..N are EXITED, else 0.
;--------------------------------------------------------------------------------------------------
TaskProgramCheckDoneN:
  mov   dword[TaskProgramDone],0
  mov   dword[TaskProgramCheckIndex],1
TaskProgramCheckDoneN1:
  mov   eax,[TaskProgramCheckIndex]
  cmp   eax,[TaskProgramRunCount]
  ja    TaskProgramCheckDoneNOk
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskProgramCheckDoneNDone
  cmp   dword[edi+TASK_STATE],TASK_STATE_EXITED
  jne   TaskProgramCheckDoneNDone
  inc   dword[TaskProgramCheckIndex]
  jmp   TaskProgramCheckDoneN1
TaskProgramCheckDoneNOk:
  mov   dword[TaskProgramDone],1
TaskProgramCheckDoneNDone:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramSplitExitCode
;   Input:
;     EAX = packed exit code: high 16 bits yield count, low 16 bits sum.
;   Output:
;     TaskExitCodeSum   = low 16 bits.
;     TaskExitCodeYield = high 16 bits.
;--------------------------------------------------------------------------------------------------
TaskProgramSplitExitCode:
  mov   ebx,eax
  and   eax,0000FFFFh
  mov   [TaskExitCodeSum],eax
  mov   eax,ebx
  shr   eax,16
  mov   [TaskExitCodeYield],eax
  ret

;--------------------------------------------------------------------------------------------------
; Unused Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; TaskGetNextRecord
;   Output:
;     pTaskRecord = next task record, or 0 if TaskNextIndex is invalid.
;   Notes:
;     Currently has no callers.
;--------------------------------------------------------------------------------------------------
TaskGetNextRecord:
  mov   eax,[TaskNextIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  ret
