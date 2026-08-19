;**************************************************************************************************
; Config.asm
;   Global kernel configuration constants for AsmOSx86.
;
; Purpose
;   Centralize kernel-wide tunables and limits that:
;     - Are not hardware-specific
;     - Are not owned by a single subsystem
;     - Must remain consistent across multiple modules
;
; Contains
;   - Size limits (e.g. Str payload capacity)
;   - Global policy constants
;   - Compile-time kernel configuration values
;   - Shared device IDs and device type IDs
;
; Does Not Contain
;   - Hardware port/register equates (belong in their subsystem modules)
;   - Local implementation constants
;
; Notes
;   - Constants here define ABI and memory layout expectations.
;   - Changes may require coordinated updates across modules.
;**************************************************************************************************

String  CrLf,0Dh,0Ah
String  Space1," "

;--------------------------------------------------------------------------------------------------
; Device Model Constants
;--------------------------------------------------------------------------------------------------
DEV_TYPE_BLOCK       equ 1
DEV_TYPE_CHAR        equ 2
DEV_TYPE_VIDEO       equ 3

DEV_ID_VIDEO_TEXT    equ 0
DEV_ID_KEYBOARD      equ 1
DEV_ID_FLOPPY_A      equ 3
DEV_ID_HARDDISK_0    equ 4
