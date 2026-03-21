; =============================================================================
; NET.OVL - Network overlay (NE2000 + TCP/IP + HTTP)
; Loaded on demand by the kernel overlay loader into OVERLAY_BUF.
; =============================================================================
BITS 16
ORG OVERLAY_BUF

%include "ovl_api.asm"

; ---------------------------------------------------------------------------
; Entry point: called by kernel ovl_load_run  (no arguments required;
; the command argument is read directly from sh_arg at 0x0060)
; ---------------------------------------------------------------------------
ovl_entry:
    call net_run
    ret

; ---------------------------------------------------------------------------
; Module code (cross-module calls are intercepted by ovl_api.asm EQUs)
; ---------------------------------------------------------------------------
%include "../net.asm"
