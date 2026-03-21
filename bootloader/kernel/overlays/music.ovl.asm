; =============================================================================
; MUSIC.OVL - PC speaker music player overlay
; =============================================================================
BITS 16
ORG OVERLAY_BUF

%include "ovl_api.asm"

ovl_entry:
    call music_run
    ret

%include "../music.asm"
