/* ================================================================
   GOLD4 Engine  -  DOOM-era DOS Game
   SDK:  GNU gold linker + djgpp gcc (Mode 13h VGA 320x200x256)
   Build: make doom-game
   Run:   DOSBox-X / QEMU with DOS / real i386 hardware
   ================================================================ */

#include <gold4.h>

/* ================================================================
   VGA Mode 13h: 320x200 256-color planar-free linear framebuffer
   ================================================================ */

/* default DOOM-style palette (16 entries shown; full palette loaded below) */
static void init_palette(void) {
    byte i;
    /* DOOM-style colour ramp */
    for (i = 0; i < 64; i++) {
        gold4_set_palette(i,     i * 4, 0, 0);           /* reds */
        gold4_set_palette(64+i,  0, i * 4, 0);           /* greens */
        gold4_set_palette(128+i, 0, 0, i * 4);           /* blues */
        gold4_set_palette(192+i, i * 4, i * 4, i * 4);   /* greys */
    }
    /* Special: colour 0 = black, 255 = white */
    gold4_set_palette(0,   0,   0,   0);
    gold4_set_palette(255, 255, 255, 255);
    /* Bright yellow (HUD) */
    gold4_set_palette(10, 255, 220, 0);
    /* Bright red (damage) */
    gold4_set_palette(12, 220, 0, 0);
}

/* ================================================================
   Fixed-point maths (16.16)
   ================================================================ */
static const fixed_t SIN90[91] = {
         0,   4096,   8192,  12272,  16336,  20384,  24416,
     28416,  32384,  36320,  40208,  44064,  47872,  51616,
     55296,  58912,  62448,  65888,  69248,  72512,  75680,
     78736,  81680,  84512,  87216,  89808,  92272,  94608,
     96800,  98864,100792,102576,104224,105728,107088,108304,
    109360,110256,110992,111568,111984,112240,112336,112272,
    112048,111664,111120,110416,109552,108528,107344,106000,
    104496,102832,101008, 99024, 96880, 94576, 92112, 89488,
     86704, 83760, 80656, 77392, 73968, 70384, 66640, 62736,
     58672, 54448, 50064, 45520, 40816, 35952, 30928, 25744,
     20400, 14896,  9232,  3408, -2496, -8448,-14448,-20496,
    -26592,-32736,-38928,-45168,-51456,-57792,-64128,-70464
};
static fixed_t fsin(int d) {
    d = ((d % 360) + 360) % 360;
    if (d <= 90)  return  SIN90[d];
    if (d <= 180) return  SIN90[180-d];
    if (d <= 270) return -SIN90[d-180];
    return               -SIN90[360-d];
}
static fixed_t fcos(int d) { return fsin(d + 90); }

/* ================================================================
   DOOM-style map and raycaster
   ================================================================ */
#define MAP_W  16
#define MAP_H  16
static const byte MAP[MAP_H][MAP_W] = {
    {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
    {1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1},
    {1,0,2,0,0,2,0,1,0,2,0,0,2,0,0,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,0,2,0,3,0,0,1,0,0,3,0,0,2,0,1},
    {1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,1,1,0,1,1,0,0,0,1,1,0,1,1,1,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,0,3,0,0,2,0,0,0,2,0,0,3,0,0,1},
    {1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1},
    {1,0,2,0,0,0,0,1,0,0,0,0,0,2,0,1},
    {1,0,0,0,3,0,0,0,0,0,3,0,0,0,0,1},
    {1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}
};

/* wall colour by type */
static byte wall_colour(int type, int dist, int side) {
    byte base;
    switch (type) {
        case 1: base = 192 + (64 - dist); break; /* grey stone */
        case 2: base = 64  + (64 - dist); break; /* green */
        case 3: base = 12;                break; /* red (danger) */
        default: base = 255;
    }
    if (side) base = (byte)(base / 2 + 10); /* darker for N/S faces */
    if (base < 1) base = 1;
    return base;
}

static void render(fixed_t px, fixed_t py, int angle) {
    int col;
    int half_w = VGA_WIDTH  / 2;
    int half_h = VGA_HEIGHT / 2;

    /* sky */
    gold4_fill_rect(0, 0, VGA_WIDTH, half_h, 64+30);
    /* floor */
    gold4_fill_rect(0, half_h, VGA_WIDTH, half_h, 200);

    /* raycaster */
    for (col = 0; col < VGA_WIDTH; col++) {
        int ray_ang = angle + (col - half_w) * 60 / VGA_WIDTH;
        fixed_t rdx = fcos(ray_ang);
        fixed_t rdy = fsin(ray_ang);
        fixed_t rx  = px;
        fixed_t ry  = py;
        int     hit  = 0;
        int     side = 0;
        int     wall_type = 1;
        int     step;

        for (step = 0; step < 300 && !hit; step++) {
            rx += rdx / 32;
            ry += rdy / 32;
            int mx = (int)(rx >> FRACBITS);
            int my = (int)(ry >> FRACBITS);
            if (mx < 0 || mx >= MAP_W || my < 0 || my >= MAP_H) {
                hit = 1; wall_type = 1;
            } else if (MAP[my][mx]) {
                hit = 1; wall_type = MAP[my][mx];
                side = (step & 4) ? 1 : 0; /* approximate N/S vs E/W */
            }
        }

        int dist = hit ? step : 300;
        if (dist < 1) dist = 1;

        int wall_h = VGA_HEIGHT * 6 / dist;
        if (wall_h > VGA_HEIGHT) wall_h = VGA_HEIGHT;

        int wt = half_h - wall_h / 2;
        int wb = wt + wall_h;
        int shade_dist = dist > 63 ? 63 : dist;
        byte wc = wall_colour(wall_type, shade_dist, side);

        int y;
        for (y = wt; y < wb; y++)
            if (y >= 0 && y < VGA_HEIGHT)
                gold4_put_pixel(col, y, wc);
    }
}

/* ================================================================
   Simple sprite: player weapon (gun centred, bottom-screen)
   ================================================================ */
static void draw_gun(void) {
    /* simple rectangle gun */
    gold4_fill_rect(VGA_WIDTH/2 - 6, VGA_HEIGHT - 30, 12, 20, 200);
    gold4_fill_rect(VGA_WIDTH/2 - 3, VGA_HEIGHT - 40, 6,  12, 192);
}

/* ================================================================
   HUD
   ================================================================ */
static void draw_hud(int health, int ammo, int score) {
    /* HUD bar */
    gold4_fill_rect(0, VGA_HEIGHT - 20, VGA_WIDTH, 20, 0);
    gold4_rect(0, VGA_HEIGHT - 20, VGA_WIDTH, 20, 192+60);

    /* Health bar */
    int hp_w = health * 60 / 100;
    gold4_fill_rect(4, VGA_HEIGHT - 14, hp_w, 8, 12);   /* red */
    gold4_rect(4, VGA_HEIGHT - 14, 60, 8, 192+40);

    /* Ammo bar */
    int am_w = ammo * 30 / 50;
    gold4_fill_rect(70, VGA_HEIGHT - 14, am_w, 8, 64+40); /* green */
    gold4_rect(70, VGA_HEIGHT - 14, 30, 8, 192+40);

    (void)score;
}

/* ================================================================
   Main
   ================================================================ */
void main(void) {
    gold4_set_mode13();
    init_palette();

    fixed_t px    = FIX(4);
    fixed_t py    = FIX(4);
    int     angle = 0;
    int     health = 100;
    int     ammo   = 50;
    int     score  = 0;
    int     frame  = 0;

    while (1) {
        /* keyboard input */
        byte key = gold4_getkey();
        if (key == KEY_ESC)     break;
        if (key == KEY_LT_ARROW) angle = (angle - 4 + 360) % 360;
        if (key == KEY_RT_ARROW) angle = (angle + 4) % 360;
        if (key == KEY_UP_ARROW) {
            fixed_t nx = px + fcos(angle) / 16;
            fixed_t ny = py + fsin(angle) / 16;
            int mx = (int)(nx >> FRACBITS), my = (int)(ny >> FRACBITS);
            if (mx >= 0 && mx < MAP_W && my >= 0 && my < MAP_H && !MAP[my][mx]) {
                px = nx; py = ny;
            }
        }
        if (key == KEY_DN_ARROW) {
            fixed_t nx = px - fcos(angle) / 16;
            fixed_t ny = py - fsin(angle) / 16;
            int mx = (int)(nx >> FRACBITS), my = (int)(ny >> FRACBITS);
            if (mx >= 0 && mx < MAP_W && my >= 0 && my < MAP_H && !MAP[my][mx]) {
                px = nx; py = ny;
            }
        }
        if (key == KEY_SPACE && ammo > 0) {
            ammo--;
            score += 10;
            gold4_beep(440);
        } else {
            gold4_nosound();
        }

        /* render frame */
        render(px, py, angle);
        draw_gun();
        draw_hud(health, ammo, score);

        /* auto-strafe (demo) */
        frame++;
        if (frame % 120 == 0) health = health > 10 ? health - 5 : 10;
    }

    gold4_set_text();
}
