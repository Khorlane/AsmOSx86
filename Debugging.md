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
  call  TimePrint                      ; HH:MM:SS (wall time)
  mov   eax,1000                       ; Delay
  call  TimerDelayMs                  ;  1 second
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