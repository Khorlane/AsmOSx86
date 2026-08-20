;**************************************************************************************************
; Config.asm
;   Global kernel configuration constants for AsmOSx86.
;
; Purpose
;   Provide common kernel definitions and small shared tables that:
;     - Are not owned by a single subsystem
;     - Must remain consistent across multiple modules
;     - Describe kernel-wide contracts such as device identity
;
; Contains
;   - Size limits (e.g. Str payload capacity)
;   - Global policy constants
;   - Compile-time kernel configuration values
;   - Shared device IDs, device type IDs, and the static device registry
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
DEV_TYPE_BLOCK          equ 1
DEV_TYPE_CHAR           equ 2
DEV_TYPE_VIDEO          equ 3

DEV_STATUS_OK           equ 0
DEV_STATUS_BAD_DEVICE   equ 1
DEV_STATUS_IO_ERROR     equ 2
DEV_STATUS_NOT_PRESENT  equ 3

DEV_ID_VIDEO_TEXT       equ 0
DEV_ID_KEYBOARD         equ 1
DEV_ID_FLOPPY_A         equ 3
DEV_ID_HARDDISK_0       equ 4

DEV_SECTOR_SIZE_NONE    equ 0
DEV_SECTOR_SIZE_512     equ 512
DEV_FLOPPY_A_SECTORS    equ 2880

DEV_RECORD_ID           equ 0
DEV_RECORD_TYPE         equ 4
DEV_RECORD_STATUS       equ 8
DEV_RECORD_SECTOR_SIZE  equ 12
DEV_RECORD_SECTOR_COUNT equ 16
DEV_RECORD_READ         equ 20
DEV_RECORD_WRITE        equ 24
DEV_RECORD_CONTROL      equ 28
DEV_RECORD_SIZE         equ 32

DEV_REGISTRY_COUNT      equ 4

;--------------------------------------------------------------------------------------------------
; Device Registry
;--------------------------------------------------------------------------------------------------
DevRegistry:
  dd DEV_ID_VIDEO_TEXT
  dd DEV_TYPE_VIDEO
  dd DEV_STATUS_OK
  dd DEV_SECTOR_SIZE_NONE
  dd 0
  dd 0
  dd 0
  dd 0
DevRegistryKeyboard:
  dd DEV_ID_KEYBOARD
  dd DEV_TYPE_CHAR
  dd DEV_STATUS_OK
  dd DEV_SECTOR_SIZE_NONE
  dd 0
  dd 0
  dd 0
  dd 0
DevRegistryFloppyA:
  dd DEV_ID_FLOPPY_A
  dd DEV_TYPE_BLOCK
  dd DEV_STATUS_OK
  dd DEV_SECTOR_SIZE_512
  dd DEV_FLOPPY_A_SECTORS
  dd 0
  dd 0
  dd 0
DevRegistryHardDisk0:
  dd DEV_ID_HARDDISK_0
  dd DEV_TYPE_BLOCK
  dd DEV_STATUS_NOT_PRESENT
  dd DEV_SECTOR_SIZE_512
  dd 0
  dd 0
  dd 0
  dd 0
