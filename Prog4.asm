;**************************************************************************************************
; Prog4.asm
;   Tiny user-program file I/O sketch.
;**************************************************************************************************

[bits 32]
  org   00200000h

KERNEL_CALL_GATEWAY equ 00100005h
KC_VD_WRITE_STR     equ 2
KC_TS_EXIT          equ 5
KC_FS_OPEN          equ 6
KC_FS_READ          equ 7
KC_FS_CLOSE         equ 8
KC_BLOCK            equ 00210000h
KC_BLOCK_NUMBER     equ 0
KC_BLOCK_STATUS     equ 4
KC_BLOCK_ARG0       equ 8
KC_BLOCK_ARG1       equ 12
KC_BLOCK_ARG2       equ 16
KC_BLOCK_RESULT0    equ 24
KC_BLOCK_RESULT1    equ 28
STATUS_OK           equ 0
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
DataFileName         dw 8
                     db "DATA.TXT"
DataBuffer           dw 0
DataBufferText:
  times DATA_BUFFER_SIZE db 0
