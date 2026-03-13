# Debugging Notes
## Time and Timer
To tell if resync is occuring add the following lines:  
### Early in Kernel.asm
```
  ;-----------------------------------------
  ; Time resync test loop (temporary)
  ;-----------------------------------------
  mov   ecx,20                          ; Print time ~20 times
TimeTestLoop:
  call  TimeTmPrint                     ; HH:MM:SS (wall time)
  mov   eax,1000                        ; Delay
  call  TimerSpinDelayMs                ;  1 second
  loop  TimeTestLoop
```
### In Time.asm  
Change time re-sync seconds 
```
;TIME_RSYNC_SEC  equ 60
TIME_RSYNC_SEC  equ 5
```
Add debug string
```
; Temp for debugging start
TimeResyncStr   dw  3                   ; length = 3 bytes (2 payload + length word)
                db  '*',0Dh,0Ah         ; "*" + CrLf
; Temp for debugging end
```
If re-sync occurs, TimeSync will fire and read the CMOS clock
```
TimeSync:
  pusha
  call  TimeReadCmos                    ; updates TimeHour/Min/Sec
  ; Temp for debugging start
  mov   ebx,TimeResyncStr               ; Resync marker
  call  CnPrint                         ; Print "*" + CrLf
  ; Temp for debugging end

  xor   eax,eax
  mov   al,[TimeHour]
  ```
### Example Output
```
AsmOSx86 Console (Session 0)
A Hobbyist Operating System in x86 Assembly
*
10:39:11
10:39:12
10:39:12
10:39:13
10:39:14
10:39:15
*
10:39:16
10:39:17
10:39:18
10:39:19
10:39:20
*
10:39:21
10:39:22
10:39:23
```  

## Bochs Shutdown On Windows
### Symptom
Guest shutdown appeared to work, but PowerShell reported:
```
Write-Error: Bochs exited with code -1073741819.
```

Bochs itself logged:
```
[ACPI  ] ACPI control: soft power off
[SIM   ] quit_sim called with exit code 1
```

### Conclusion
- This was not an AsmOSx86 shutdown bug.
- The guest successfully issued the Bochs/ACPI soft-power-off request.
- The host-side `bochs.exe` process appeared to crash on exit when the display backend was left to Bochs auto-selection.

### Working Fix
Explicitly set the display backend in `AsmOSx86.bxrc`:
```
display_library: win32
```

With `display_library: win32` set explicitly, the guest shutdown path still powered off Bochs and PowerShell returned cleanly without the access-violation exit code.

### Notes
- Treat this as a Bochs-on-Windows environment/configuration issue, not an OS-kernel bug.
- If this regression returns, compare explicit `display_library` choices before changing shutdown code.
- The current config also points the Bochs log at `c:\Download\bochsout.txt`; if that path does not exist, Bochs falls back to `stderr`.
