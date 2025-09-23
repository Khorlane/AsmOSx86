rem Copy1.bat
@echo off
echo.
echo --------------------------------------
echo - Copy Boot2 and Kernel to Boot Disk -
echo --------------------------------------
@echo on
copy Boot2.bin  A:
copy Kernel.bin A:
@echo off
echo.
pause
if x%1 == xexit exit