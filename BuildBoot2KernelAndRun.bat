rem BuildBoot2KernelAndRun.bat
@echo off
rem ------------------
rem - Assemble Boot2 -
rem -----------------
call BuildBoot2.bat noexit
@echo off
rem -------------------
rem - Assemble Kernel -
rem -------------------
call BuildKernel.bat noexit
@echo off
echo.
rem --------------------------------------
rem - Copy Boot2 and Kernel to Boot Disk -
rem --------------------------------------
"C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe" -conf C:\Projects\AsmOSx86\DosBox1.txt
cls
@echo off
echo.
echo --------------------------
echo - Boot Disk prep is done -
echo --------------------------
echo.
pause
cls
echo.
echo --------------------------------
echo - Boot up AsmOSx86 using Bochs -
echo --------------------------------
pause
@echo on
"C:\Program Files\Bochs-2.8\bochs.exe" -q -f C:\Projects\AsmOSx86\AsmOSx86.bxrc