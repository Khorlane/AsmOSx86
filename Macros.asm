;**************************************************************************************************
; Macros.asm
;   NASM macro definitions for AsmOSx86.
;
; Purpose
;   Provide shared source-generation helpers used by the kernel modules.
;
; Contains
;   - String macro for counted kernel strings
;
; Notes
;   - Str/String storage format is [u16 length][bytes...].
;   - Counted strings are the kernel's standard string representation.
;**************************************************************************************************

%macro String 2+
%1          dw  %%EndStr-%1-2
            db  %2
%rotate 1
%rep %0-2
            db  %2
%rotate 1
%endrep
%%EndStr:
%endmacro
