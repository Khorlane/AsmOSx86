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
;   - TaskPut4Hex
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
TASK_ENTER_STATUS_OK equ 0
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
TASK_AUTHORITY       equ 104
TASK_IMAGE_PAGES     equ 108
TASK_RECORD_SIZE     equ 112

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
TASK_MEMORY_STATUS_OK            equ 0
TASK_MEMORY_STATUS_BAD_ARG       equ 1
TASK_MEMORY_STATUS_NO_MEMORY     equ 2
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
USER_PROGRAM_KERNEL_STACK_GAP   equ 00000200h
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
TaskStackMapPte      dd 0               ; work: stack page-table entry pointer
TaskStackMapPhys     dd 0               ; work: stack page physical address
TaskStackMapLeft     dd 0               ; work: stack pages left to map
pTaskRecord          dd 0               ; output: selected task record pointer
TaskPut4DecVal       dd 0               ; input: value 0..9999
pTaskPut4DecDst      dd 0               ; input: destination payload pointer
TaskPut4HexVal       dd 0               ; input: low 16 bits to format
pTaskPut4HexDst      dd 0               ; input: destination payload pointer
TaskPut4HexShift     dd 0               ; work: current nibble shift
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
TaskProgramAuthority dd 0               ; input: TASK_AUTH_* authority for loaded task
TaskProgramArgCopySrc dd 0              ; work: task argument copy source
TaskProgramArgCopyPtr dd 0              ; work: task argument copy pointer
TaskProgramArgCopyLeft dd 0             ; work: task argument bytes left
TaskProgramRunCount dd 0                ; input: count of task slots 1..N to run
TaskProgramCheckIndex dd 0              ; work: task completion scan index
TaskProgramPrintIndex dd 0              ; work: task exit-code print index
TaskEnterEnabled    dd 1                ; input: 1 allows TaskEnterUserMode iretd path
TaskEnterStatus     dd 0                ; output: TASK_ENTER_STATUS_*
TaskModeIsUser      dd 0                ; output: 1 if pTaskRecord is user mode
TaskInterruptFrameEsp dd 0              ; input: ring 3 interrupt-frame ESP
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
TaskMemoryRequestBytes dd 0             ; input: bytes requested from task memory
TaskMemoryPointer    dd 0               ; input/output: user memory pointer
TaskMemoryBytes      dd 0               ; output: page-rounded byte count
TaskMemoryMappedBytes dd 0              ; output: mapped user-program bytes
TaskMemoryMaxBytes  dd 0                ; output: max user-program bytes
TaskMemoryStatus     dd 0               ; output: TASK_MEMORY_STATUS_*
TaskMemoryPageCount  dd 0               ; work: page count for memory request
TaskMemoryPageIndex  dd 0               ; work: page index for memory pointer
TaskMemoryNewPages   dd 0               ; work: new mapped user page count
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
; TaskPut4Hex
;   Input:
;     TaskPut4HexVal = low 16 bits to format.
;     pTaskPut4HexDst = destination payload pointer.
;   Output:
;     [pTaskPut4HexDst original..original+3] = four uppercase hex digits.
;--------------------------------------------------------------------------------------------------
TaskPut4Hex:
  mov   edi,[pTaskPut4HexDst]
  mov   dword[TaskPut4HexShift],12
TaskPut4Hex1:
  mov   eax,[TaskPut4HexVal]
  mov   ecx,[TaskPut4HexShift]
  shr   eax,cl
  and   eax,0000000Fh
  cmp   eax,10
  jb    TaskPut4Hex2
  add   al,'A'-10
  jmp   TaskPut4Hex3
TaskPut4Hex2:
  add   al,'0'
TaskPut4Hex3:
  mov   [edi],al
  inc   edi
  mov   eax,[TaskPut4HexShift]
  test  eax,eax
  jz    TaskPut4Hex4
  sub   eax,4
  mov   [TaskPut4HexShift],eax
  jmp   TaskPut4Hex1
TaskPut4Hex4:
  ret

;--------------------------------------------------------------------------------------------------
; TaskValidateUserRange
;   Input:
;     TaskUserPtr  = first byte of user range.
;     TaskUserSize = byte count to validate.
;   Output:
;     TaskUserOk = 1 if the range is inside the user program or KcBlock area.
;   Notes:
;     Kc handlers validate user pointers before kernel routines use them, even
;     though ring 3 paging now faults direct illegal user memory access.
;--------------------------------------------------------------------------------------------------
TaskValidateUserRange:
  mov   dword[TaskUserOk],0
  mov   eax,[TaskUserSize]
  test  eax,eax
  jz    TaskValidateUserRange3
  mov   ebx,[TaskUserPtr]
  test  ebx,ebx
  jz    TaskValidateUserRange3
  add   eax,ebx
  jc    TaskValidateUserRange3
  mov   [TaskUserLimit],eax
  cmp   ebx,USER_PROGRAM_VIRTUAL_BASE
  jb    TaskValidateUserRange1
  cmp   eax,USER_PROGRAM_VIRTUAL_BASE+USER_PROGRAM_MAX_SIZE
  jbe   TaskValidateUserRange2
TaskValidateUserRange1:
  cmp   ebx,USER_PROGRAM_KCBLOCK_BASE
  jb    TaskValidateUserRange3
  cmp   eax,USER_PROGRAM_KCBLOCK_BASE+USER_PROGRAM_KCBLOCK_SIZE
  ja    TaskValidateUserRange3
TaskValidateUserRange2:
  mov   dword[TaskUserOk],1
TaskValidateUserRange3:
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
  jne   TaskSetReady1
  mov   edi,[pTaskRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
TaskSetReady1:
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
  jne   TaskBlock1
  mov   edi,[pTaskRecord]
  mov   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
TaskBlock1:
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
  jne   TaskWake1
  mov   edi,[pTaskRecord]
  cmp   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
  jne   TaskWake1
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
TaskWake1:
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
  jz    TaskSleep2
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
TaskSleep2:
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
  jz    TaskKeyboardRead1
  movzx eax,byte[KbOutType]
  mov   [TaskKeyType],eax
  movzx eax,byte[KbOutChar]
  mov   [TaskKeyChar],eax
  ret
TaskKeyboardRead1:
  mov   eax,[TaskCurrentIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskKeyboardRead2
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
  jz    TaskKeyboardRead2
  mov   eax,[edi+TASK_KEY_TYPE]
  mov   [TaskKeyType],eax
  mov   eax,[edi+TASK_KEY_CHAR]
  mov   [TaskKeyChar],eax
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],0
TaskKeyboardRead2:
  ret

;--------------------------------------------------------------------------------------------------
; TaskYieldFromInterrupt
;   Input:
;     TaskInterruptFrameEsp = ESP at the ring 3 int 80h frame.
;   Output:
;     Saves the current user frame and dispatches the next ready task.
;--------------------------------------------------------------------------------------------------
TaskYieldFromInterrupt:
  call  TaskGetCurrentRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskYieldFromInterrupt1
  mov   eax,[TaskInterruptFrameEsp]
  mov   [edi+TASK_USER_IRET_ESP],eax
  cmp   dword[edi+TASK_STATE],TASK_STATE_EXITED
  je    TaskYieldFromInterrupt1
  cmp   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
  je    TaskYieldFromInterrupt1
  mov   dword[edi+TASK_STATE],TASK_STATE_READY
TaskYieldFromInterrupt1:
  call  TaskSelectNext
  call  TaskResumeSelected
  ret

;--------------------------------------------------------------------------------------------------
; TaskExitFromInterrupt
;   Input:
;     TaskExitCode = current task exit code.
;     TaskInterruptFrameEsp = ESP at the ring 3 int 80h frame.
;   Output:
;     Marks the current task exited and dispatches the next ready task.
;--------------------------------------------------------------------------------------------------
TaskExitFromInterrupt:
  call  TaskGetCurrentRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskExitFromInterrupt1
  mov   eax,[TaskInterruptFrameEsp]
  mov   [edi+TASK_USER_IRET_ESP],eax
  mov   eax,[TaskExitCode]
  mov   [edi+TASK_EXIT_CODE],eax
  mov   eax,[edi+TASK_RUN_COUNT]
  inc   eax
  mov   [edi+TASK_RUN_COUNT],eax
  mov   dword[edi+TASK_SLEEP_ACTIVE],0
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],0
  mov   dword[edi+TASK_STATE],TASK_STATE_EXITED
TaskExitFromInterrupt1:
  call  TaskSelectNext
  call  TaskResumeSelected
  ret

;--------------------------------------------------------------------------------------------------
; TaskSleepFromInterrupt
;   Input:
;     TaskSleepMs = cooperative sleep duration in milliseconds.
;     TaskInterruptFrameEsp = ESP at the ring 3 int 80h frame.
;   Output:
;     Blocks the current task until its wake deadline and dispatches next task.
;--------------------------------------------------------------------------------------------------
TaskSleepFromInterrupt:
  mov   eax,[TaskSleepMs]
  cmp   eax,3600000
  jbe   TaskSleepFromInterrupt1
  mov   eax,3600000
TaskSleepFromInterrupt1:
  mov   ebx,PIT_HZ
  mul   ebx
  add   eax,500
  adc   edx,0
  mov   ecx,1000
  div   ecx
  mov   [TaskSleepTicks],eax
  call  TimerNowTicks
  call  TaskGetCurrentRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskSleepFromInterrupt2
  mov   eax,[TaskInterruptFrameEsp]
  mov   [edi+TASK_USER_IRET_ESP],eax
  mov   eax,[TimerOutTicksLo]
  mov   edx,[TimerOutTicksHi]
  add   eax,[TaskSleepTicks]
  adc   edx,0
  mov   [edi+TASK_WAKE_LO],eax
  mov   [edi+TASK_WAKE_HI],edx
  mov   dword[edi+TASK_SLEEP_ACTIVE],1
  mov   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
TaskSleepFromInterrupt2:
  call  TaskSelectNext
  call  TaskResumeSelected
  ret

;--------------------------------------------------------------------------------------------------
; TaskKeyboardReadFromInterrupt
;   Output:
;     TaskKeyType/TaskKeyChar if a key is available immediately.
;     Otherwise blocks current task until TaskWakeKeyboardWaiters records one.
;--------------------------------------------------------------------------------------------------
TaskKeyboardReadFromInterrupt:
  mov   dword[TaskKeyType],KEY_NONE
  mov   dword[TaskKeyChar],0
  call  KbGetKey
  movzx eax,byte[KbOutHasKey]
  test  eax,eax
  jz    TaskKeyboardReadFromInterrupt1
  movzx eax,byte[KbOutType]
  mov   [TaskKeyType],eax
  movzx eax,byte[KbOutChar]
  mov   [TaskKeyChar],eax
  ret
TaskKeyboardReadFromInterrupt1:
  call  TaskGetCurrentRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskKeyboardReadFromInterrupt3
  mov   eax,[TaskInterruptFrameEsp]
  mov   [edi+TASK_USER_IRET_ESP],eax
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],1
  mov   dword[edi+TASK_KEY_TYPE],KEY_NONE
  mov   dword[edi+TASK_KEY_CHAR],0
  mov   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
  mov   ebx,[edi+TASK_KCBLOCK_PTR]
  test  ebx,ebx
  jz    TaskKeyboardReadFromInterrupt2
  mov   dword[ebx+KC_BLOCK_STATUS],KC_STATUS_OK
  mov   dword[ebx+KC_BLOCK_RESULT0],KEY_NONE
  mov   dword[ebx+KC_BLOCK_RESULT1],0
TaskKeyboardReadFromInterrupt2:
  call  TaskSelectNext
  call  TaskResumeSelected
TaskKeyboardReadFromInterrupt3:
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
  jz    TaskProgramLoad3
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
  jne   TaskProgramLoad4
  mov   eax,[FsOpenHandle]
  mov   [TaskProgramHandle],eax
  mov   eax,[FsOpenSize]
  mov   [TaskProgramImageSize],eax
  call  TaskProgramValidateImage
  mov   eax,[TaskProgramStatus]
  test  eax,eax
  jnz   TaskProgramLoad5
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
  jne   TaskProgramLoad5
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
  mov   [edi+TASK_IMAGE_PAGES],ebx
  mov   ebx,[TaskProgramKcBlockPhysPtr]
  mov   [edi+TASK_KCBLOCK_PHYS],ebx
  mov   dword[edi+TASK_USER_EIP],USER_PROGRAM_VIRTUAL_BASE
  mov   eax,[TaskStackTop]
  sub   eax,USER_PROGRAM_KERNEL_STACK_GAP
  mov   [edi+TASK_USER_ESP],eax
  mov   dword[edi+TASK_USER_CS],USER_CODE_SEL
  mov   dword[edi+TASK_USER_DS],USER_DATA_SEL
  mov   dword[edi+TASK_USER_SS],USER_DATA_SEL
  mov   dword[edi+TASK_USER_EFLAGS],USER_PROGRAM_INITIAL_EFLAGS
  call  TaskPrepareUserIretFrame
  mov   dword[edi+TASK_MODE],TASK_MODE_USER
  mov   eax,[TaskProgramAuthority]
  mov   [edi+TASK_AUTHORITY],eax
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
  jmp   TaskProgramLoad6
TaskProgramLoad1:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_TASK
  jmp   TaskProgramLoad6
TaskProgramLoad2:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_STACK
  jmp   TaskProgramLoad6
TaskProgramLoad3:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_BAD_IMAGE
  jmp   TaskProgramLoad6
TaskProgramLoad4:
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_NOT_FOUND
  jmp   TaskProgramLoad6
TaskProgramLoad5:
  call  TaskProgramCloseFile
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_FS_ERROR
TaskProgramLoad6:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramInit
;   Output:
;     Clears the task table and records the current kernel console context as task 0.
;   Notes:
;     Used by console-driven user-program smoke tests before loading mock images.
;--------------------------------------------------------------------------------------------------
TaskProgramInit:
  mov   eax,[MemoryKernelHeapEnd]
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
  mov   dword[edi+TASK_AUTHORITY],TASK_AUTH_SYSTEM
  mov   dword[edi+TASK_IMAGE_PAGES],0
  mov   dword[edi+TASK_WAKE_LO],0
  mov   dword[edi+TASK_WAKE_HI],0
  mov   dword[edi+TASK_SLEEP_ACTIVE],0
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],0
  mov   dword[edi+TASK_KEY_TYPE],0
  mov   dword[edi+TASK_KEY_CHAR],0
  mov   dword[TaskProgramArgPtr],0
  mov   dword[TaskProgramAuthority],TASK_AUTH_NORMAL
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
  jz    TaskProgramGetExitCode1
  mov   eax,[edi+TASK_EXIT_CODE]
  mov   [TaskProgramExitCode],eax
TaskProgramGetExitCode1:
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
  jz    TaskProgramSetArg3
  mov   eax,[edi+TASK_KCBLOCK_PHYS]
  test  eax,eax
  jz    TaskProgramSetArg3
  add   eax,USER_PROGRAM_KCBLOCK_SIZE
  mov   [TaskProgramArgCopyPtr],eax
  mov   edi,eax
  mov   word[edi],0
  mov   esi,[TaskProgramArgPtr]
  test  esi,esi
  jz    TaskProgramSetArg3
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
  jz    TaskProgramSetArg3
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
TaskProgramSetArg3:
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
  ja    TaskProgramPrintExitCodesN5
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskProgramPrintExitCodesN4
  mov   eax,[TaskProgramPrintIndex]
  add   al,'0'
  mov   [TaskProgramExitStr+7],al
  mov   eax,[edi+TASK_EXIT_CODE]
  call  TaskProgramSplitExitCode
  mov   eax,[TaskExitCodeSum]
  mov   ebx,[TaskExitCodeYield]
  test  ebx,ebx
  jz    TaskProgramPrintExitCodesN2
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskProgramExitStr+14]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  jmp   TaskProgramPrintExitCodesN3
TaskProgramPrintExitCodesN2:
  mov   [TaskPut4HexVal],eax
  lea   eax,[TaskProgramExitStr+14]
  mov   [pTaskPut4HexDst],eax
  call  TaskPut4Hex
TaskProgramPrintExitCodesN3:
  mov   eax,[TaskExitCodeYield]
  mov   [TaskPut4DecVal],eax
  lea   eax,[TaskProgramExitStr+19]
  mov   [pTaskPut4DecDst],eax
  call  TaskPut4Dec
  lea   eax,[TaskProgramExitStr]
  mov   [pVdStr],eax
  call  VdPutStr
  call  CnCrLf
TaskProgramPrintExitCodesN4:
  inc   dword[TaskProgramPrintIndex]
  jmp   TaskProgramPrintExitCodesN1
TaskProgramPrintExitCodesN5:
  ret

;--------------------------------------------------------------------------------------------------
; TaskEnterUserMode
;   Input:
;     pTaskRecord = selected task record with a prepared TASK_USER_IRET_ESP.
;   Output:
;     TaskEnterStatus = TASK_ENTER_STATUS_*.
;   Notes:
;     Low-level ring transition routine. TaskEnterEnabled remains as a simple
;     guard around the iretd path.
;--------------------------------------------------------------------------------------------------
TaskEnterUserMode:
  mov   dword[TaskEnterStatus],TASK_ENTER_STATUS_NO_TASK
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskEnterUserMode1
  mov   dword[TaskEnterStatus],TASK_ENTER_STATUS_NO_FRAME
  mov   eax,[edi+TASK_USER_IRET_ESP]
  test  eax,eax
  jz    TaskEnterUserMode1
  mov   dword[TaskEnterStatus],TASK_ENTER_STATUS_DISABLED
  cmp   dword[TaskEnterEnabled],1
  jne   TaskEnterUserMode1
  mov   dword[TaskEnterStatus],TASK_ENTER_STATUS_OK
  mov   ebx,eax
  mov   ax,USER_DATA_SEL
  mov   ds,ax
  mov   es,ax
  mov   fs,ax
  mov   gs,ax
  mov   esp,ebx
  iretd
TaskEnterUserMode1:
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
  jz    TaskIsUserMode1
  cmp   dword[edi+TASK_MODE],TASK_MODE_USER
  jne   TaskIsUserMode1
  mov   dword[TaskModeIsUser],1
TaskIsUserMode1:
  ret

;--------------------------------------------------------------------------------------------------
; TaskMemoryInfo
;   Output:
;     TaskMemoryStatus      = TASK_MEMORY_STATUS_*.
;     TaskMemoryMappedBytes = bytes currently mapped for this task's user image.
;     TaskMemoryMaxBytes    = maximum bytes available in the user image range.
;--------------------------------------------------------------------------------------------------
TaskMemoryInfo:
  mov   dword[TaskMemoryStatus],TASK_MEMORY_STATUS_BAD_ARG
  mov   dword[TaskMemoryMappedBytes],0
  mov   dword[TaskMemoryMaxBytes],USER_PROGRAM_MAX_SIZE
  mov   eax,[TaskCurrentIndex]
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  cmp   dword[edi+TASK_MODE],TASK_MODE_USER
  jne   TaskMemoryInfo1
  mov   eax,[edi+TASK_PROGRAM_PHYS]
  test  eax,eax
  jz    TaskMemoryInfo1
  mov   eax,[edi+TASK_PROGRAM_PAGES]
  mov   ebx,USER_PROGRAM_SLOT_SIZE
  mul   ebx
  mov   [TaskMemoryMappedBytes],eax
  mov   dword[TaskMemoryStatus],TASK_MEMORY_STATUS_OK
TaskMemoryInfo1:
  ret

;--------------------------------------------------------------------------------------------------
; TaskMemoryGet
;   Input:
;     TaskMemoryRequestBytes = requested byte count.
;   Output:
;     TaskMemoryStatus  = TASK_MEMORY_STATUS_*.
;     TaskMemoryPointer = allocated user virtual address.
;     TaskMemoryBytes   = page-rounded byte count.
;   Notes:
;     Minimal per-task page allocator. Pages come from the task's reserved user
;     program slot after the loaded image and are mapped into the current task.
;--------------------------------------------------------------------------------------------------
TaskMemoryGet:
  mov   dword[TaskMemoryStatus],TASK_MEMORY_STATUS_BAD_ARG
  mov   dword[TaskMemoryPointer],0
  mov   dword[TaskMemoryBytes],0
  mov   eax,[TaskMemoryRequestBytes]
  test  eax,eax
  jz    TaskMemoryGet2
  add   eax,00000FFFh
  and   eax,0FFFFF000h
  mov   [TaskMemoryBytes],eax
  mov   ebx,USER_PROGRAM_SLOT_SIZE
  xor   edx,edx
  div   ebx
  mov   [TaskMemoryPageCount],eax
  mov   eax,[TaskCurrentIndex]
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  cmp   dword[edi+TASK_MODE],TASK_MODE_USER
  jne   TaskMemoryGet2
  mov   eax,[edi+TASK_PROGRAM_PHYS]
  test  eax,eax
  jz    TaskMemoryGet2
  mov   eax,[edi+TASK_PROGRAM_PAGES]
  add   eax,[TaskMemoryPageCount]
  cmp   eax,USER_PROGRAM_MAX_PAGES
  ja    TaskMemoryGet1
  mov   [TaskMemoryNewPages],eax
  mov   eax,[edi+TASK_PROGRAM_PAGES]
  mov   ebx,USER_PROGRAM_SLOT_SIZE
  mul   ebx
  add   eax,USER_PROGRAM_VIRTUAL_BASE
  mov   [TaskMemoryPointer],eax
  mov   eax,[TaskMemoryNewPages]
  mov   [edi+TASK_PROGRAM_PAGES],eax
  mov   [pTaskRecord],edi
  call  TaskMapSelectedProgram
  mov   dword[TaskMemoryStatus],TASK_MEMORY_STATUS_OK
  ret
TaskMemoryGet1:
  mov   dword[TaskMemoryStatus],TASK_MEMORY_STATUS_NO_MEMORY
TaskMemoryGet2:
  ret

;--------------------------------------------------------------------------------------------------
; TaskMemoryFree
;   Input:
;     TaskMemoryPointer      = user virtual address returned by TaskMemoryGet.
;     TaskMemoryRequestBytes = byte count to free.
;   Output:
;     TaskMemoryStatus = TASK_MEMORY_STATUS_*.
;     TaskMemoryBytes  = page-rounded byte count freed.
;   Notes:
;     The first allocator is stack-like: only the most recent allocation can be
;     freed. That keeps the service real while avoiding heap bookkeeping.
;--------------------------------------------------------------------------------------------------
TaskMemoryFree:
  mov   dword[TaskMemoryStatus],TASK_MEMORY_STATUS_BAD_ARG
  mov   dword[TaskMemoryBytes],0
  mov   eax,[TaskMemoryRequestBytes]
  test  eax,eax
  jz    TaskMemoryFree1
  add   eax,00000FFFh
  and   eax,0FFFFF000h
  mov   [TaskMemoryBytes],eax
  mov   ebx,USER_PROGRAM_SLOT_SIZE
  xor   edx,edx
  div   ebx
  mov   [TaskMemoryPageCount],eax
  mov   eax,[TaskMemoryPointer]
  cmp   eax,USER_PROGRAM_VIRTUAL_BASE
  jb    TaskMemoryFree1
  sub   eax,USER_PROGRAM_VIRTUAL_BASE
  cmp   eax,USER_PROGRAM_MAX_SIZE
  jae   TaskMemoryFree1
  test  eax,00000FFFh
  jnz   TaskMemoryFree1
  mov   ebx,USER_PROGRAM_SLOT_SIZE
  xor   edx,edx
  div   ebx
  mov   [TaskMemoryPageIndex],eax
  mov   eax,[TaskCurrentIndex]
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  cmp   dword[edi+TASK_MODE],TASK_MODE_USER
  jne   TaskMemoryFree1
  mov   eax,[edi+TASK_PROGRAM_PHYS]
  test  eax,eax
  jz    TaskMemoryFree1
  mov   eax,[edi+TASK_PROGRAM_PAGES]
  sub   eax,[edi+TASK_IMAGE_PAGES]
  cmp   eax,[TaskMemoryPageCount]
  jb    TaskMemoryFree1
  mov   eax,[edi+TASK_PROGRAM_PAGES]
  sub   eax,[TaskMemoryPageCount]
  cmp   eax,[TaskMemoryPageIndex]
  jne   TaskMemoryFree1
  mov   [edi+TASK_PROGRAM_PAGES],eax
  mov   [pTaskRecord],edi
  call  TaskMapSelectedProgram
  mov   dword[TaskMemoryStatus],TASK_MEMORY_STATUS_OK
TaskMemoryFree1:
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
TaskYield1:
  call  TaskSelectNext
  call  TaskResumeSelected
  ret

;--------------------------------------------------------------------------------------------------
; Internal Routines
;--------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; TaskSelectNext
;   Output:
;     Selects the next ready task, maps its user pages, and updates pTaskRecord.
;--------------------------------------------------------------------------------------------------
TaskSelectNext:
  mov   eax,[TaskCurrentIndex]
  inc   eax
  cmp   eax,MAX_TASKS
  jb    TaskSelectNext1
  xor   eax,eax
TaskSelectNext1:
  mov   [TaskScanIndex],eax
  call  TaskWakeSleepers
  call  TaskWakeKeyboardWaiters
  mov   dword[TaskScanLeft],MAX_TASKS
TaskSelectNext2:
  mov   eax,[TaskScanLeft]
  test  eax,eax
  jz    TaskSelectNext5
  mov   eax,[TaskScanIndex]
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  cmp   dword[edi+TASK_STATE],TASK_STATE_READY
  je    TaskSelectNext4
  mov   eax,[TaskScanIndex]
  inc   eax
  cmp   eax,MAX_TASKS
  jb    TaskSelectNext3
  xor   eax,eax
TaskSelectNext3:
  mov   [TaskScanIndex],eax
  mov   eax,[TaskScanLeft]
  dec   eax
  mov   [TaskScanLeft],eax
  jmp   TaskSelectNext2
TaskSelectNext4:
  mov   eax,[TaskScanIndex]
  jmp   TaskSelectNext6
TaskSelectNext5:
  xor   eax,eax
TaskSelectNext6:
  mov   [TaskNextIndex],eax
  mov   [TaskCurrentIndex],eax
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  mov   dword[edi+TASK_STATE],TASK_STATE_RUNNING
  mov   [pTaskRecord],edi
  call  TaskLoadRing0Stack
  call  TaskMapSelectedProgram
  ret

;--------------------------------------------------------------------------------------------------
; TaskResumeSelected
;   Input:
;     pTaskRecord = selected task record.
;   Output:
;     Resumes ring 0 tasks through TASK_SAVED_ESP and ring 3 tasks by iretd.
;--------------------------------------------------------------------------------------------------
TaskResumeSelected:
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskResumeSelected2
  cmp   dword[edi+TASK_MODE],TASK_MODE_USER
  jne   TaskResumeSelected1
  cmp   dword[TaskEnterEnabled],1
  jne   TaskResumeSelected1
  call  TaskEnterUserMode
TaskResumeSelected1:
  mov   ax,DATA_DESC
  mov   ds,ax
  mov   es,ax
  mov   fs,ax
  mov   gs,ax
  mov   edi,[pTaskRecord]
  mov   esp,[edi+TASK_SAVED_ESP]
TaskResumeSelected2:
  ret

;--------------------------------------------------------------------------------------------------
; TaskLoadRing0Stack
;   Input:
;     pTaskRecord = selected task record.
;   Output:
;     TSS ESP0 tracks the selected task's kernel stack top.
;--------------------------------------------------------------------------------------------------
TaskLoadRing0Stack:
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskLoadRing0Stack1
  mov   eax,[edi+TASK_STACK_TOP]
  test  eax,eax
  jz    TaskLoadRing0Stack1
  mov   [Tss32+TSS_ESP0],eax
TaskLoadRing0Stack1:
  ret

;--------------------------------------------------------------------------------------------------
; TaskPrepareUserIretFrame
;   Input:
;     pTaskRecord = loaded user task record.
;   Output:
;     TASK_USER_IRET_ESP points to an initial iretd frame on the task stack.
;--------------------------------------------------------------------------------------------------
TaskPrepareUserIretFrame:
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskPrepareUserIretFrame1
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
TaskPrepareUserIretFrame1:
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
  jz    TaskWakeSleepers4
  mov   eax,[TaskWakeScanIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskWakeSleepers3
  cmp   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
  jne   TaskWakeSleepers3
  cmp   dword[edi+TASK_SLEEP_ACTIVE],1
  jne   TaskWakeSleepers3
  mov   eax,[TaskWakeNowHi]
  cmp   eax,[edi+TASK_WAKE_HI]
  jb    TaskWakeSleepers3
  ja    TaskWakeSleepers2
  mov   eax,[TaskWakeNowLo]
  cmp   eax,[edi+TASK_WAKE_LO]
  jb    TaskWakeSleepers3
TaskWakeSleepers2:
  mov   dword[edi+TASK_SLEEP_ACTIVE],0
  mov   eax,[TaskWakeScanIndex]
  mov   [TaskStateIndex],eax
  call  TaskWake
TaskWakeSleepers3:
  inc   dword[TaskWakeScanIndex]
  dec   dword[TaskWakeScanLeft]
  jmp   TaskWakeSleepers1
TaskWakeSleepers4:
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
TaskWakeKeyboardWaiters1:
  mov   eax,[TaskKeyScanLeft]
  test  eax,eax
  jz    TaskWakeKeyboardWaiters5
  mov   eax,[TaskKeyScanIndex]
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskWakeKeyboardWaiters2
  cmp   dword[edi+TASK_STATE],TASK_STATE_BLOCKED
  jne   TaskWakeKeyboardWaiters2
  cmp   dword[edi+TASK_KEY_WAIT_ACTIVE],1
  jne   TaskWakeKeyboardWaiters2
  mov   eax,[TaskKeyScanIndex]
  mov   [TaskKeyFoundIndex],eax
  mov   [TaskKeyFoundPtr],edi
  jmp   TaskWakeKeyboardWaiters3
TaskWakeKeyboardWaiters2:
  inc   dword[TaskKeyScanIndex]
  dec   dword[TaskKeyScanLeft]
  jmp   TaskWakeKeyboardWaiters1
TaskWakeKeyboardWaiters3:
  call  KbGetKey
  movzx eax,byte[KbOutHasKey]
  test  eax,eax
  jz    TaskWakeKeyboardWaiters5
  mov   edi,[TaskKeyFoundPtr]
  movzx eax,byte[KbOutType]
  mov   [edi+TASK_KEY_TYPE],eax
  movzx eax,byte[KbOutChar]
  mov   [edi+TASK_KEY_CHAR],eax
  mov   dword[edi+TASK_KEY_WAIT_ACTIVE],0
  mov   ebx,[edi+TASK_KCBLOCK_PTR]
  test  ebx,ebx
  jz    TaskWakeKeyboardWaiters4
  mov   dword[ebx+KC_BLOCK_STATUS],KC_STATUS_OK
  mov   eax,[edi+TASK_KEY_TYPE]
  mov   [ebx+KC_BLOCK_RESULT0],eax
  mov   eax,[edi+TASK_KEY_CHAR]
  mov   [ebx+KC_BLOCK_RESULT1],eax
TaskWakeKeyboardWaiters4:
  mov   eax,[TaskKeyFoundIndex]
  mov   [TaskStateIndex],eax
  call  TaskWake
TaskWakeKeyboardWaiters5:
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
  jz    TaskGetStateRecord1
  mov   dword[TaskStateStatus],TASK_STATUS_OK
  ret
TaskGetStateRecord1:
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
  call  TaskMapSelectedStack
  ret

;--------------------------------------------------------------------------------------------------
; TaskMapSelectedStack
;   Input:
;     pTaskRecord = selected task record.
;   Output:
;     Stack arena pages are supervisor-only except the selected user stack.
;--------------------------------------------------------------------------------------------------
TaskMapSelectedStack:
  mov   eax,PgTable0+((STACK_ARENA_BOTTOM/PG_PAGE_SIZE)*4)
  mov   [TaskStackMapPte],eax
  mov   eax,STACK_ARENA_BOTTOM
  mov   [TaskStackMapPhys],eax
  mov   dword[TaskStackMapLeft],STACK_SLOT_COUNT
TaskMapSelectedStack1:
  mov   eax,[TaskStackMapLeft]
  test  eax,eax
  jz    TaskMapSelectedStack2
  mov   eax,[TaskStackMapPhys]
  or    eax,PG_KERNEL_FLAGS
  mov   edi,[TaskStackMapPte]
  mov   [edi],eax
  add   edi,4
  mov   [TaskStackMapPte],edi
  mov   eax,[TaskStackMapPhys]
  add   eax,PG_PAGE_SIZE
  mov   [TaskStackMapPhys],eax
  dec   dword[TaskStackMapLeft]
  jmp   TaskMapSelectedStack1
TaskMapSelectedStack2:
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskMapSelectedStack3
  cmp   dword[edi+TASK_MODE],TASK_MODE_USER
  jne   TaskMapSelectedStack3
  mov   eax,[edi+TASK_STACK_BOTTOM]
  test  eax,eax
  jz    TaskMapSelectedStack3
  and   eax,0FFFFF000h
  mov   ebx,eax
  shr   ebx,12
  shl   ebx,2
  add   ebx,PgTable0
  or    eax,PG_USER_FLAGS
  mov   [ebx],eax
TaskMapSelectedStack3:
  mov   eax,PgDirectory
  mov   cr3,eax
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
  jae   TaskGetRecord1
  mov   ebx,TASK_RECORD_SIZE
  mul   ebx
  lea   edi,[TaskTable+eax]
  mov   [pTaskRecord],edi
TaskGetRecord1:
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
  jae   TaskGetStackBounds1
  mov   ebx,STACK_SLOT_SIZE
  mul   ebx
  mov   ebx,STACK_ARENA_TOP
  sub   ebx,eax
  mov   [TaskStackTop],ebx
  sub   ebx,STACK_SLOT_SIZE
  mov   [TaskStackBottom],ebx
TaskGetStackBounds1:
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
  jz    TaskProgramValidateImage1
  cmp   eax,USER_PROGRAM_MAX_SIZE
  ja    TaskProgramValidateImage1
  mov   dword[TaskProgramStatus],TASK_PROGRAM_STATUS_OK
TaskProgramValidateImage1:
  ret

;--------------------------------------------------------------------------------------------------
; TaskProgramAlloc
;   Output:
;     TaskProgramLoadBase = next dynamic user-program load base.
;     TaskProgramAllocSize = allocation bytes.
;     TaskProgramPageCount = initial image pages.
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
  add   eax,USER_PROGRAM_MAX_SIZE
  mov   [TaskProgramKcBlockPhysPtr],eax
  mov   eax,USER_PROGRAM_MAX_SIZE
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
  jz    TaskProgramCloseFile1
  mov   [FsCloseHandle],eax
  call  FsClose
  mov   dword[TaskProgramHandle],0
TaskProgramCloseFile1:
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
  jz    TaskProgramClearSlot2
  mov   edi,[TaskProgramClearPtr]
  mov   byte[edi],0
  inc   edi
  mov   [TaskProgramClearPtr],edi
  dec   eax
  mov   [TaskProgramClearLeft],eax
  jmp   TaskProgramClearSlot1
TaskProgramClearSlot2:
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
  ja    TaskProgramCheckDoneN2
  mov   [TaskIndex],eax
  call  TaskGetRecord
  mov   edi,[pTaskRecord]
  test  edi,edi
  jz    TaskProgramCheckDoneN3
  cmp   dword[edi+TASK_STATE],TASK_STATE_EXITED
  jne   TaskProgramCheckDoneN3
  inc   dword[TaskProgramCheckIndex]
  jmp   TaskProgramCheckDoneN1
TaskProgramCheckDoneN2:
  mov   dword[TaskProgramDone],1
TaskProgramCheckDoneN3:
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
