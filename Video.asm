;==============================================================================
; Video.asm (Vd) - drop-in replacement (v0.0.1)
; 32-bit NASM, single-binary (%include), no sections, no globals
;
; FIXES:
; - Do not rely on any register value across CALL boundaries.
; - VdInClearLine no longer uses AX as a loop counter across a call.
; - VdPutChar_BS ensures erase char is set immediately before erase writes.
; - VdScrollOutputRegion avoids REP MOVSD to remove reliance on implicit state.
; - Cursor contract is now 1-based:
;     Row 1, Col 1 maps to VGA offset 0 (0xB8000 + 0 bytes)
;
; Screen: Rows=25, Cols=80
; Output region (scrolls): rows 1..24
; Input line (fixed):      row 25
; Row,Col ordering everywhere (row first, then col)
;==============================================================================

[bits 32]

; ----- Video constants -----
VD_COLS         equ 80
VD_ROWS         equ 25
VD_OUT_MAX_ROW  equ 24                   ; Output region rows 1..24 (scrolls)
VD_IN_ROW       equ 25                   ; Input line row 25 (fixed)

VGA_TEXT_BASE   equ 0xB8000
VD_ATTR_DEFAULT equ 0x07
VGA_CRTC_INDEX  equ 0x3D4
VGA_CRTC_DATA   equ 0x3D5

;------------------------------------------------------------------------------
; VdInit
; Initializes the video output and input cursor state.
;
; Output (memory):
;   VdOutCurRow = 1    ; Output region row set to 1 (1-based)
;   VdOutCurCol = 1    ; Output region column set to 1 (1-based)
;   VdInCurCol  = 1    ; Input line column set to 1 (1-based)
;
; Notes:
; - Should be called once at system startup or reset.
; - Ensures video cursor state is in a known, clean state.
; - Row 1, Col 1 maps to VGA offset 0.
;------------------------------------------------------------------------------
VdInit:
  mov   ax,1
  mov   [VdOutCurRow],ax
  mov   [VdOutCurCol],ax
  mov   [VdInCurCol],ax
  call  VdClear

  mov   ax,1
  mov   [VdCurRow],ax
  mov   ax,1
  mov   [VdCurCol],ax

  ret

;------------------------------------------------------------------------------
; VdPutStr
; Input (memory):
;   VdInStrPtr -> String [u16 len][bytes...]
;------------------------------------------------------------------------------
VdPutStr:
  mov   esi,[VdInStrPtr]
  mov   ax,[esi]
  movzx ecx,ax
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
; VdPutChar (output region only: rows 1..24)
; Input (memory):
;   VdInCh = byte
;
; Control chars supported:
;   0x0D CR: col=1 (1-based)
;   0x0A LF: row++ with scroll inside output region (rows 1..24)
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
  mov   ax,[VdOutCurRow]
  movzx eax,ax
  cmp   eax,VD_OUT_MAX_ROW
  jbe   VdPutCharRowOk
  mov   ax,VD_OUT_MAX_ROW
  mov   [VdOutCurRow],ax
VdPutCharRowOk:
  call  VdWriteOutCharAtCursor
  mov   ax,[VdOutCurCol]
  movzx eax,ax
  inc   eax
  cmp   eax,(VD_COLS + 1)               ; past col 80?
  jb    VdPutCharSetCol
  mov   ax,1
  mov   [VdOutCurCol],ax
  jmp   VdPutCharLF
VdPutCharSetCol:
  mov   [VdOutCurCol],ax
  ret
VdPutCharCR:
  mov   ax,1
  mov   [VdOutCurCol],ax
  ret
VdPutCharLF:
  mov   ax,[VdOutCurRow]
  movzx eax,ax
  inc   eax
  cmp   eax,VD_OUT_MAX_ROW
  jbe   VdPutCharSetRow
  call  VdScrollOutputRegion
  mov   ax,VD_OUT_MAX_ROW
  mov   [VdOutCurRow],ax
  ret
VdPutCharSetRow:
  mov   [VdOutCurRow],ax
  ret
VdPutCharBS:
  mov   ax,[VdOutCurCol]
  movzx eax,ax
  cmp   eax,1
  jbe   VdPutCharBSDone
  dec   eax
  mov   [VdOutCurCol],ax
  mov   al,' '
  mov   [VdInCh],al
  call  VdWriteOutCharAtCursor
  mov   ax,[VdOutCurCol]
  movzx eax,ax
  cmp   eax,1
  jbe   VdPutCharBSDone
  dec   eax
  mov   [VdOutCurCol],ax
VdPutCharBSDone:
  ret

;------------------------------------------------------------------------------
; VdInPutChar (input line only: row 25)
; Input:
;   VdInCh
; Stops at right edge (no scroll).
;
; Notes:
; - VdInCurCol is 1-based and clamps at 80.
;------------------------------------------------------------------------------
VdInPutChar:
  mov   ax,[VdInCurCol]
  movzx eax,ax
  cmp   eax,VD_COLS
  ja    VdInPutCharDone
  call  VdWriteInCharAtCursor
  mov   ax,[VdInCurCol]
  movzx eax,ax
  inc   eax
  mov   [VdInCurCol],ax
VdInPutCharDone:
  ret

;------------------------------------------------------------------------------
; VdInBackspaceVisual
; - Moves left one column (if possible)
; - Overwrites with space
; - Cursor remains at erased position
;
; Notes:
; - VdInCurCol is 1-based; cannot backspace past column 1.
;------------------------------------------------------------------------------
VdInBackspaceVisual:
  mov   ax,[VdInCurCol]
  movzx eax,ax
  cmp   eax,1
  jbe   VdInBackspaceVisualDone
  dec   eax
  mov   [VdInCurCol],ax
  mov   al,' '
  mov   [VdInCh],al
  call  VdWriteInCharAtCursor
VdInBackspaceVisualDone:
  ret

;------------------------------------------------------------------------------
; VdInClearLine
; Clears row 25 and sets InCurCol=1
;
; IMPORTANT:
; - Do not use AX/EAX as the loop counter across CALL boundaries.
; - VdInCurCol is 1-based.
;------------------------------------------------------------------------------
VdInClearLine:
  mov   ax,1
  mov   [VdInCurCol],ax
  mov   [VdWorkCol],ax
VdInClearLineLoop:
  mov   ax,[VdWorkCol]
  movzx eax,ax
  cmp   eax,(VD_COLS + 1)
  jae   VdInClearLineDone
  mov   [VdInCurCol],ax
  mov   al,' '
  mov   [VdInCh],al
  call  VdWriteInCharAtCursor
  mov   ax,[VdWorkCol]
  inc   ax
  mov   [VdWorkCol],ax
  jmp   VdInClearLineLoop
VdInClearLineDone:
  mov   ax,1
  mov   [VdInCurCol],ax
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
;   VdOutCurRow   = Output row (1-based, 1..24)
;   VdOutCurCol   = Output column (1-based, 1..80)
;
; Output:
;   Writes character and attribute to VGA memory at (VdOutCurRow, VdOutCurCol)
;
; Notes:
;   - Does not advance the cursor or modify VdOutCurRow/VdOutCurCol.
;   - Row 1, Col 1 maps to VGA offset 0.
;   - Follows PascalCase and column alignment (LOCKED-IN).
;------------------------------------------------------------------------------
VdWriteOutCharAtCursor:
  mov   ax,[VdOutCurRow]
  movzx eax,ax
  dec   eax                               ; row0 = row-1
  imul  eax,VD_COLS
  mov   dx,[VdOutCurCol]
  movzx edx,dx
  dec   edx                               ; col0 = col-1
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
; position (row 25, column = VdInCurCol) with the default attribute.
;
; Input (memory):
;   VdInCh      = Character to write (byte)
;   VdInCurCol  = Column position on input line (1-based, 1..80)
;
; Output:
;   Writes character and attribute to VGA memory at (25, VdInCurCol)
;
; Notes:
;   - Does not advance the cursor or modify VdInCurCol.
;   - Row 1, Col 1 maps to VGA offset 0, so row 25 maps to row0=24.
;   - Uses PascalCase and column alignment (LOCKED-IN).
;------------------------------------------------------------------------------
VdWriteInCharAtCursor:
  mov   eax,VD_IN_ROW
  dec   eax                               ; row0 = 24
  imul  eax,VD_COLS
  mov   dx,[VdInCurCol]
  movzx edx,dx
  dec   edx                               ; col0 = col-1
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
; Scroll output region rows 1..24 up by one line; clear row 24.
;
; Avoid REP MOVSD to eliminate reliance on:
; - ECX/ESI/EDI preservation assumptions
; - direction flag assumptions
;
; Notes:
; - Copies rows 2..24 over rows 1..23 (23 rows).
; - Clears row 24.
;------------------------------------------------------------------------------
VdScrollOutputRegion:
  mov   eax,(VD_OUT_MAX_ROW - 1) * 160    ; 23 rows * 160 bytes/row
  mov   [VdWorkCount],eax
  mov   esi,VGA_TEXT_BASE
  mov   edi,VGA_TEXT_BASE
  add   esi,160                           ; start at row2 (row0=1)
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
  add   edi,(VD_OUT_MAX_ROW - 1) * 160    ; row24 start (row0=23)
  mov   ax,1
  mov   [VdWorkCol],ax
VdScrollClearLoop:
  mov   ax,[VdWorkCol]
  movzx eax,ax
  cmp   eax,(VD_COLS + 1)
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
; - Resets output and input cursor positions to row=1, col=1 (1-based).
;------------------------------------------------------------------------------
VdClear:
  mov   edi,VGA_TEXT_BASE
  mov   ecx,VD_COLS * VD_ROWS
VdClearLoop:
  mov   ax,(VD_ATTR_DEFAULT << 8) | ' '
  mov   [edi],ax
  add   edi,2
  loop  VdClearLoop
  mov   ax,1
  mov   [VdOutCurRow],ax
  mov   [VdOutCurCol],ax
  mov   [VdInCurCol],ax
  ret

;------------------------------------------------------------------------------
; VdSetCursor
; Sets the hardware VGA text cursor to a specific screen position.
;
; Input (memory):
;   VdCurRow = desired row (1..25)
;   VdCurCol = desired col (1..80)
;
; Output (memory):
;   VdOutCurRow / VdOutCurCol updated if row<=24
;   VdInCurCol updated if row==25
;
; Notes:
; - Row,Col ordering (row first, then col)
; - Clamps to 1-based screen bounds
; - Row 1, Col 1 maps to VGA offset 0
; - Also programs the VGA hardware cursor via ports 0x3D4/0x3D5
;------------------------------------------------------------------------------
VdSetCursor:
  ; Clamp row to 1..25
  mov   ax,[VdCurRow]
  movzx eax,ax
  test  eax,eax
  jnz   VdSetCursorRowMinOk
  mov   eax,1
VdSetCursorRowMinOk:
  cmp   eax,VD_IN_ROW
  jbe   VdSetCursorRowOk
  mov   eax,VD_IN_ROW
VdSetCursorRowOk:
  mov   [VdCurRow],ax
  ; Clamp col to 1..80
  mov   dx,[VdCurCol]
  movzx edx,dx
  test  edx,edx
  jnz   VdSetCursorColMinOk
  mov   edx,1
VdSetCursorColMinOk:
  cmp   edx,VD_COLS
  jbe   VdSetCursorColOk
  mov   edx,VD_COLS
VdSetCursorColOk:
  mov   [VdCurCol],dx
  ; Compute linear position (0-based): pos0 = (row-1)*80 + (col-1)
  mov   ax,[VdCurRow]
  movzx eax,ax
  dec   eax
  imul  eax,VD_COLS
  mov   dx,[VdCurCol]
  movzx edx,dx
  dec   edx
  add   eax,edx
  mov   bx,ax
  ; Program VGA cursor high byte (index 0x0E)
  mov   dx,VGA_CRTC_INDEX
  mov   al,0x0E
  out   dx,al
  mov   dx,VGA_CRTC_DATA
  mov   al,bh
  out   dx,al
  ; Program VGA cursor low byte (index 0x0F)
  mov   dx,VGA_CRTC_INDEX
  mov   al,0x0F
  out   dx,al
  mov   dx,VGA_CRTC_DATA
  mov   al,bl
  out   dx,al
  ; Update your software cursors to match (1-based)
  mov   ax,[VdCurRow]
  movzx ecx,ax
  cmp   ecx,VD_IN_ROW
  jne   VdSetCursorIsOutput
  mov   ax,[VdCurCol]
  mov   [VdInCurCol],ax
  ret
VdSetCursorIsOutput:
  cmp   ecx,VD_OUT_MAX_ROW
  jbe   VdSetCursorOutOk
  mov   ecx,VD_OUT_MAX_ROW
VdSetCursorOutOk:
  mov   ax,cx
  mov   [VdOutCurRow],ax
  mov   ax,[VdCurCol]
  mov   [VdOutCurCol],ax
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
VdCurRow         dw 0
VdCurCol         dw 0