; =============================================================================
; IDE.OVL - Built-in text editor overlay
; sh_arg (0x0060) = filename to open (may be empty)
; =============================================================================
BITS 16
ORG OVERLAY_BUF

%include "ovl_api.asm"

ovl_entry:
    mov si, sh_arg          ; pass filename from shared arg buffer
    call ide_run
    call vid_clear
    ret

%include "../ide.asm"
