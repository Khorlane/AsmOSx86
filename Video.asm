;**************************************************************************************************
; Video.asm
;   Physical VGA text output and cursor management for AsmOSx86.
;
; Purpose
;   Own kernel-side VGA text memory output, output/input cursor state,
;   scrolling, screen clearing, and hardware cursor updates.
;
; Contains
;   - VGA text-mode initialization
;   - Kernel Str output through VdPutStr/VdPutChar
;   - Output-region scrolling
;   - Input-style row editing helpers
;   - Hardware cursor programming
;
; Contracts
;   - Cursor coordinates are 1-based.
;   - Row 1, Col 1 maps to VGA offset 0 at 000B8000h.
;   - Screen size is 25 rows by 80 columns.
;   - Output region scrolls through rows 1..24.
;   - VdIn* routines write on VdCurRow, set by the caller.
;   - Row,Col ordering is used everywhere, row first and then column.
;
; Notes
;   - Video.asm owns the physical VGA text display for the kernel.
;   - Future userland display should use KcVd* logical session services.
;**************************************************************************************************

[bits 32]

; ----- Video constants -----
VD_COLS         equ 80
VD_ROWS         equ 25
VD_OUT_MAX_ROW  equ 24                   ; Output region rows 1..24 (scrolls)

VGA_TEXT_BASE   equ 0xB8000
VD_ATTR_DEFAULT equ 0x07                 ; Default attribute: Light Gray on Black
VGA_CRTC_INDEX  equ 0x3D4
VGA_CRTC_DATA   equ 0x3D5
;---------------
;- Color Codes -
;---------------
;  0 0 Black
;  1 1 Blue
;  2 2 Green
;  3 3 Cyan
;  4 4 Red
;  5 5 Magenta
;  6 6 Brown
;  7 7 White
;  8 8 Gray
;  9 9 Light Blue
; 10 A Light Green
; 11 B Light Cyan
; 12 C Light Red
; 13 D Light Magenta
; 14 E Yellow
; 15 F Bright White
; Example 3F
;         ^^
;         ||
;         ||- Foreground F = White
;         |-- Background 3 = Cyan

VidMem      equ 0B8000h                 ; Video Memory (Starting Address)
TotCol      equ 80                      ; width and height of screen
Black       equ 00h                     ; Black
Cyan        equ 03h                     ; Cyan
Purple      equ 05h                     ; Purple
White       equ 0Fh                     ; White

; ----- Video variables -----
VdInCh           db 0
VdPad0           db 0,0,0
pVdStr           dd 0
VdOutCurRow      dw 0
VdOutCurCol      dw 0
VdInCurCol       dw 0
VdPad1           dw 0
VdWorkCol        dw 0
VdWorkPad2       dw 0
VdWorkCount      dd 0
pVdWorkStr       dd 0                    ; work: current String payload pointer
VdWorkLen        dw 0                    ; work: remaining String payload bytes
VdWorkPad3       dw 0
VdCurRow         dw 0
VdCurCol         dw 0
VdColorBack      db  0                  ; Background color (00h - 0Fh)
VdColorFore      db  0                  ; Foreground color (00h - 0Fh)
VdColorAttr      db  0                  ; Combination of background and foreground color (e.g. 3Fh 3=cyan background,F=white text)

;------------------------------------------------------------------------------
; VdInit
;   Output:
;     Initializes video output cursor, input cursor, current cursor position,
;     and default color attribute.
; Notes:
;     Calls VdClear.
;     Row/Col state is 1-based.
;------------------------------------------------------------------------------
VdInit:
  mov   ax,1
  mov   [VdOutCurRow],ax
  mov   [VdOutCurCol],ax
  mov   [VdInCurCol],ax
  mov   al,VD_ATTR_DEFAULT
  mov   [VdColorAttr],al
  call  VdClear
  mov   ax,1
  mov   [VdCurRow],ax
  mov   ax,1
  mov   [VdCurCol],ax
  ret

;------------------------------------------------------------------------------
; VdPutStr
;   Input:
;     pVdStr = Str pointer [u16 len][payload]
;   Output:
;     Writes each payload byte through VdPutChar.
;   Notes:
;     Uses pVdWorkStr and VdWorkLen as memory-backed loop state because
;     VdPutChar is allowed to clobber all registers.
;------------------------------------------------------------------------------
VdPutStr:
  mov   esi,[pVdStr]
  mov   ax,[esi]
  mov   [VdWorkLen],ax
  add   esi,2
  mov   [pVdWorkStr],esi
VdPutStrNext:
  mov   ax,[VdWorkLen]
  test  ax,ax
  jz    VdPutStrDone
  dec   ax
  mov   [VdWorkLen],ax
  mov   esi,[pVdWorkStr]
  mov   al,[esi]
  inc   esi
  mov   [pVdWorkStr],esi
  mov   [VdInCh],al
  call  VdPutChar
  jmp   VdPutStrNext
VdPutStrDone:
  ret

;------------------------------------------------------------------------------
; VdPutChar
;   Input:
;     VdInCh = character/control byte to write
;   Output:
;     Updates VdOutCurRow/VdOutCurCol and writes to output region.
;   Notes:
;     Handles CR, LF, BS, printable characters, and output scrolling.
;     Output region is rows 1..24.
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
; VdInPutChar
;   Input:
;     VdInCh   = character to write
;     VdCurRow = target input row, 1..25
;   Output:
;     Writes character at VdCurRow/VdInCurCol, advances VdInCurCol,
;     updates VdCurCol, and updates the hardware cursor.
; Notes:
;     Stops at the right edge; does not scroll.
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
;   Output:
;     If VdInCurCol > 1, moves one column left, overwrites with a space,
;     and leaves the hardware cursor at the erased position.
; Notes:
;     Uses VdCurRow as the target input row.
;     VdInCurCol is 1-based and cannot move before column 1.
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
;   Output:
;     Clears the current input-style row VdCurRow and resets VdInCurCol/VdCurCol
;     to column 1.
;   Notes:
;     Uses VdWorkCol as memory-backed loop state because calls clobber registers.
;     VdInCurCol is 1-based.
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
;   Input:
;     VdInCh      = character to write
;     VdOutCurRow = output row, 1-based, 1..24
;     VdOutCurCol = output column, 1-based, 1..80
;     VdColorAttr = VGA text attribute
;   Output:
;     Writes character/attribute cell to VGA text memory.
; Notes:
;     Does not advance VdOutCurRow/VdOutCurCol.
;     Row 1, Col 1 maps to VGA offset 0.
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
  mov   ah,[VdColorAttr]                  ; Use current color attribute
  mov   [edi],ax
  ret

;------------------------------------------------------------------------------
; VdWriteInCharAtCursor
;   Input:
;     VdInCh      = character to write
;     VdCurRow    = target row, 1-based, 1..25
;     VdInCurCol  = target column, 1-based, 1..80
;     VdColorAttr = VGA text attribute
;   Output:
;     Writes character/attribute cell to VGA text memory.
; Notes:
;     Does not advance VdInCurCol.
;     Row 1, Col 1 maps to VGA offset 0.
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
  mov   ah,[VdColorAttr]                  ; Use current color attribute
  mov   [edi],ax
  ret

;------------------------------------------------------------------------------
; VdScrollOutputRegion
;   Output:
;     Scrolls output region rows 1..24 up by one line and clears row 24.
; Notes:
;     Copies rows 2..24 over rows 1..23.
;     Uses VdWorkCount and VdWorkCol as memory-backed loop state.
;     Clears row 24 using VdColorAttr.
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
  mov   al,' '
  mov   ah,[VdColorAttr]
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
;   Output:
;     Clears all 25 rows and 80 columns using spaces and VdColorAttr.
;     Resets VdCurRow/VdCurCol, VdOutCurRow/VdOutCurCol, and VdInCurCol to 1.
;     Updates the hardware cursor through VdSetCursor.
; Notes:
;     Uses registers as local loop scratch only.
;------------------------------------------------------------------------------
VdClear:
  mov   edi,VGA_TEXT_BASE
  mov   ecx,VD_COLS * VD_ROWS
VdClearLoop:
  mov   al,' '
  mov   ah,[VdColorAttr]
  mov   [edi],ax
  add   edi,2
  loop  VdClearLoop
  mov   ax,1
  mov   [VdCurRow],ax
  mov   [VdCurCol],ax
  mov   [VdOutCurRow],ax
  mov   [VdOutCurCol],ax
  mov   [VdInCurCol],ax
  call  VdSetCursor
  ret

;------------------------------------------------------------------------------
; VdSetCursor
;   Input:
;     VdCurRow = desired row, 1-based, 1..25
;     VdCurCol = desired column, 1-based, 1..80
;   Output:
;     Programs the VGA hardware text cursor.
;     VdInCurCol = VdCurCol.
; Notes:
;     Row,Col ordering is row first, then column.
;     Row 1, Col 1 maps to VGA offset 0.
;     Invalid row/column enters a halt loop.
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

;------------------------------------------------------------------------------
; VdSetColorAttr
;   Input:
;     VdColorBack = background color nibble 0..15
;     VdColorFore = foreground color nibble 0..15
;   Output:
;     VdColorAttr = combined VGA text attribute byte.
;   Notes:
;     Clears EAX and EBX before combining nibbles to avoid stale high bits.
;------------------------------------------------------------------------------
VdSetColorAttr:
  xor   eax,eax                           ; Clear full
  xor   ebx,ebx                           ;  regs (avoid garbage OR)
  mov   al,[VdColorBack]                  ; Background color (0..F)
  shl   al,4                              ;  goes in high nibble
  mov   bl,[VdColorFore]                  ; Foreground color (0..F)
  or    al,bl                             ; Combine -> attribute byte
  mov   [VdColorAttr],al                  ; Save attribute
  ret
