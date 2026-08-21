;**************************************************************************************************
; Prog4.asm
;   Tiny user-program file I/O sketch.
;**************************************************************************************************

[bits 32]
  org   00200000h

KERNEL_CALL_GATEWAY equ 00100005h
KC_TM_SLEEP         equ 9
KC_VD_WRITE_STR     equ 2
KC_TS_EXIT          equ 5
KC_FS_OPEN          equ 6
KC_FS_READ          equ 7
KC_FS_CLOSE         equ 8
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
  call  MaybeSleepTest                  ; Optional cooperative sleep proof
  call  MaybeBadPrintTest               ; Optional bad-print proof
  call  MaybeBadOpenTest                ; Optional bad-open proof
  call  MaybeBadReadTest                ; Optional bad-read proof
Prog4CloseAndExit:
  call  CloseFile                       ; Close file
Prog4Exit:
  call  ExitProgram                     ; Return to OS

OpenFile:
  mov   dword[DataHandle],0
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_FS_OPEN
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],DataFileName
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
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
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
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
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
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
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
  mov   dword[Prog4ExitCode],7
MaybeSleepTestDone:
  ret

BadPrintTest:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_VD_WRITE_STR
  mov   dword[KC_BLOCK+KC_BLOCK_ARG0],00100000h
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
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
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
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
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
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

PrintProg4Msg:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_VD_WRITE_STR
  mov   eax,[pProg4Msg]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
  ret

CloseFile:
  mov   eax,[DataHandle]
  test  eax,eax
  jz    CloseFileDone
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_FS_CLOSE
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
CloseFileDone:
  ret

ExitProgram:
  mov   dword[KC_BLOCK+KC_BLOCK_NUMBER],KC_TS_EXIT
  mov   eax,[Prog4ExitCode]
  mov   [KC_BLOCK+KC_BLOCK_ARG0],eax
  mov   ebx,KERNEL_CALL_GATEWAY
  call  ebx
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
DataBuffer           dw 0
DataBufferText:
  times DATA_BUFFER_SIZE db 0
