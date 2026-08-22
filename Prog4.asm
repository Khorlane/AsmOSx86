;**************************************************************************************************
; Prog4.asm
;   Tiny user-program file I/O sketch.
;**************************************************************************************************

[bits 32]
  org   00200000h

KC_TM_SLEEP         equ 9
KC_VD_WRITE_STR     equ 2
KC_TS_EXIT          equ 5
KC_FS_OPEN          equ 6
KC_FS_READ          equ 7
KC_FS_CLOSE         equ 8
KC_KB_READ          equ 10
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
  call  MaybeKeyTest                    ; Optional keyboard read proof
  call  MaybeSleepTest                  ; Optional cooperative sleep proof
  call  MaybePrivTest                   ; Optional privilege-fault proof
  call  MaybeMemTest                    ; Optional kernel-memory fault proof
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
  mov   dword[Prog4ExitCode],47
  ret
MaybeKeyTestFailed:
  mov   dword[pProg4Msg],MsgKeyFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],94
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
  mov   dword[Prog4ExitCode],80
  ret
MaybeInt80TestFailed:
  mov   dword[pProg4Msg],MsgInt80Fail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],93
MaybeInt80TestDone:
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
  mov   dword[Prog4ExitCode],91
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
  mov   dword[Prog4ExitCode],92
MaybeMemTestDone:
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
  mov   dword[Prog4ExitCode],42
  ret
BadPrintTestFailed:
  mov   dword[pProg4Msg],MsgBadPrintFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],99
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
  mov   dword[Prog4ExitCode],43
  ret
BadOpenTestFailed:
  mov   dword[pProg4Msg],MsgBadOpenFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],98
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
  mov   dword[Prog4ExitCode],44
  ret
BadReadTestFailed:
  mov   dword[pProg4Msg],MsgBadReadFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],97
  ret

BadZeroCallTest:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],0
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_INVALID
  jne   BadZeroCallTestFailed
  mov   dword[pProg4Msg],MsgBadZeroCallOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],45
  ret
BadZeroCallTestFailed:
  mov   dword[pProg4Msg],MsgBadZeroCallFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],96
  ret

BadCallNumberTest:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],9999
  int   080h
  mov   eax,[KC_BLOCK+KC_BLOCK_STATUS]
  cmp   eax,STATUS_INVALID
  jne   BadCallNumberTestFailed
  mov   dword[pProg4Msg],MsgBadCallNumberOk
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],46
  ret
BadCallNumberTestFailed:
  mov   dword[pProg4Msg],MsgBadCallNumberFail
  call  PrintProg4Msg
  mov   dword[Prog4ExitCode],95
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
DataBuffer           dw 0
DataBufferText:
  times DATA_BUFFER_SIZE db 0
