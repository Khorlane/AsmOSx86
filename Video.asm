;==============================================================================
; Video.asm (Vd) - drop-in replacement (v0.0.2)
; 32-bit NASM, single-binary (%include), no sections, no globals
;
; CHANGE (minimal):
; - Replace VD_IN_ROW usage with VdCurRow so the VdIn* routines are not locked
;   to a fixed row. The Console will set VdCurRow=25 and never change it, but
;   other components may set VdCurRow as needed before calling VdIn* routines.
;
; Cursor contract is 1-based:
;   Row 1, Col 1 maps to VGA offset 0 (0xB8000 + 0 bytes)
;
; Screen: Rows=25, Cols=80
; Output region (scrolls): rows 1..24
; "Input-style" routines (VdIn*): write on row = VdCurRow (set by caller)
; Row,Col ordering everywhere (row first, then col)
;==============================================================================

[bits 32]

; ----- Video constants -----
VD_COLS         equ 80
VD_ROWS         equ 25
VD_OUT_MAX_ROW  equ 24                   ; Output region rows 1..24 (scrolls)

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
;   VdInCurCol  = 1    ; "Input-style" column set to 1 (1-based)
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
; VdInPutChar ("input-style" char write at row = VdCurRow)
; Input:
;   VdInCh
;   VdCurRow must already be set by caller to the target row (1..25)
;
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
  mov   ax,[VdInCurCol]
  mov   [VdCurCol],ax
  call  VdSetCursor
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
; - Writes on row = VdCurRow (set by caller).
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
  mov   ax,[VdInCurCol]
  mov   [VdCurCol],ax
  call  VdSetCursor
VdInBackspaceVisualDone:
  ret

;------------------------------------------------------------------------------
; VdInClearLine
; Clears the current "input-style" line at row = VdCurRow and sets InCurCol=1
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
  mov   ax,[VdInCurCol]
  mov   [VdCurCol],ax
  call  VdSetCursor
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
; Notes:
;   - Does not advance the cursor or modify VdOutCurRow/VdOutCurCol.
;   - Row 1, Col 1 maps to VGA offset 0.
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
; Writes the character in VdInCh to the VGA text buffer at:
;   row = VdCurRow, col = VdInCurCol
;
; Input (memory):
;   VdInCh      = Character to write (byte)
;   VdCurRow    = Target row (1-based, 1..25)
;   VdInCurCol  = Target column (1-based, 1..80)
;
; Notes:
;   - Does not advance the cursor or modify VdInCurCol.
;   - Row 1, Col 1 maps to VGA offset 0.
;------------------------------------------------------------------------------
VdWriteInCharAtCursor:
  mov   ax,[VdCurRow]
  movzx eax,ax
  dec   eax                               ; row0 = row-1
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
; Notes:
; - Resets output cursor positions to row=1, col=1 (1-based).
; - Resets VdInCurCol to 1 (1-based).
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
; Notes:
; - Row,Col ordering (row first, then col)
; - Row 1, Col 1 maps to VGA offset 0
; - Programs the VGA hardware cursor via ports 0x3D4/0x3D5
; - Does NOT decide "input row" vs "output row" here; it only sets hardware
;   cursor and tracks the current "input-style" column in VdInCurCol.
;------------------------------------------------------------------------------
VdSetCursor:
  mov   ax,[VdCurRow]                   ; Load desired row
  movzx eax,ax
  cmp   eax,1
  jb    VdSetCursorPanic
  cmp   eax,VD_ROWS
  ja    VdSetCursorPanic
  mov   dx,[VdCurCol]                   ; Load desired col
  movzx edx,dx
  cmp   edx,1
  jb    VdSetCursorPanic
  cmp   edx,VD_COLS
  ja    VdSetCursorPanic
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
  ; Track the active "input-style" column (1-based)
  mov   ax,[VdCurCol]
  mov   [VdInCurCol],ax
  ret
VdSetCursorPanic:
  cli
VdSetCursorPanicHang:
  hlt
  jmp   VdSetCursorPanicHang

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