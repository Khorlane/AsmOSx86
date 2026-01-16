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

LINE_MAX    equ 64                      ; maximum line input length (excluding NUL terminator)
LSTR_MAX    equ  80                     ; maximum payload length in bytes (excludes the 2-byte length)

section .data
String  CrLf,0Dh,0Ah

;==============================================================================
; Defs.inc
; Shared constants for AsmOSx86 v0.0.1
; Row,Col ordering everywhere (row first, then col)
;==============================================================================

%define KEY_NONE        0
%define KEY_CHAR        1
%define KEY_ENTER       2
%define KEY_BACKSPACE   3

%define VD_COLS         80
%define VD_ROWS         25
%define VD_OUT_MAX_ROW  23          ; output region rows: 0..23
%define VD_IN_ROW       24          ; fixed input line row

%define VGA_TEXT_BASE   0xB8000
%define VD_ATTR_DEFAULT 0x07

%define KBD_STATUS_PORT 0x64
%define KBD_DATA_PORT   0x60

section .text