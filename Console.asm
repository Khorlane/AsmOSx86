; Console.asm (Cn) - no sections, no globals

CnInit:
    mov word [Cn_Work_Len], 0
    ret

CnCrLf:
    mov byte [Vd_In_Ch], 0x0D
    call VdPutChar
    mov byte [Vd_In_Ch], 0x0A
    call VdPutChar
    ret

CnReadLine:
    mov word [Cn_Work_Len], 0
    call VdInClearLine

CnReadLine_Loop:
    call KbGetKey

    mov al, [Kb_Out_HasKey]
    test al, al
    jz  CnReadLine_Loop

    mov al, [Kb_Out_Type]

    cmp al, KEY_CHAR
    je  CnReadLine_OnChar
    cmp al, KEY_BACKSPACE
    je  CnReadLine_OnBackspace
    cmp al, KEY_ENTER
    je  CnReadLine_OnEnter
    jmp CnReadLine_Loop

CnReadLine_OnChar:
    movzx ecx, word [Cn_Work_Len]
    movzx edx, word [Cn_In_Max]
    cmp ecx, edx
    jae CnReadLine_Loop

    mov esi, [Cn_In_DstPtr]
    mov al,  [Kb_Out_Char]
    mov [esi + 2 + ecx], al

    inc cx
    mov [Cn_Work_Len], cx

    mov [Vd_In_Ch], al
    call VdInPutChar
    jmp CnReadLine_Loop

CnReadLine_OnBackspace:
    movzx ecx, word [Cn_Work_Len]
    test ecx, ecx
    jz  CnReadLine_Loop

    dec cx
    mov [Cn_Work_Len], cx

    call VdInBackspaceVisual
    jmp CnReadLine_Loop

CnReadLine_OnEnter:
    mov esi, [Cn_In_DstPtr]
    mov ax,  [Cn_Work_Len]
    mov [esi], ax

    call VdInClearLine
    ret


; ----- Storage (explicit zeros; no .bss) -----

Cn_In_DstPtr     dd 0
Cn_In_Max        dw 0
Cn_Pad0          dw 0

Cn_Work_Len      dw 0
Cn_Pad1          dw 0
