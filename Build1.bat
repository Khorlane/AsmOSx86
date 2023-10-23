@echo off
echo.
echo ------------------
echo - Assemble Boot1 -
echo ------------------
@echo on
del Boot1.bin
del Boot1.lst
"C:\Program Files\NASM\nasm" -f bin Boot1.asm -o Boot1.bin -l Boot1.lst
@echo off
echo.
pause
if x%1 == xexit exit