;**************************************************************************************************
; Prog4.asm
;   Tiny user-program file I/O sketch.
;**************************************************************************************************

[bits 32]
  org   00200000h

LEGACY_KC_GATEWAY   equ 00100005h
KC_TM_SLEEP         equ 9
KC_VD_WRITE_STR     equ 2
KC_TS_LOAD_PROGRAM  equ 4
KC_TS_EXIT          equ 5
KC_FS_OPEN          equ 6
KC_FS_READ          equ 7
KC_FS_CLOSE         equ 8
KC_KB_READ          equ 10
KC_TS_GET_INFO      equ 11
KC_MM_GET_MEMORY    equ 12
KC_MM_FREE_MEMORY   equ 13
KC_TS_GET_AUTHORITY equ 14
KC_MM_INFO          equ 15
KC_BLOCK            equ 00210000h
USER_ARG            equ 00210020h
KC_BLOCK_NUMBER     equ 0
KC_BLOCK_STATUS     equ 4
KC_BLOCK_ARG0       equ 8
KC_BLOCK_ARG1       equ 12
KC_BLOCK_ARG2       equ 16
KC_BLOCK_RESULT0    equ 24
KC_BLOCK_RESULT1    equ 28
STATUS_OK           equ 0
STATUS_INVALID      equ 1
STATUS_BAD_ARG      equ 2
STATUS_DENIED       equ 3
DATA_BUFFER_SIZE    equ 80

Start:
  mov   dword[Prog4ExitCode],0          ; Set program exit code to zero
  call  OpenFile                        ; Open file
  mov   eax,[Prog4Status]               ;  check status
  cmp   eax,STATUS_OK                   ;  if bad
  jne   Prog4Exit                       ;    can't continue, just exit
  call  ReadData                        ; Read file
  mov   eax,[Prog4Status]               ;  check status
  cmp   eax,STATUS_OK                   ;  if bad
  jne   Prog4CloseAndExit               ;    can't continue, close file, then exit
  call  PrintLine                       ; Print
  call  MaybeCplTest                    ; Optional CS selector proof
  call  MaybeInt80Test                  ; Optional int 80h proof
  call  MaybeInfoTest                   ; Optional task-info syscall proof
  call  MaybeAuthTest                   ; Optional task-authority proof
  call  MaybeKeyTest                    ; Optional keyboard read proof
  call  MaybeSleepTest                  ; Optional cooperative sleep proof
  call  MaybePrivTest                   ; Optional privilege-fault proof
  call  MaybeMemTest                    ; Optional kernel-memory fault proof
  call  MaybeLoadTest                   ; Optional user load-program denial proof
  call  MaybeGetMemoryTest              ; Optional trusted memory-service proof
  call  MaybeFreeMemoryTest             ; Optional trusted memory-free proof
  call  MaybeMemoryInfoTest             ; Optional memory-info proof
  call  MaybeMemoryGrowTest             ; Optional memory-growth info proof
  call  MaybeMemoryOomTest              ; Optional memory-limit proof
  call  MaybeMemoryFreeOrderTest        ; Optional stack-like free proof
  call  MaybeLegacyTest                 ; Optional legacy-gateway page-fault proof
  call  MaybeBadPrintTest               ; Optional bad-print proof
  call  MaybeBadOpenTest                ; Optional bad-open proof
  call  MaybeBadReadTest                ; Optional bad-read proof
  call  MaybeBadZeroCallTest            ; Optional zero-call proof
  call  MaybeBadCallNumberTest          ; Optional unknown-call proof
Prog4CloseAndExit:
  call  CloseFile                       ; Close file
Prog4Exit:
  call  ExitProgram                     ; Return to OS

OpenFile:
  mov   dword[DataHandle],0
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_FS_OPEN
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],DataFileName
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   OpenFileFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  cmp   eax,STATUS_OK
  jne   OpenFileFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT1]
  mov   [DataHandle],eax
  mov   dword[Prog4Status],STATUS_OK
  ret
OpenFileFailed:
  mov   dword[Prog4Status],1
  mov   dword[Prog4ExitCode],1
  ret

ReadData:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_FS_READ
  mov   eax,[DataHandle]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],DataBufferText
  mov   dword[KC_BLOCK+KC_BLOCK_ARG2],DATA_BUFFER_SIZE
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   ReadDataFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  cmp   eax,STATUS_OK
  jne   ReadDataFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT1]
  mov   [DataBuffer],ax
  mov   dword[Prog4Status],STATUS_OK
  ret
ReadDataFailed:
  mov   dword[Prog4Status],1
  mov   dword[Prog4ExitCode],2
  ret

PrintLine:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_VD_WRITE_STR
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],DataBuffer
  int   080h
  ret

MaybeCplTest:
  cmp   word[USER_ARG],3
  jne   MaybeCplTestDone
  cmp   byte[USER_ARG+2],'c'
  jne   MaybeCplTestDone
  cmp   byte[USER_ARG+3],'p'
  jne   MaybeCplTestDone
  cmp   byte[USER_ARG+4],'l'
  jne   MaybeCplTestDone
  xor   eax,eax
  mov   ax,cs
  mov   [Prog4ExitCode],eax
MaybeCplTestDone:
  ret

MaybeBadPrintTest:
  cmp   word[USER_ARG],3
  jne   MaybeBadPrintTestLong
  cmp   byte[USER_ARG+2],'b'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+3],'a'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+4],'d'
  jne   MaybeBadPrintTestDone
  call  BadPrintTest
  ret
MaybeBadPrintTestLong:
  cmp   word[USER_ARG],9
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+2],'b'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+3],'a'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+4],'d'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+5],'-'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+6],'p'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+7],'r'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+8],'i'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+9],'n'
  jne   MaybeBadPrintTestDone
  cmp   byte[USER_ARG+10],'t'
  jne   MaybeBadPrintTestDone
  call  BadPrintTest
MaybeBadPrintTestDone:
  ret

MaybeBadOpenTest:
  cmp   word[USER_ARG],8
  jne   MaybeBadOpenTestDone
  cmp   byte[USER_ARG+2],'b'
  jne   MaybeBadOpenTestDone
  cmp   byte[USER_ARG+3],'a'
  jne   MaybeBadOpenTestDone
  cmp   byte[USER_ARG+4],'d'
  jne   MaybeBadOpenTestDone
  cmp   byte[USER_ARG+5],'-'
  jne   MaybeBadOpenTestDone
  cmp   byte[USER_ARG+6],'o'
  jne   MaybeBadOpenTestDone
  cmp   byte[USER_ARG+7],'p'
  jne   MaybeBadOpenTestDone
  cmp   byte[USER_ARG+8],'e'
  jne   MaybeBadOpenTestDone
  cmp   byte[USER_ARG+9],'n'
  jne   MaybeBadOpenTestDone
  call  BadOpenTest
MaybeBadOpenTestDone:
  ret

MaybeBadReadTest:
  cmp   word[USER_ARG],8
  jne   MaybeBadReadTestDone
  cmp   byte[USER_ARG+2],'b'
  jne   MaybeBadReadTestDone
  cmp   byte[USER_ARG+3],'a'
  jne   MaybeBadReadTestDone
  cmp   byte[USER_ARG+4],'d'
  jne   MaybeBadReadTestDone
  cmp   byte[USER_ARG+5],'-'
  jne   MaybeBadReadTestDone
  cmp   byte[USER_ARG+6],'r'
  jne   MaybeBadReadTestDone
  cmp   byte[USER_ARG+7],'e'
  jne   MaybeBadReadTestDone
  cmp   byte[USER_ARG+8],'a'
  jne   MaybeBadReadTestDone
  cmp   byte[USER_ARG+9],'d'
  jne   MaybeBadReadTestDone
  call  BadReadTest
MaybeBadReadTestDone:
  ret

MaybeSleepTest:
  cmp   word[USER_ARG],5
  jne   MaybeSleepTestDone
  cmp   byte[USER_ARG+2],'s'
  jne   MaybeSleepTestDone
  cmp   byte[USER_ARG+3],'l'
  jne   MaybeSleepTestDone
  cmp   byte[USER_ARG+4],'e'
  jne   MaybeSleepTestDone
  cmp   byte[USER_ARG+5],'e'
  jne   MaybeSleepTestDone
  cmp   byte[USER_ARG+6],'p'
  jne   MaybeSleepTestDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TM_SLEEP
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],1000
  int   080h
  mov   dword[Prog4ExitCode],7
MaybeSleepTestDone:
  ret

MaybeKeyTest:
  cmp   word[USER_ARG],3
  jne   MaybeKeyTestDone
  cmp   byte[USER_ARG+2],'k'
  jne   MaybeKeyTestDone
  cmp   byte[USER_ARG+3],'e'
  jne   MaybeKeyTestDone
  cmp   byte[USER_ARG+4],'y'
  jne   MaybeKeyTestDone
  mov   dword[pProg4Msg],MsgKeyPrompt
  call  PrintProg4Msg
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_KB_READ
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeKeyTestFailed
  mov   dword[pProg4Msg],MsgKeyOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000047h
  ret
MaybeKeyTestFailed:
  mov   dword[pProg4Msg],MsgKeyFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000094h
MaybeKeyTestDone:
  ret

MaybeInt80Test:
  cmp   word[USER_ARG],5
  jne   MaybeInt80TestDone
  cmp   byte[USER_ARG+2],'i'
  jne   MaybeInt80TestDone
  cmp   byte[USER_ARG+3],'n'
  jne   MaybeInt80TestDone
  cmp   byte[USER_ARG+4],'t'
  jne   MaybeInt80TestDone
  cmp   byte[USER_ARG+5],'8'
  jne   MaybeInt80TestDone
  cmp   byte[USER_ARG+6],'0'
  jne   MaybeInt80TestDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_VD_WRITE_STR
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],MsgInt80Ok
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeInt80TestFailed
  mov   dword[Prog4ExitCode],00000080h
  ret
MaybeInt80TestFailed:
  mov   dword[pProg4Msg],MsgInt80Fail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000093h
MaybeInt80TestDone:
  ret

MaybeInfoTest:
  cmp   word[USER_ARG],4
  jne   MaybeInfoTestDone
  cmp   byte[USER_ARG+2],'i'
  jne   MaybeInfoTestDone
  cmp   byte[USER_ARG+3],'n'
  jne   MaybeInfoTestDone
  cmp   byte[USER_ARG+4],'f'
  jne   MaybeInfoTestDone
  cmp   byte[USER_ARG+5],'o'
  jne   MaybeInfoTestDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_GET_INFO
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeInfoTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  cmp   eax,1
  jne   MaybeInfoTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT1]
  cmp   eax,1
  jne   MaybeInfoTestFailed
  mov   dword[Prog4ExitCode],00000101h
  ret
MaybeInfoTestFailed:
  mov   dword[Prog4ExitCode],00000089h
MaybeInfoTestDone:
  ret

MaybeAuthTest:
  cmp   word[USER_ARG],4
  jne   MaybeAuthTestDone
  cmp   byte[USER_ARG+2],'a'
  jne   MaybeAuthTestDone
  cmp   byte[USER_ARG+3],'u'
  jne   MaybeAuthTestDone
  cmp   byte[USER_ARG+4],'t'
  jne   MaybeAuthTestDone
  cmp   byte[USER_ARG+5],'h'
  jne   MaybeAuthTestDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_GET_AUTHORITY
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeAuthTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  cmp   eax,0
  je    MaybeAuthTestNormal
  cmp   eax,1
  je    MaybeAuthTestTrusted
  cmp   eax,2
  je    MaybeAuthTestSystem
  jmp   MaybeAuthTestFailed
MaybeAuthTestNormal:
  mov   dword[pProg4Msg],MsgAuthNormalOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000050h
  ret
MaybeAuthTestTrusted:
  mov   dword[pProg4Msg],MsgAuthTrustedOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000051h
  ret
MaybeAuthTestSystem:
  mov   dword[pProg4Msg],MsgAuthSystemOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000052h
  ret
MaybeAuthTestFailed:
  mov   dword[pProg4Msg],MsgAuthFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000090h
MaybeAuthTestDone:
  ret

MaybePrivTest:
  cmp   word[USER_ARG],4
  jne   MaybePrivTestDone
  cmp   byte[USER_ARG+2],'p'
  jne   MaybePrivTestDone
  cmp   byte[USER_ARG+3],'r'
  jne   MaybePrivTestDone
  cmp   byte[USER_ARG+4],'i'
  jne   MaybePrivTestDone
  cmp   byte[USER_ARG+5],'v'
  jne   MaybePrivTestDone
  cli
  mov   dword[Prog4ExitCode],00000091h
MaybePrivTestDone:
  ret

MaybeMemTest:
  cmp   word[USER_ARG],3
  jne   MaybeMemTestDone
  cmp   byte[USER_ARG+2],'m'
  jne   MaybeMemTestDone
  cmp   byte[USER_ARG+3],'e'
  jne   MaybeMemTestDone
  cmp   byte[USER_ARG+4],'m'
  jne   MaybeMemTestDone
  mov   eax,[00100000h]
  mov   dword[Prog4ExitCode],00000092h
MaybeMemTestDone:
  ret

MaybeLoadTest:
  cmp   word[USER_ARG],4
  jne   MaybeLoadTestDone
  cmp   byte[USER_ARG+2],'l'
  jne   MaybeLoadTestDone
  cmp   byte[USER_ARG+3],'o'
  jne   MaybeLoadTestDone
  cmp   byte[USER_ARG+4],'a'
  jne   MaybeLoadTestDone
  cmp   byte[USER_ARG+5],'d'
  jne   MaybeLoadTestDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_LOAD_PROGRAM
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],Prog1FileName
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],1
  mov   dword[KC_BLOCK+KC_BLOCK_ARG2],1
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_BAD_ARG
  jne   MaybeLoadTestFailed
  mov   dword[Prog4ExitCode],00000048h
  ret
MaybeLoadTestFailed:
  mov   dword[Prog4ExitCode],00000088h
MaybeLoadTestDone:
  ret

MaybeGetMemoryTest:
  cmp   word[USER_ARG],6
  jne   MaybeGetMemoryTestDone
  cmp   byte[USER_ARG+2],'g'
  jne   MaybeGetMemoryTestSystem
  cmp   byte[USER_ARG+3],'e'
  jne   MaybeGetMemoryTestSystem
  cmp   byte[USER_ARG+4],'t'
  jne   MaybeGetMemoryTestSystem
  cmp   byte[USER_ARG+5],'m'
  jne   MaybeGetMemoryTestSystem
  cmp   byte[USER_ARG+6],'e'
  jne   MaybeGetMemoryTestSystem
  cmp   byte[USER_ARG+7],'m'
  jne   MaybeGetMemoryTestSystem
  call  GetMemoryProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_DENIED
  je    MaybeGetMemoryTestDenied
  cmp   eax,STATUS_OK
  jne   MaybeGetMemoryTestDone
  call  CheckMemoryProbe
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   MaybeGetMemoryTestFailed
  mov   dword[pProg4Msg],MsgGetMemoryTrustedOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],0000004Ah
  ret
MaybeGetMemoryTestSystem:
  cmp   byte[USER_ARG+2],'s'
  jne   MaybeGetMemoryTestDone
  cmp   byte[USER_ARG+3],'y'
  jne   MaybeGetMemoryTestDone
  cmp   byte[USER_ARG+4],'s'
  jne   MaybeGetMemoryTestDone
  cmp   byte[USER_ARG+5],'t'
  jne   MaybeGetMemoryTestDone
  cmp   byte[USER_ARG+6],'e'
  jne   MaybeGetMemoryTestDone
  cmp   byte[USER_ARG+7],'m'
  jne   MaybeGetMemoryTestDone
  call  GetMemoryProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeGetMemoryTestFailed
  call  CheckMemoryProbe
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   MaybeGetMemoryTestFailed
  mov   dword[pProg4Msg],MsgGetMemorySystemOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],0000004Bh
  ret
GetMemoryProbe:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_GET_MEMORY
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],4096
  int   080h
  ret

CheckMemoryProbe:
  mov   dword[Prog4Status],1
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  test  eax,eax
  jz    CheckMemoryProbeDone
  mov   [Prog4MemoryPtr],eax
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT1]
  cmp   eax,4096
  jne   CheckMemoryProbeDone
  mov   eax,[Prog4MemoryPtr]
  mov   dword[eax],00C0FFEEh
  cmp   dword[eax],00C0FFEEh
  jne   CheckMemoryProbeDone
  mov   dword[Prog4Status],STATUS_OK
CheckMemoryProbeDone:
  ret
MaybeGetMemoryTestDenied:
  mov   dword[pProg4Msg],MsgGetMemoryDeniedOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000049h
  ret
MaybeGetMemoryTestFailed:
  mov   dword[pProg4Msg],MsgGetMemoryFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000090h
MaybeGetMemoryTestDone:
  ret

MaybeFreeMemoryTest:
  cmp   word[USER_ARG],7
  jne   MaybeFreeMemoryTestSystem
  cmp   byte[USER_ARG+2],'f'
  jne   MaybeBadFreeMemoryTest
  cmp   byte[USER_ARG+3],'r'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+4],'e'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+5],'e'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+6],'m'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+7],'e'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+8],'m'
  jne   MaybeFreeMemoryTestDone
  call  FreeMemoryProbeReal
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_DENIED
  je    MaybeFreeMemoryTestDenied
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   MaybeFreeMemoryTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeFreeMemoryTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT1]
  cmp   eax,4096
  jne   MaybeFreeMemoryTestFailed
  mov   dword[pProg4Msg],MsgFreeMemoryTrustedOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],0000004Dh
  ret
MaybeFreeMemoryTestSystem:
  cmp   word[USER_ARG],10
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+2],'s'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+3],'y'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+4],'s'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+5],'t'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+6],'e'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+7],'m'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+8],'f'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+9],'r'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+10],'e'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+11],'e'
  jne   MaybeFreeMemoryTestDone
  call  FreeMemoryProbeReal
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   MaybeFreeMemoryTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeFreeMemoryTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT1]
  cmp   eax,4096
  jne   MaybeFreeMemoryTestFailed
  mov   dword[pProg4Msg],MsgFreeMemorySystemOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],0000004Eh
  ret

MaybeBadFreeMemoryTest:
  cmp   byte[USER_ARG+2],'b'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+3],'a'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+4],'d'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+5],'f'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+6],'r'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+7],'e'
  jne   MaybeFreeMemoryTestDone
  cmp   byte[USER_ARG+8],'e'
  jne   MaybeFreeMemoryTestDone
  call  BadFreeMemoryProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_BAD_ARG
  jne   MaybeBadFreeMemoryTestFailed
  mov   dword[pProg4Msg],MsgBadFreeMemoryOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000053h
  ret
MaybeBadFreeMemoryTestFailed:
  mov   dword[pProg4Msg],MsgBadFreeMemoryFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000091h
  ret

FreeMemoryProbe:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_FREE_MEMORY
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],0
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],4096
  int   080h
  ret

BadFreeMemoryProbe:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_FREE_MEMORY
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],00200001h
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],4096
  int   080h
  ret

FreeMemoryProbeReal:
  mov   dword[Prog4Status],1
  call  GetMemoryProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   FreeMemoryProbeRealDone
  call  CheckMemoryProbe
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   FreeMemoryProbeRealDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_FREE_MEMORY
  mov   eax,[Prog4MemoryPtr]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],4096
  int   080h
  mov   dword[Prog4Status],STATUS_OK
FreeMemoryProbeRealDone:
  ret
MaybeFreeMemoryTestDenied:
  mov   dword[pProg4Msg],MsgFreeMemoryDeniedOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],0000004Ch
  ret
MaybeFreeMemoryTestFailed:
  mov   dword[pProg4Msg],MsgFreeMemoryFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000090h
MaybeFreeMemoryTestDone:
  ret

MaybeMemoryInfoTest:
  cmp   word[USER_ARG],6
  jne   MaybeMemoryInfoTestDone
  cmp   byte[USER_ARG+2],'m'
  jne   MaybeMemoryInfoTestDone
  cmp   byte[USER_ARG+3],'m'
  jne   MaybeMemoryInfoTestDone
  cmp   byte[USER_ARG+4],'i'
  jne   MaybeMemoryInfoTestDone
  cmp   byte[USER_ARG+5],'n'
  jne   MaybeMemoryInfoTestDone
  cmp   byte[USER_ARG+6],'f'
  jne   MaybeMemoryInfoTestDone
  cmp   byte[USER_ARG+7],'o'
  jne   MaybeMemoryInfoTestDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_INFO
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryInfoTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT1]
  cmp   eax,65536
  jne   MaybeMemoryInfoTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  test  eax,eax
  jz    MaybeMemoryInfoTestFailed
  cmp   eax,[KC_BLOCK+KC_BLOCK_RESULT1]
  ja    MaybeMemoryInfoTestFailed
  mov   dword[pProg4Msg],MsgMemoryInfoOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000054h
  ret
MaybeMemoryInfoTestFailed:
  mov   dword[pProg4Msg],MsgMemoryInfoFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000092h
MaybeMemoryInfoTestDone:
  ret

MaybeMemoryGrowTest:
  cmp   word[USER_ARG],7
  jne   MaybeMemoryGrowTestDone
  cmp   byte[USER_ARG+2],'m'
  jne   MaybeMemoryGrowTestDone
  cmp   byte[USER_ARG+3],'e'
  jne   MaybeMemoryGrowTestDone
  cmp   byte[USER_ARG+4],'m'
  jne   MaybeMemoryGrowTestDone
  cmp   byte[USER_ARG+5],'g'
  jne   MaybeMemoryGrowTestDone
  cmp   byte[USER_ARG+6],'r'
  jne   MaybeMemoryGrowTestDone
  cmp   byte[USER_ARG+7],'o'
  jne   MaybeMemoryGrowTestDone
  cmp   byte[USER_ARG+8],'w'
  jne   MaybeMemoryGrowTestDone
  call  MemoryInfoProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryGrowTestFailed
  mov   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  mov   [Prog4MemoryBefore],eax
  call  GetMemoryProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryGrowTestFailed
  call  CheckMemoryProbe
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryGrowTestFailed
  call  MemoryInfoProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryGrowTestFailed
  mov   eax,[Prog4MemoryBefore]
  add   eax,4096
  cmp   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  jne   MaybeMemoryGrowTestFailed
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_FREE_MEMORY
  mov   eax,[Prog4MemoryPtr]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],4096
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryGrowTestFailed
  call  MemoryInfoProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryGrowTestFailed
  mov   eax,[Prog4MemoryBefore]
  cmp   eax,[KC_BLOCK+KC_BLOCK_RESULT0]
  jne   MaybeMemoryGrowTestFailed
  mov   dword[pProg4Msg],MsgMemoryGrowOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000055h
  ret
MaybeMemoryGrowTestFailed:
  mov   dword[pProg4Msg],MsgMemoryGrowFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000093h
MaybeMemoryGrowTestDone:
  ret

MemoryInfoProbe:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_INFO
  int   080h
  ret

MaybeMemoryOomTest:
  cmp   word[USER_ARG],6
  jne   MaybeMemoryOomTestDone
  cmp   byte[USER_ARG+2],'m'
  jne   MaybeMemoryOomTestDone
  cmp   byte[USER_ARG+3],'e'
  jne   MaybeMemoryOomTestDone
  cmp   byte[USER_ARG+4],'m'
  jne   MaybeMemoryOomTestDone
  cmp   byte[USER_ARG+5],'o'
  jne   MaybeMemoryOomTestDone
  cmp   byte[USER_ARG+6],'o'
  jne   MaybeMemoryOomTestDone
  cmp   byte[USER_ARG+7],'m'
  jne   MaybeMemoryOomTestDone
  mov   dword[Prog4MemoryCount],0
MaybeMemoryOomTestLoop:
  call  GetMemoryProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_BAD_ARG
  je    MaybeMemoryOomTestFull
  cmp   eax,STATUS_OK
  jne   MaybeMemoryOomTestFailed
  inc   dword[Prog4MemoryCount]
  call  CheckMemoryProbe
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryOomTestFailed
  cmp   dword[Prog4MemoryCount],20
  ja    MaybeMemoryOomTestFailed
  jmp   MaybeMemoryOomTestLoop
MaybeMemoryOomTestFull:
  cmp   dword[Prog4MemoryCount],0
  je    MaybeMemoryOomTestFailed
  mov   dword[pProg4Msg],MsgMemoryOomOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000056h
  ret
MaybeMemoryOomTestFailed:
  mov   dword[pProg4Msg],MsgMemoryOomFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000094h
MaybeMemoryOomTestDone:
  ret

MaybeMemoryFreeOrderTest:
  cmp   word[USER_ARG],12
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+2],'m'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+3],'e'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+4],'m'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+5],'f'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+6],'r'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+7],'e'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+8],'e'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+9],'o'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+10],'r'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+11],'d'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+12],'e'
  jne   MaybeMemoryFreeOrderTestDone
  cmp   byte[USER_ARG+13],'r'
  jne   MaybeMemoryFreeOrderTestDone
  call  GetMemoryProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryFreeOrderTestFailed
  call  CheckMemoryProbe
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryFreeOrderTestFailed
  mov   eax,[Prog4MemoryPtr]
  mov   [Prog4MemoryPtr1],eax
  call  GetMemoryProbe
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryFreeOrderTestFailed
  call  CheckMemoryProbe
  mov   eax,[Prog4Status]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryFreeOrderTestFailed
  mov   eax,[Prog4MemoryPtr]
  mov   [Prog4MemoryPtr2],eax
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_FREE_MEMORY
  mov   eax,[Prog4MemoryPtr1]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],4096
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_BAD_ARG
  jne   MaybeMemoryFreeOrderTestFailed
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_FREE_MEMORY
  mov   eax,[Prog4MemoryPtr2]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],4096
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryFreeOrderTestFailed
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_MM_FREE_MEMORY
  mov   eax,[Prog4MemoryPtr1]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],4096
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_OK
  jne   MaybeMemoryFreeOrderTestFailed
  mov   dword[pProg4Msg],MsgMemoryFreeOrderOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000057h
  ret
MaybeMemoryFreeOrderTestFailed:
  mov   dword[pProg4Msg],MsgMemoryFreeOrderFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000095h
MaybeMemoryFreeOrderTestDone:
  ret

MaybeLegacyTest:
  cmp   word[USER_ARG],6
  jne   MaybeLegacyTestDone
  cmp   byte[USER_ARG+2],'l'
  jne   MaybeLegacyTestDone
  cmp   byte[USER_ARG+3],'e'
  jne   MaybeLegacyTestDone
  cmp   byte[USER_ARG+4],'g'
  jne   MaybeLegacyTestDone
  cmp   byte[USER_ARG+5],'a'
  jne   MaybeLegacyTestDone
  cmp   byte[USER_ARG+6],'c'
  jne   MaybeLegacyTestDone
  cmp   byte[USER_ARG+7],'y'
  jne   MaybeLegacyTestDone
  mov   ebx,LEGACY_KC_GATEWAY
  call  ebx
  mov   dword[Prog4ExitCode],00000087h
MaybeLegacyTestDone:
  ret

MaybeBadZeroCallTest:
  cmp   word[USER_ARG],13
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+2],'b'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+3],'a'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+4],'d'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+5],'-'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+6],'z'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+7],'e'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+8],'r'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+9],'o'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+10],'-'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+11],'c'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+12],'a'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+13],'l'
  jne   MaybeBadZeroCallTestDone
  cmp   byte[USER_ARG+14],'l'
  jne   MaybeBadZeroCallTestDone
  call  BadZeroCallTest
MaybeBadZeroCallTestDone:
  ret

MaybeBadCallNumberTest:
  cmp   word[USER_ARG],15
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+2],'b'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+3],'a'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+4],'d'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+5],'-'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+6],'c'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+7],'a'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+8],'l'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+9],'l'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+10],'-'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+11],'n'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+12],'u'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+13],'m'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+14],'b'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+15],'e'
  jne   MaybeBadCallNumberTestDone
  cmp   byte[USER_ARG+16],'r'
  jne   MaybeBadCallNumberTestDone
  call  BadCallNumberTest
MaybeBadCallNumberTestDone:
  ret

BadPrintTest:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_VD_WRITE_STR
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],00100000h
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_BAD_ARG
  jne   BadPrintTestFailed
  mov   dword[pProg4Msg],MsgBadPrintOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000042h
  ret
BadPrintTestFailed:
  mov   dword[pProg4Msg],MsgBadPrintFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000099h
  ret

BadOpenTest:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_FS_OPEN
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],00100000h
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_BAD_ARG
  jne   BadOpenTestFailed
  mov   dword[pProg4Msg],MsgBadOpenOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000043h
  ret
BadOpenTestFailed:
  mov   dword[pProg4Msg],MsgBadOpenFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000098h
  ret

BadReadTest:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_FS_READ
  mov   eax,[DataHandle]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   dword[KC_BLOCK+KC_BLOCK_ARG1],00100000h
  mov   dword[KC_BLOCK+KC_BLOCK_ARG2],DATA_BUFFER_SIZE
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_BAD_ARG
  jne   BadReadTestFailed
  mov   dword[pProg4Msg],MsgBadReadOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000044h
  ret
BadReadTestFailed:
  mov   dword[pProg4Msg],MsgBadReadFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000097h
  ret

BadZeroCallTest:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],0
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_INVALID
  jne   BadZeroCallTestFailed
  mov   dword[pProg4Msg],MsgBadZeroCallOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000045h
  ret
BadZeroCallTestFailed:
  mov   dword[pProg4Msg],MsgBadZeroCallFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000096h
  ret

BadCallNumberTest:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],9999
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_INVALID
  jne   BadCallNumberTestFailed
  mov   dword[pProg4Msg],MsgBadCallNumberOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000046h
  ret
BadCallNumberTestFailed:
  mov   dword[pProg4Msg],MsgBadCallNumberFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],00000095h
  ret

PrintProg4Msg:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_VD_WRITE_STR
  mov   eax,[pProg4Msg]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  int   080h
  ret

CloseFile:
  mov   eax,[DataHandle]
  test  eax,eax
  jz    CloseFileDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_FS_CLOSE
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  int   080h
CloseFileDone:
  ret

ExitProgram:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_EXIT
  mov   eax,[Prog4ExitCode]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  int   080h
  ret

align 4
DataHandle           dd 0
Prog4ExitCode        dd 0
Prog4Status          dd 0
pProg4Msg            dd 0
DataFileName         dw 8
                     db "DATA.TXT"
Prog1FileName        dw 9
                     db "PROG1.BIN"
MsgBadPrintOk        dw 21
                     db "Prog4: bad-print OK",13,10
MsgBadPrintFail      dw 23
                     db "Prog4: bad-print FAIL",13,10
MsgBadOpenOk         dw 20
                     db "Prog4: bad-open OK",13,10
MsgBadOpenFail       dw 22
                     db "Prog4: bad-open FAIL",13,10
MsgBadReadOk         dw 20
                     db "Prog4: bad-read OK",13,10
MsgBadReadFail       dw 22
                     db "Prog4: bad-read FAIL",13,10
MsgBadZeroCallOk     dw 25
                     db "Prog4: bad-zero-call OK",13,10
MsgBadZeroCallFail   dw 27
                     db "Prog4: bad-zero-call FAIL",13,10
MsgBadCallNumberOk   dw 27
                     db "Prog4: bad-call-number OK",13,10
MsgBadCallNumberFail dw 29
                     db "Prog4: bad-call-number FAIL",13,10
MsgKeyPrompt         dw 20
                     db "Prog4: press a key",13,10
MsgKeyOk             dw 15
                     db "Prog4: key OK",13,10
MsgKeyFail           dw 17
                     db "Prog4: key FAIL",13,10
MsgInt80Ok           dw 17
                     db "Prog4: int80 OK",13,10
MsgInt80Fail         dw 19
                     db "Prog4: int80 FAIL",13,10
MsgGetMemoryDeniedOk dw 25
                     db "Prog4: getmem denied OK",13,10
MsgGetMemoryTrustedOk dw 26
                     db "Prog4: getmem trusted OK",13,10
MsgGetMemorySystemOk dw 25
                     db "Prog4: getmem system OK",13,10
MsgGetMemoryFail     dw 20
                     db "Prog4: getmem FAIL",13,10
MsgFreeMemoryDeniedOk dw 26
                     db "Prog4: freemem denied OK",13,10
MsgFreeMemoryTrustedOk dw 27
                     db "Prog4: freemem trusted OK",13,10
MsgFreeMemorySystemOk dw 26
                     db "Prog4: freemem system OK",13,10
MsgFreeMemoryFail    dw 21
                     db "Prog4: freemem FAIL",13,10
MsgBadFreeMemoryOk   dw 19
                     db "Prog4: badfree OK",13,10
MsgBadFreeMemoryFail dw 21
                     db "Prog4: badfree FAIL",13,10
MsgMemoryInfoOk     dw 18
                     db "Prog4: mminfo OK",13,10
MsgMemoryInfoFail   dw 20
                     db "Prog4: mminfo FAIL",13,10
MsgMemoryGrowOk     dw 19
                     db "Prog4: memgrow OK",13,10
MsgMemoryGrowFail   dw 21
                     db "Prog4: memgrow FAIL",13,10
MsgMemoryOomOk      dw 18
                     db "Prog4: memoom OK",13,10
MsgMemoryOomFail    dw 20
                     db "Prog4: memoom FAIL",13,10
MsgMemoryFreeOrderOk dw 24
                     db "Prog4: memfreeorder OK",13,10
MsgMemoryFreeOrderFail dw 26
                     db "Prog4: memfreeorder FAIL",13,10
MsgAuthNormalOk      dw 23
                     db "Prog4: auth normal OK",13,10
MsgAuthTrustedOk     dw 24
                     db "Prog4: auth trusted OK",13,10
MsgAuthSystemOk      dw 23
                     db "Prog4: auth system OK",13,10
MsgAuthFail          dw 18
                     db "Prog4: auth FAIL",13,10
Prog4MemoryPtr       dd 0
Prog4MemoryBefore    dd 0
Prog4MemoryCount     dd 0
Prog4MemoryPtr1      dd 0
Prog4MemoryPtr2      dd 0
DataBuffer           dw 0
DataBufferText:
  times DATA_BUFFER_SIZE db 0
