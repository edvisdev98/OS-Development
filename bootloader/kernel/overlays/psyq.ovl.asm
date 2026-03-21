; =============================================================================
; PSYQ.OVL - PSYq PlayStation-style ship engine overlay
; =============================================================================
BITS 16
ORG OVERLAY_BUF

%include "ovl_api.asm"

ovl_entry:
    call psyq_ship_demo
    ret

%include "../opengl.asm"
%include "../psyq.asm"
