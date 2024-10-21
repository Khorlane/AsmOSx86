@echo off
echo.
echo -------------------
echo - Assemble Kernel -
echo -------------------
@echo on
del Kernel.bin
del Kernel.lst
nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst
@echo off
echo.
pause
if x%1 == xexit exit