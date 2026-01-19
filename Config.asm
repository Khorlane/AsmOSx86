;**************************************************************************************************
; Config.asm
;   Global kernel configuration constants
;
; Purpose
;   Centralize kernel-wide tunables and limits that:
;     - Are not hardware-specific
;     - Are not owned by a single subsystem
;     - Must remain consistent across multiple modules
;
; Contains
;   - Size limits (e.g. LStr payload capacity)
;   - Global policy constants
;   - Compile-time kernel configuration values
;
; Does NOT contain
;   - Hardware-specific equates (belong in their subsystem modules)
;   - Local implementation constants
;
; Notes (LOCKED-IN)
;   - Constants here define ABI and memory layout expectations.
;   - Changes may require coordinated updates across modules.
;**************************************************************************************************

String  CrLf,0Dh,0Ah
String  Space1," "