;==============================================================================
; Video.asm (Vd) - drop-in replacement (v0.0.1)
; 32-bit NASM, single-binary (%include), no sections, no globals
;
; FIXES:
; - Do not rely on any register value across CALL boundaries.
; - VdInClearLine no longer uses AX as a loop counter across a call.
; - VdPutChar_BS ensures erase char is set immediately before erase writes.
; - VdScrollOutputRegion avoids REP MOVSD to remove reliance on implicit state.
;
; Screen: Rows=25, Cols=80
; Output region (scrolls): rows 0..23
; Input line (fixed):      row 24
; Row,Col ordering everywhere (row first, then col)
;==============================================================================

[bits 32]

; ----- Video constants -----
VD_COLS         equ 80
VD_ROWS         equ 25
VD_OUT_MAX_ROW  equ 23
VD_IN_ROW       equ 24

VGA_TEXT_BASE   equ 0xB8000
VD_ATTR_DEFAULT equ 0x07

;------------------------------------------------------------------------------
; VdInit
; Initializes the video output and input cursor state.
;
; Output (memory):
;   VdOutCurRow = 0    ; Output region row set to 0
;   VdOutCurCol = 0    ; Output region column set to 0
;   VdInCurCol  = 0    ; Input line column set to 0
;
; Notes:
; - Should be called once at system startup or reset.
; - Ensures video cursor state is in a known, clean state.
;------------------------------------------------------------------------------
VdInit:
  mov   word [VdOutCurRow],0
  mov   word [VdOutCurCol],0
  mov   word [VdInCurCol],0
  call  VdClear
  ret

;------------------------------------------------------------------------------
; VdPutStr
; Input (memory):
;   VdInStrPtr -> String [u16 len][bytes...]
;------------------------------------------------------------------------------
VdPutStr:
  mov   esi,[VdInStrPtr]
  movzx ecx,word [esi]
  add   esi,2
VdPutStrNext:
  test  ecx,ecx
  jz    VdPutStrDone
  mov   al,[esi]
  inc   esi
  dec   ecx
  mov   [VdInCh],al
  call  VdPutChar
  jmp   VdPutStrNext
VdPutStrDone:
  ret

;------------------------------------------------------------------------------
; VdPutChar (output region only: rows 0..23)
; Input (memory):
;   VdInCh = byte
;
; Control chars supported:
;   0x0D CR: col=0
;   0x0A LF: row++ with scroll inside output region
;   0x08 BS: move left, erase char, move left (within row)
;------------------------------------------------------------------------------
VdPutChar:
  mov   al,[VdInCh]
  cmp   al,0x0D
  je    VdPutCharCR
  cmp   al,0x0A
  je    VdPutCharLF
  cmp   al,0x08
  je    VdPutCharBS
  movzx eax,word [VdOutCurRow]
  cmp   eax,VD_OUT_MAX_ROW
  jbe   VdPutCharRowOk
  mov   word [VdOutCurRow],VD_OUT_MAX_ROW
VdPutCharRowOk:
  call  VdWriteOutCharAtCursor
  movzx eax,word [VdOutCurCol]
  inc   eax
  cmp   eax,VD_COLS
  jb    VdPutCharSetCol
  mov   word [VdOutCurCol],0
  jmp   VdPutCharLF
VdPutCharSetCol:
  mov   [VdOutCurCol],ax
  ret
VdPutCharCR:
  mov   word [VdOutCurCol],0
  ret
VdPutCharLF:
  movzx eax,word [VdOutCurRow]
  inc   eax
  cmp   eax,VD_OUT_MAX_ROW
  jbe   VdPutCharSetRow
  call  VdScrollOutputRegion
  mov   word [VdOutCurRow],VD_OUT_MAX_ROW
  ret
VdPutCharSetRow:
  mov   [VdOutCurRow],ax
  ret
VdPutCharBS:
  movzx eax,word [VdOutCurCol]
  test  eax,eax
  jz    VdPutCharBSDone
  dec   eax
  mov   [VdOutCurCol],ax
  mov   byte [VdInCh],' '
  call  VdWriteOutCharAtCursor
  movzx eax,word [VdOutCurCol]
  test  eax,eax
  jz    VdPutCharBSDone
  dec   eax
  mov   [VdOutCurCol],ax
VdPutCharBSDone:
  ret

;------------------------------------------------------------------------------
; VdInPutChar (input line only: row 24)
; Input:
;   VdInCh
; Stops at right edge (no scroll).
;------------------------------------------------------------------------------
VdInPutChar:
  movzx eax,word [VdInCurCol]
  cmp   eax,VD_COLS
  jae   VdInPutCharDone
  call  VdWriteInCharAtCursor
  movzx eax,word [VdInCurCol]
  inc   eax
  mov   [VdInCurCol],ax
VdInPutCharDone:
  ret

;------------------------------------------------------------------------------
; VdInBackspaceVisual
; - Moves left one column (if possible)
; - Overwrites with space
; - Cursor remains at erased position
;------------------------------------------------------------------------------
VdInBackspaceVisual:
  movzx eax,word [VdInCurCol]
  test  eax,eax
  jz    VdInBackspaceVisualDone
  dec   eax
  mov   [VdInCurCol],ax
  mov   byte [VdInCh],' '
  call  VdWriteInCharAtCursor
VdInBackspaceVisualDone:
  ret

;------------------------------------------------------------------------------
; VdInClearLine
; Clears row 24 and sets InCurCol=0
;
; IMPORTANT:
; - Do not use AX/EAX as the loop counter across CALL boundaries.
;------------------------------------------------------------------------------
VdInClearLine:
  mov   word [VdInCurCol],0
  mov   word [VdWorkCol],0
VdInClearLineLoop:
  movzx eax,word [VdWorkCol]
  cmp   eax,VD_COLS
  jae   VdInClearLineDone
  mov   [VdInCurCol],ax
  mov   byte [VdInCh],' '
  call  VdWriteInCharAtCursor
  mov   ax,[VdWorkCol]
  inc   ax
  mov   [VdWorkCol],ax
  jmp   VdInClearLineLoop
VdInClearLineDone:
  mov   word [VdInCurCol],0
  ret

;------------------------------------------------------------------------------
; Internal helpers
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; VdWriteOutCharAtCursor
; Writes the character in VdInCh to the VGA text buffer at the current output
; region position (row = VdOutCurRow, col = VdOutCurCol) with the default attribute.
;
; Input (memory):
;   VdInCh        = Character to write (byte)
;   VdOutCurRow   = Output row (word)
;   VdOutCurCol   = Output column (word)
;
; Output:
;   Writes character and attribute to VGA memory at (VdOutCurRow, VdOutCurCol)
;
; Notes:
;   - Does not advance the cursor or modify VdOutCurRow/VdOutCurCol.
;   - Follows PascalCase and column alignment (LOCKED-IN).
;------------------------------------------------------------------------------
VdWriteOutCharAtCursor:
  movzx eax,word [VdOutCurRow]
  imul  eax,VD_COLS
  movzx edx,word [VdOutCurCol]
  add   eax,edx
  shl   eax,1
  mov   edi,VGA_TEXT_BASE
  add   edi,eax
  mov   al,[VdInCh]
  mov   ah,VD_ATTR_DEFAULT
  mov   [edi],ax
  ret

;------------------------------------------------------------------------------
; VdWriteInCharAtCursor
; Writes the character in VdInCh to the VGA text buffer at the input line
; position (row 24, column = VdInCurCol) with the default attribute.
;
; Input (memory):
;   VdInCh      = Character to write (byte)
;   VdInCurCol  = Column position on input line (word)
;
; Output:
;   Writes character and attribute to VGA memory at (24, VdInCurCol)
;
; Notes:
;   - Does not advance the cursor or modify VdInCurCol.
;   - Uses PascalCase and column alignment (LOCKED-IN).
;------------------------------------------------------------------------------
VdWriteInCharAtCursor:
  mov   eax,VD_IN_ROW
  imul  eax,VD_COLS
  movzx edx,word [VdInCurCol]
  add   eax,edx
  shl   eax,1
  mov   edi,VGA_TEXT_BASE
  add   edi,eax
  mov   al,[VdInCh]
  mov   ah,VD_ATTR_DEFAULT
  mov   [edi],ax
  ret

;------------------------------------------------------------------------------
; VdScrollOutputRegion
; Scroll output region rows 0..23 up by one line; clear row 23.
;
; Avoid REP MOVSD to eliminate reliance on:
; - ECX/ESI/EDI preservation assumptions
; - direction flag assumptions
;------------------------------------------------------------------------------
VdScrollOutputRegion:
  mov   dword [VdWorkCount],VD_OUT_MAX_ROW * 160
  mov   esi,VGA_TEXT_BASE
  mov   edi,VGA_TEXT_BASE
  add   esi,160
VdScrollCopyLoop:
  mov   eax,[VdWorkCount]
  test  eax,eax
  jz    VdScrollClearRow
  mov   eax,[esi]
  mov   [edi],eax
  add   esi,4
  add   edi,4
  mov   eax,[VdWorkCount]
  sub   eax,4
  mov   [VdWorkCount],eax
  jmp   VdScrollCopyLoop
VdScrollClearRow:
  mov   edi,VGA_TEXT_BASE
  add   edi,VD_OUT_MAX_ROW * 160
  mov   word [VdWorkCol],0
VdScrollClearLoop:
  movzx eax,word [VdWorkCol]
  cmp   eax,VD_COLS
  jae   VdScrollDone
  mov   ax,(VD_ATTR_DEFAULT << 8) | ' '
  mov   [edi],ax
  add   edi,2
  mov   ax,[VdWorkCol]
  inc   ax
  mov   [VdWorkCol],ax
  jmp   VdScrollClearLoop
VdScrollDone:
  ret

;------------------------------------------------------------------------------
; VdClear
; Clears the entire screen (all rows and columns) by writing spaces with the default attribute.
;
; Output:
;   VGA text buffer is filled with spaces and default attribute.
;
; Notes:
; - Resets output and input cursor positions to zero.
;------------------------------------------------------------------------------
VdClear:
  mov   edi,VGA_TEXT_BASE
  mov   ecx,VD_COLS * VD_ROWS
VdClearLoop:
  mov   ax,(VD_ATTR_DEFAULT << 8) | ' '
  mov   [edi],ax
  add   edi,2
  loop  VdClearLoop
  mov   word [VdOutCurRow],0
  mov   word [VdOutCurCol],0
  mov   word [VdInCurCol],0
  ret

; ----- Storage -----
VdInCh           db 0
VdPad0           db 0,0,0
VdInStrPtr       dd 0
VdOutCurRow      dw 0
VdOutCurCol      dw 0
VdInCurCol       dw 0
VdPad1           dw 0
VdWorkCol        dw 0
VdWorkPad2       dw 0
VdWorkCount      dd 0