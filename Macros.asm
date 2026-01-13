; String Macro - Define a string with length prefix
%macro String 2+
%1          dw  %%EndStr-%1
            db  %2
%rotate 1
%rep %0-2
            db  %2
%rotate 1
%endrep
%%EndStr:
%endmacro