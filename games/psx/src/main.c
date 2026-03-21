/* ================================================================
   PSYq / PSn00bSDK  -  PS1 Game Example
   SDK:  PSn00bSDK v0.24  (open-source psyq equivalent)
   CC:   mipsel-none-elf-gcc -msoft-float -nostdlib
   Build: make psx-game
   Run:   pcsx-redux / no$psx / duckstation
   ================================================================ */

#include <libps.h>

/* ---- constants ---- */
#define SCREEN_W   320
#define SCREEN_H   240
#define OT_LEN     512

/* ---- ordering table + primitive buffer ---- */
static OT_tag  ot[2][OT_LEN];
static u_char  primbuf[2][0x2000];
static u_char *primbuf_ptr;
static int     cur_buf = 0;

/* ---- GPU inline helpers ---- */
static inline void gpu_write(u_int cmd) {
    MMIO(PS1_GPU_GP0) = cmd;
}
static inline void gpu_ctrl(u_int cmd) {
    MMIO(PS1_GPU_GP1) = cmd;
}
static inline void gpu_wait_ready(void) {
    while (!(MMIO(PS1_GPU_GP1) & 0x04000000)) {}
}

/* ---- display init (NTSC 320x240) ---- */
static void display_init(void) {
    gpu_ctrl(0x00000000);  /* reset GPU */
    gpu_ctrl(0x08000001);  /* display mode: NTSC 320x240 */
    gpu_ctrl(0x06C60260);  /* horizontal display range */
    gpu_ctrl(0x07042018);  /* vertical display range */
    gpu_ctrl(0x05000000);  /* display area (VRAM x,y = 0,0) */
    gpu_ctrl(0x03000000);  /* enable display */

    /* Set draw area */
    gpu_write(0xE1000000); /* texpage */
    gpu_write(0xE3000000); /* draw top-left = (0,0) */
    gpu_write(0xE4000000 | ((SCREEN_W-1)&0x3FF) | (((SCREEN_H-1)&0x1FF)<<10));
    gpu_write(0xE5000000); /* draw offset = (0,0) */
    gpu_write(0xE6000000); /* mask bit off */
}

/* ---- draw flat-shaded triangle (GPU_Poly_F3) ---- */
static void draw_tri_f3(s_short x0,s_short y0,
                         s_short x1,s_short y1,
                         s_short x2,s_short y2,
                         u_char r, u_char g, u_char b) {
    gpu_wait_ready();
    gpu_write(0x20000000 | ((u_int)r<<16)|((u_int)g<<8)|b); /* cmd+colour */
    gpu_write(((u_int)(u_short)y0<<16)|(u_short)x0);
    gpu_write(((u_int)(u_short)y1<<16)|(u_short)x1);
    gpu_write(((u_int)(u_short)y2<<16)|(u_short)x2);
}

/* ---- draw flat rectangle ---- */
static void draw_rect(s_short x,s_short y,s_short w,s_short h,
                       u_char r,u_char g,u_char b) {
    gpu_wait_ready();
    gpu_write(0x60000000|((u_int)r<<16)|((u_int)g<<8)|b);
    gpu_write(((u_int)(u_short)y<<16)|(u_short)x);
    gpu_write(((u_int)(u_short)h<<16)|(u_short)w);
}

/* ---- clear screen ---- */
static void clear_screen(u_char r, u_char g, u_char b) {
    gpu_wait_ready();
    gpu_write(0x02000000|((u_int)r<<16)|((u_int)g<<8)|b);
    gpu_write(0x00000000);                          /* top-left (0,0) */
    gpu_write(((u_int)SCREEN_H<<16)|SCREEN_W);      /* width x height */
}

/* ---- wait for VSync (Timer 0 as vsync counter) ---- */
static void vsync(void) {
    /* busy-wait on GPU vsync bit */
    while (  (MMIO(PS1_GPU_GP1) & 0x80000000)) {}
    while (!(MMIO(PS1_GPU_GP1) & 0x80000000)) {}
}

/* ---- read pad (port 0) ---- */
static u_short pad_read(void) {
    /* Simplified direct read via JOY port */
    u_short buttons = (u_short)~(MMIO(PS1_JOY_DATA) >> 16);
    return buttons;
}

/* ---- Fixed-point sine (64 entry table, 0-90 deg, 0-255 scale) ---- */
static const u_char sinT[91] = {
      0,  4,  9, 13, 18, 22, 27, 31, 36, 40, 44, 49, 53, 57, 62, 66,
     70, 74, 79, 83, 87, 91, 95, 99,103,107,111,115,119,122,126,130,
    133,137,140,143,147,150,153,156,159,162,165,168,171,174,176,179,
    182,184,187,189,191,193,196,198,200,202,204,205,207,209,210,212,
    213,215,216,217,218,219,220,221,222,222,223,224,224,225,225,225,
    226,226,226,226,226,226,226,225,225,225,224
};

static s_short isin(int d) {
    d = ((d%360)+360)%360;
    if (d <= 90)  return  (s_short)sinT[d];
    if (d <= 180) return  (s_short)sinT[180-d];
    if (d <= 270) return -(s_short)sinT[d-180];
    return               -(s_short)sinT[360-d];
}
static s_short icos(int d) { return isin(d+90); }

/* ================================================================
   Game state
   ================================================================ */
typedef struct {
    s_short x, y;     /* player position */
    int     angle;    /* 0-359 degrees    */
    int     score;
    int     lives;
} Player;

typedef struct {
    s_short x, y;
    s_short vx, vy;
    int     active;
    int     color_r, color_g, color_b;
} Enemy;

#define MAX_ENEMIES 8
static Player player;
static Enemy  enemies[MAX_ENEMIES];
static int    frame = 0;

static void game_init(void) {
    player.x     = SCREEN_W / 2;
    player.y     = SCREEN_H - 30;
    player.angle = 0;
    player.score = 0;
    player.lives = 3;

    int i;
    for (i = 0; i < MAX_ENEMIES; i++) {
        enemies[i].active  = 1;
        enemies[i].x       = (s_short)(20 + i * 35);
        enemies[i].y       = (s_short)(20 + (i % 3) * 20);
        enemies[i].vx      = (s_short)((i & 1) ? 1 : -1);
        enemies[i].vy      = 1;
        enemies[i].color_r = (i * 40) & 0xFF;
        enemies[i].color_g = (i * 70 + 80) & 0xFF;
        enemies[i].color_b = (i * 30 + 120) & 0xFF;
    }
}

static void game_update(void) {
    u_short pad = pad_read();
    frame++;

    /* Move player */
    if (pad & PAD_LEFT)  { player.x -= 2; if (player.x < 10) player.x = 10; }
    if (pad & PAD_RIGHT) { player.x += 2; if (player.x > SCREEN_W-10) player.x = SCREEN_W-10; }
    if (pad & PAD_UP)    { player.y -= 1; if (player.y < SCREEN_H/2)  player.y = SCREEN_H/2; }
    if (pad & PAD_DOWN)  { player.y += 1; if (player.y > SCREEN_H-10) player.y = SCREEN_H-10; }

    player.angle = (player.angle + 3) % 360;

    /* Move enemies */
    int i;
    for (i = 0; i < MAX_ENEMIES; i++) {
        if (!enemies[i].active) continue;
        enemies[i].x += enemies[i].vx;
        enemies[i].y += (s_short)(isin(frame * 2 + i * 45) / 64);
        if (enemies[i].x < 10 || enemies[i].x > SCREEN_W-10)
            enemies[i].vx = -enemies[i].vx;
        if (enemies[i].y < 5) enemies[i].y = 5;
        if (enemies[i].y > SCREEN_H/2) enemies[i].y = SCREEN_H/2;
    }
}

static void game_draw(void) {
    /* Background: dark blue sky + grey floor */
    clear_screen(10, 10, 40);
    draw_rect(0, SCREEN_H*3/4, SCREEN_W, SCREEN_H/4, 40, 40, 40);

    /* Stars (animated) */
    int i;
    for (i = 0; i < 16; i++) {
        s_short sx = (s_short)((i * 79 + frame/4) % SCREEN_W);
        s_short sy = (s_short)(i * 13 % (SCREEN_H/2));
        draw_rect(sx, sy, 2, 2, 255, 255, 200);
    }

    /* Enemies: flat-shaded diamond shape */
    for (i = 0; i < MAX_ENEMIES; i++) {
        if (!enemies[i].active) continue;
        s_short ex = enemies[i].x, ey = enemies[i].y;
        u_char er = (u_char)enemies[i].color_r;
        u_char eg = (u_char)enemies[i].color_g;
        u_char eb = (u_char)enemies[i].color_b;
        draw_tri_f3(ex,     ey-10, ex+8,  ey+4,  ex-8, ey+4,  er,eg,eb);
        draw_tri_f3(ex-8,   ey+4,  ex+8,  ey+4,  ex,   ey+10, er/2,eg/2,eb/2);
    }

    /* Player ship: rotating triangle */
    s_short px = player.x, py = player.y;
    int  ang  = player.angle;
    s_short nx = (s_short)(px + icos(ang) * 12 / 256);
    s_short ny = (s_short)(py + isin(ang) * 12 / 256);
    s_short lx = (s_short)(px + icos(ang+150) * 10 / 256);
    s_short ly = (s_short)(py + isin(ang+150) * 10 / 256);
    s_short rx2 = (s_short)(px + icos(ang+210) * 10 / 256);
    s_short ry2 = (s_short)(py + isin(ang+210) * 10 / 256);
    draw_tri_f3(nx,ny, lx,ly, rx2,ry2, 50, 200, 255);

    /* HUD bar */
    draw_rect(0, 0, SCREEN_W, 10, 0, 0, 80);
}

/* ================================================================
   Main entry
   ================================================================ */
void _start(void) {
    display_init();
    game_init();

    while (1) {
        vsync();
        game_update();
        game_draw();
    }
}
