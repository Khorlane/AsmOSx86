;==============================================================================
; Video.asm (Vd) - drop-in replacement (v0.0.1)
; 32-bit NASM, single-binary (%include), no sections, no globals
;
; FIXES:
; - Do not rely on any register value across CALL boundaries.
; - VdInClearLine no longer uses AX as a loop counter across a call.
; - VdPutChar_BS ensures erase char is set immediately before erase writes.
; - Vd_ScrollOutputRegion avoids REP MOVSD to remove reliance on implicit state.
;
; Screen: Rows=25, Cols=80
; Output region (scrolls): rows 0..23
; Input line (fixed):      row 24
; Row,Col ordering everywhere (row first, then col)
;==============================================================================

VdInit:
    mov word [Vd_OutCurRow], 0
    mov word [Vd_OutCurCol], 0
    mov word [Vd_InCurCol],  0
    ret

;------------------------------------------------------------------------------
; VdPutStr
; Input (memory):
;   Vd_In_StrPtr -> Sting [u16 len][bytes...]
;------------------------------------------------------------------------------
VdPutStr:
    mov esi, [Vd_In_StrPtr]
    movzx ecx, word [esi]
    add esi, 2

VdPutStr_Next:
    test ecx, ecx
    jz  VdPutStr_Done

    mov al, [esi]
    inc esi
    dec ecx

    mov [Vd_In_Ch], al
    call VdPutChar
    jmp VdPutStr_Next

VdPutStr_Done:
    ret


;------------------------------------------------------------------------------
; VdPutChar (output region only: rows 0..23)
; Input (memory):
;   Vd_In_Ch = byte
;
; Control chars supported:
;   0x0D CR: col=0
;   0x0A LF: row++ with scroll inside output region
;   0x08 BS: move left, erase char, move left (within row)
;------------------------------------------------------------------------------
VdPutChar:
    mov al, [Vd_In_Ch]

    cmp al, 0x0D
    je  VdPutChar_CR
    cmp al, 0x0A
    je  VdPutChar_LF
    cmp al, 0x08
    je  VdPutChar_BS

    ; Clamp row (safety): never print into input line
    movzx eax, word [Vd_OutCurRow]
    cmp eax, VD_OUT_MAX_ROW
    jbe VdPutChar_RowOk
    mov word [Vd_OutCurRow], VD_OUT_MAX_ROW
VdPutChar_RowOk:

    call Vd_WriteOutCharAtCursor

    ; Reload OutCurCol after CALL (regs clobbered)
    movzx eax, word [Vd_OutCurCol]
    inc eax
    cmp eax, VD_COLS
    jb  VdPutChar_SetCol

    mov word [Vd_OutCurCol], 0
    jmp VdPutChar_LF

VdPutChar_SetCol:
    mov [Vd_OutCurCol], ax
    ret

VdPutChar_CR:
    mov word [Vd_OutCurCol], 0
    ret

VdPutChar_LF:
    movzx eax, word [Vd_OutCurRow]
    inc eax
    cmp eax, VD_OUT_MAX_ROW
    jbe VdPutChar_SetRow

    call Vd_ScrollOutputRegion
    mov word [Vd_OutCurRow], VD_OUT_MAX_ROW
    ret

VdPutChar_SetRow:
    mov [Vd_OutCurRow], ax
    ret

VdPutChar_BS:
    ; If col==0, nothing
    movzx eax, word [Vd_OutCurCol]
    test eax, eax
    jz  VdPutChar_BSDone

    ; move left one
    dec eax
    mov [Vd_OutCurCol], ax

    ; erase at current position
    mov byte [Vd_In_Ch], ' '
    call Vd_WriteOutCharAtCursor

    ; move left again if possible
    movzx eax, word [Vd_OutCurCol]
    test eax, eax
    jz  VdPutChar_BSDone
    dec eax
    mov [Vd_OutCurCol], ax

VdPutChar_BSDone:
    ret


;------------------------------------------------------------------------------
; VdInPutChar (input line only: row 24)
; Input:
;   Vd_In_Ch
; Stops at right edge (no scroll).
;------------------------------------------------------------------------------
VdInPutChar:
    movzx eax, word [Vd_InCurCol]
    cmp eax, VD_COLS
    jae VdInPutChar_Done

    call Vd_WriteInCharAtCursor

    ; reload because Vd_WriteInCharAtCursor clobbers regs
    movzx eax, word [Vd_InCurCol]
    inc eax
    mov [Vd_InCurCol], ax

VdInPutChar_Done:
    ret


;------------------------------------------------------------------------------
; VdInBackspaceVisual
; - Moves left one column (if possible)
; - Overwrites with space
; - Cursor remains at erased position
;------------------------------------------------------------------------------
VdInBackspaceVisual:
    movzx eax, word [Vd_InCurCol]
    test eax, eax
    jz  VdInBackspaceVisual_Done

    dec eax
    mov [Vd_InCurCol], ax

    mov byte [Vd_In_Ch], ' '
    call Vd_WriteInCharAtCursor

VdInBackspaceVisual_Done:
    ret


;------------------------------------------------------------------------------
; VdInClearLine
; Clears row 24 and sets InCurCol=0
;
; IMPORTANT:
; - Do not use AX/EAX as the loop counter across CALL boundaries.
;------------------------------------------------------------------------------
VdInClearLine:
    mov word [Vd_InCurCol], 0
    mov word [Vd_Work_Col], 0

VdInClearLine_Loop:
    movzx eax, word [Vd_Work_Col]
    cmp eax, VD_COLS
    jae VdInClearLine_Done

    mov [Vd_InCurCol], ax
    mov byte [Vd_In_Ch], ' '
    call Vd_WriteInCharAtCursor

    ; advance col in memory (regs clobbered)
    mov ax, [Vd_Work_Col]
    inc ax
    mov [Vd_Work_Col], ax
    jmp VdInClearLine_Loop

VdInClearLine_Done:
    mov word [Vd_InCurCol], 0
    ret


;------------------------------------------------------------------------------
; Internal helpers
;------------------------------------------------------------------------------

; Write Vd_In_Ch at (Vd_OutCurRow, Vd_OutCurCol)
Vd_WriteOutCharAtCursor:
    movzx eax, word [Vd_OutCurRow]     ; row
    imul eax, VD_COLS
    movzx edx, word [Vd_OutCurCol]     ; col
    add eax, edx
    shl eax, 1

    mov edi, VGA_TEXT_BASE
    add edi, eax
    mov al, [Vd_In_Ch]
    mov ah, VD_ATTR_DEFAULT
    mov [edi], ax
    ret


; Write Vd_In_Ch at (row=24, col=Vd_InCurCol)
Vd_WriteInCharAtCursor:
    mov eax, VD_IN_ROW                 ; row fixed
    imul eax, VD_COLS
    movzx edx, word [Vd_InCurCol]      ; col
    add eax, edx
    shl eax, 1

    mov edi, VGA_TEXT_BASE
    add edi, eax
    mov al, [Vd_In_Ch]
    mov ah, VD_ATTR_DEFAULT
    mov [edi], ax
    ret


;------------------------------------------------------------------------------
; Vd_ScrollOutputRegion
; Scroll output region rows 0..23 up by one line; clear row 23.
;
; Avoid REP MOVSD to eliminate reliance on:
; - ECX/ESI/EDI preservation assumptions
; - direction flag assumptions
;------------------------------------------------------------------------------
Vd_ScrollOutputRegion:
    ; Copy rows 1..23 -> 0..22
    ; Total bytes copied = 23 rows * 160 bytes = 3680 bytes
    mov dword [Vd_Work_Count], VD_OUT_MAX_ROW * 160

    mov esi, VGA_TEXT_BASE
    mov edi, VGA_TEXT_BASE
    add esi, 160

Vd_Scroll_CopyLoop:
    mov eax, [Vd_Work_Count]
    test eax, eax
    jz  Vd_Scroll_ClearRow

    ; copy one dword
    mov eax, [esi]
    mov [edi], eax
    add esi, 4
    add edi, 4

    ; decrement remaining bytes by 4
    mov eax, [Vd_Work_Count]
    sub eax, 4
    mov [Vd_Work_Count], eax
    jmp Vd_Scroll_CopyLoop

Vd_Scroll_ClearRow:
    ; Clear row 23 (last output row)
    mov edi, VGA_TEXT_BASE
    add edi, VD_OUT_MAX_ROW * 160

    mov word [Vd_Work_Col], 0

Vd_Scroll_ClearLoop:
    movzx eax, word [Vd_Work_Col]
    cmp eax, VD_COLS
    jae Vd_Scroll_Done

    mov ax, (VD_ATTR_DEFAULT << 8) | ' '
    mov [edi], ax
    add edi, 2

    mov ax, [Vd_Work_Col]
    inc ax
    mov [Vd_Work_Col], ax
    jmp Vd_Scroll_ClearLoop

Vd_Scroll_Done:
    ret


; ----- Storage (explicit zeros; no .bss) -----

Vd_In_Ch        db 0
Vd_Pad0         db 0,0,0
Vd_In_StrPtr    dd 0

Vd_OutCurRow    dw 0
Vd_OutCurCol    dw 0

Vd_InCurCol     dw 0
Vd_Pad1         dw 0

; Work vars (needed because regs are volatile across CALL)
Vd_Work_Col     dw 0
Vd_Work_Pad2    dw 0
Vd_Work_Count   dd 0
