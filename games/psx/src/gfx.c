/* PSYq gfx.c - GPU helper library for PS1
   GPU primitives, ordering table management, double buffering */

#include <libps.h>

/* ---- flat-shaded quad (2 triangles) ---- */
void gfx_fill_quad(s_short x, s_short y, s_short w, s_short h,
                   u_char r, u_char g, u_char b) {
    while (!(MMIO(PS1_GPU_GP1) & 0x04000000)) {}
    /* Top-left triangle */
    MMIO(PS1_GPU_GP0) = 0x20000000|((u_int)r<<16)|((u_int)g<<8)|b;
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)y    <<16)|(u_short)x;
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)y    <<16)|(u_short)(x+w);
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)(y+h)<<16)|(u_short)x;
    /* Bottom-right triangle */
    MMIO(PS1_GPU_GP0) = 0x20000000|((u_int)r<<16)|((u_int)g<<8)|b;
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)y    <<16)|(u_short)(x+w);
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)(y+h)<<16)|(u_short)(x+w);
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)(y+h)<<16)|(u_short)x;
}

/* ---- horizontal line ---- */
void gfx_hline(s_short x0, s_short x1, s_short y,
               u_char r, u_char g, u_char b) {
    while (!(MMIO(PS1_GPU_GP1) & 0x04000000)) {}
    MMIO(PS1_GPU_GP0) = 0x40000000|((u_int)r<<16)|((u_int)g<<8)|b;
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)y<<16)|(u_short)x0;
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)y<<16)|(u_short)x1;
    MMIO(PS1_GPU_GP0) = 0x55555555; /* terminate polyline */
}

/* ---- gouraud triangle ---- */
void gfx_tri_g3(s_short x0,s_short y0, u_char r0,u_char g0,u_char b0,
                s_short x1,s_short y1, u_char r1,u_char g1,u_char b1,
                s_short x2,s_short y2, u_char r2,u_char g2,u_char b2) {
    while (!(MMIO(PS1_GPU_GP1) & 0x04000000)) {}
    MMIO(PS1_GPU_GP0) = 0x30000000|((u_int)r0<<16)|((u_int)g0<<8)|b0;
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)y0<<16)|(u_short)x0;
    MMIO(PS1_GPU_GP0) = ((u_int)r1<<16)|((u_int)g1<<8)|b1;
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)y1<<16)|(u_short)x1;
    MMIO(PS1_GPU_GP0) = ((u_int)r2<<16)|((u_int)g2<<8)|b2;
    MMIO(PS1_GPU_GP0) = ((u_int)(u_short)y2<<16)|(u_short)x2;
}
