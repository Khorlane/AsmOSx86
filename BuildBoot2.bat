@echo off
echo.
echo ------------------
echo - Assemble Boot2 -
echo ------------------
@echo on
del Boot2.bin
del Boot2.lst
nasm -f bin Boot2.asm -o Boot2.bin -l Boot2.lst
@echo off
echo.
pause
if x%1 == xexit exit