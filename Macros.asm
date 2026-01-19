; Str (aka String) = [u16 len][bytes...]
; The ONLY string representation in the kernel.
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