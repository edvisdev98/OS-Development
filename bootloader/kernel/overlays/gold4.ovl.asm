; =============================================================================
; GOLD4.OVL - DOOM-style raycaster engine overlay
; =============================================================================
BITS 16
ORG OVERLAY_BUF

%include "ovl_api.asm"

ovl_entry:
    call gold4_run
    ret

%include "../opengl.asm"
%include "../gold4.asm"
