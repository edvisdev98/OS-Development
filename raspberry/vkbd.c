/*
 * vkbd.c — KSDOS Watch Virtual Keyboard
 * ======================================
 * Renders a touch keyboard on the bottom of the TFT framebuffer.
 * Injects keypresses via Linux uinput (no QMP socket — no exposed attack surface).
 *
 * Build:  gcc -O2 -o vkbd vkbd.c -lpthread
 * Run:    sudo ./vkbd [fb_device] [touch_device]
 *          e.g. sudo ./vkbd /dev/fb1 /dev/input/event0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <glob.h>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <linux/fb.h>
#include <linux/uinput.h>
#include <linux/input.h>

/* ============================================================
 * Configuration
 * ============================================================ */
#define KBD_HEIGHT_FRAC   0.36f   /* fraction of screen height for keyboard  */
#define HIDE_DELAY_NS     6000000000LL  /* 6 s auto-hide                      */
#define REFRESH_MS        60      /* redraw interval while keyboard is visible */

/* ============================================================
 * RGB565 color helpers
 * ============================================================ */
static inline uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b)
{
    return (uint16_t)(((r & 0xF8u) << 8) | ((g & 0xFCu) << 3) | (b >> 3));
}
#define C_BG        rgb565( 28,  28,  40)
#define C_KEY       rgb565( 55,  55,  80)
#define C_PRESSED   rgb565( 70, 140, 230)
#define C_SPECIAL   rgb565( 80,  42,  42)
#define C_BORDER    rgb565( 95,  95, 135)
#define C_TEXT      rgb565(230, 230, 255)
#define C_BAR       rgb565( 16,  16,  26)
#define C_SHIFT_ON  rgb565( 50, 130,  80)

/* ============================================================
 * Tiny 5×7 bitmap font (ASCII 32–126)
 * Each glyph: 5 bytes = 5 columns of 7 bits (bit6 = top row).
 * Public domain — matches common embedded LCD fonts.
 * ============================================================ */
#define FONT_W 5
#define FONT_H 7
static const uint8_t font5x7[][FONT_W] = {
/* 32 ' ' */ {0x00,0x00,0x00,0x00,0x00},
/* 33 '!' */ {0x00,0x00,0x5F,0x00,0x00},
/* 34 '"' */ {0x00,0x07,0x00,0x07,0x00},
/* 35 '#' */ {0x14,0x7F,0x14,0x7F,0x14},
/* 36 '$' */ {0x24,0x2A,0x7F,0x2A,0x12},
/* 37 '%' */ {0x23,0x13,0x08,0x64,0x62},
/* 38 '&' */ {0x36,0x49,0x55,0x22,0x50},
/* 39 '\''*/ {0x00,0x05,0x03,0x00,0x00},
/* 40 '(' */ {0x00,0x1C,0x22,0x41,0x00},
/* 41 ')' */ {0x00,0x41,0x22,0x1C,0x00},
/* 42 '*' */ {0x08,0x2A,0x1C,0x2A,0x08},
/* 43 '+' */ {0x08,0x08,0x3E,0x08,0x08},
/* 44 ',' */ {0x00,0x50,0x30,0x00,0x00},
/* 45 '-' */ {0x08,0x08,0x08,0x08,0x08},
/* 46 '.' */ {0x00,0x60,0x60,0x00,0x00},
/* 47 '/' */ {0x20,0x10,0x08,0x04,0x02},
/* 48 '0' */ {0x3E,0x51,0x49,0x45,0x3E},
/* 49 '1' */ {0x00,0x42,0x7F,0x40,0x00},
/* 50 '2' */ {0x42,0x61,0x51,0x49,0x46},
/* 51 '3' */ {0x21,0x41,0x45,0x4B,0x31},
/* 52 '4' */ {0x18,0x14,0x12,0x7F,0x10},
/* 53 '5' */ {0x27,0x45,0x45,0x45,0x39},
/* 54 '6' */ {0x3C,0x4A,0x49,0x49,0x30},
/* 55 '7' */ {0x01,0x71,0x09,0x05,0x03},
/* 56 '8' */ {0x36,0x49,0x49,0x49,0x36},
/* 57 '9' */ {0x06,0x49,0x49,0x29,0x1E},
/* 58 ':' */ {0x00,0x36,0x36,0x00,0x00},
/* 59 ';' */ {0x00,0x56,0x36,0x00,0x00},
/* 60 '<' */ {0x00,0x08,0x14,0x22,0x41},
/* 61 '=' */ {0x14,0x14,0x14,0x14,0x14},
/* 62 '>' */ {0x41,0x22,0x14,0x08,0x00},
/* 63 '?' */ {0x02,0x01,0x51,0x09,0x06},
/* 64 '@' */ {0x32,0x49,0x79,0x41,0x3E},
/* 65 'A' */ {0x7E,0x11,0x11,0x11,0x7E},
/* 66 'B' */ {0x7F,0x49,0x49,0x49,0x36},
/* 67 'C' */ {0x3E,0x41,0x41,0x41,0x22},
/* 68 'D' */ {0x7F,0x41,0x41,0x22,0x1C},
/* 69 'E' */ {0x7F,0x49,0x49,0x49,0x41},
/* 70 'F' */ {0x7F,0x09,0x09,0x09,0x01},
/* 71 'G' */ {0x3E,0x41,0x49,0x49,0x7A},
/* 72 'H' */ {0x7F,0x08,0x08,0x08,0x7F},
/* 73 'I' */ {0x00,0x41,0x7F,0x41,0x00},
/* 74 'J' */ {0x20,0x40,0x41,0x3F,0x01},
/* 75 'K' */ {0x7F,0x08,0x14,0x22,0x41},
/* 76 'L' */ {0x7F,0x40,0x40,0x40,0x40},
/* 77 'M' */ {0x7F,0x02,0x04,0x02,0x7F},
/* 78 'N' */ {0x7F,0x04,0x08,0x10,0x7F},
/* 79 'O' */ {0x3E,0x41,0x41,0x41,0x3E},
/* 80 'P' */ {0x7F,0x09,0x09,0x09,0x06},
/* 81 'Q' */ {0x3E,0x41,0x51,0x21,0x5E},
/* 82 'R' */ {0x7F,0x09,0x19,0x29,0x46},
/* 83 'S' */ {0x46,0x49,0x49,0x49,0x31},
/* 84 'T' */ {0x01,0x01,0x7F,0x01,0x01},
/* 85 'U' */ {0x3F,0x40,0x40,0x40,0x3F},
/* 86 'V' */ {0x1F,0x20,0x40,0x20,0x1F},
/* 87 'W' */ {0x3F,0x40,0x38,0x40,0x3F},
/* 88 'X' */ {0x63,0x14,0x08,0x14,0x63},
/* 89 'Y' */ {0x07,0x08,0x70,0x08,0x07},
/* 90 'Z' */ {0x61,0x51,0x49,0x45,0x43},
/* 91 '[' */ {0x00,0x7F,0x41,0x41,0x00},
/* 92 '\\'*/ {0x02,0x04,0x08,0x10,0x20},
/* 93 ']' */ {0x00,0x41,0x41,0x7F,0x00},
/* 94 '^' */ {0x04,0x02,0x01,0x02,0x04},
/* 95 '_' */ {0x40,0x40,0x40,0x40,0x40},
/* 96 '`' */ {0x00,0x01,0x02,0x04,0x00},
/* 97  'a'*/ {0x20,0x54,0x54,0x54,0x78},
/* 98  'b'*/ {0x7F,0x48,0x44,0x44,0x38},
/* 99  'c'*/ {0x38,0x44,0x44,0x44,0x20},
/* 100 'd'*/ {0x38,0x44,0x44,0x48,0x7F},
/* 101 'e'*/ {0x38,0x54,0x54,0x54,0x18},
/* 102 'f'*/ {0x08,0x7E,0x09,0x01,0x02},
/* 103 'g'*/ {0x0C,0x52,0x52,0x52,0x3E},
/* 104 'h'*/ {0x7F,0x08,0x04,0x04,0x78},
/* 105 'i'*/ {0x00,0x44,0x7D,0x40,0x00},
/* 106 'j'*/ {0x20,0x40,0x44,0x3D,0x00},
/* 107 'k'*/ {0x7F,0x10,0x28,0x44,0x00},
/* 108 'l'*/ {0x00,0x41,0x7F,0x40,0x00},
/* 109 'm'*/ {0x7C,0x04,0x18,0x04,0x78},
/* 110 'n'*/ {0x7C,0x08,0x04,0x04,0x78},
/* 111 'o'*/ {0x38,0x44,0x44,0x44,0x38},
/* 112 'p'*/ {0x7C,0x14,0x14,0x14,0x08},
/* 113 'q'*/ {0x08,0x14,0x14,0x18,0x7C},
/* 114 'r'*/ {0x7C,0x08,0x04,0x04,0x08},
/* 115 's'*/ {0x48,0x54,0x54,0x54,0x20},
/* 116 't'*/ {0x04,0x3F,0x44,0x40,0x20},
/* 117 'u'*/ {0x3C,0x40,0x40,0x20,0x7C},
/* 118 'v'*/ {0x1C,0x20,0x40,0x20,0x1C},
/* 119 'w'*/ {0x3C,0x40,0x30,0x40,0x3C},
/* 120 'x'*/ {0x44,0x28,0x10,0x28,0x44},
/* 121 'y'*/ {0x0C,0x50,0x50,0x50,0x3C},
/* 122 'z'*/ {0x44,0x64,0x54,0x4C,0x44},
/* 123 '{' */ {0x00,0x08,0x36,0x41,0x00},
/* 124 '|' */ {0x00,0x00,0x7F,0x00,0x00},
/* 125 '}' */ {0x00,0x41,0x36,0x08,0x00},
/* 126 '~' */ {0x0C,0x02,0x0C,0x00,0x00},
};

/* ============================================================
 * Key layout definition
 * ============================================================ */
#define MAX_ROWS  6
#define MAX_COLS  16

typedef struct {
    const char *label;      /* displayed text (UTF-8 ok for arrows)          */
    int         keycode;    /* Linux KEY_xxx                                  */
    int         width10;    /* width in tenths of a standard key unit         */
    int         is_special; /* 1 = highlighted in a different colour          */
} Key;

typedef struct {
    Key  keys[MAX_COLS];
    int  nkeys;
} Row;

/* Arrow glyphs stored as single ASCII stand-ins rendered from font */
static Row rows[MAX_ROWS];
static int nrows = 0;

static void layout_init(void)
{
    /* Row 0: ESC 1 2 3 4 5 6 7 8 9 0 - = BKSP */
    rows[0].nkeys = 14;
    Key r0[] = {
        {"ESC",KEY_ESC,14,1},     {"1",KEY_1,10,0},   {"2",KEY_2,10,0},
        {"3",KEY_3,10,0},         {"4",KEY_4,10,0},   {"5",KEY_5,10,0},
        {"6",KEY_6,10,0},         {"7",KEY_7,10,0},   {"8",KEY_8,10,0},
        {"9",KEY_9,10,0},         {"0",KEY_0,10,0},   {"-",KEY_MINUS,10,0},
        {"=",KEY_EQUAL,10,0},     {"<-",KEY_BACKSPACE,15,1},
    };
    memcpy(rows[0].keys, r0, sizeof(r0));

    /* Row 1: TAB Q W E R T Y U I O P [ ] ENT */
    rows[1].nkeys = 14;
    Key r1[] = {
        {"TAB",KEY_TAB,14,1},     {"Q",KEY_Q,10,0},   {"W",KEY_W,10,0},
        {"E",KEY_E,10,0},         {"R",KEY_R,10,0},   {"T",KEY_T,10,0},
        {"Y",KEY_Y,10,0},         {"U",KEY_U,10,0},   {"I",KEY_I,10,0},
        {"O",KEY_O,10,0},         {"P",KEY_P,10,0},   {"[",KEY_LEFTBRACE,10,0},
        {"]",KEY_RIGHTBRACE,10,0},{"RET",KEY_ENTER,15,1},
    };
    memcpy(rows[1].keys, r1, sizeof(r1));

    /* Row 2: A S D F G H J K L ; ' */
    rows[2].nkeys = 11;
    Key r2[] = {
        {"A",KEY_A,10,0}, {"S",KEY_S,10,0}, {"D",KEY_D,10,0},
        {"F",KEY_F,10,0}, {"G",KEY_G,10,0}, {"H",KEY_H,10,0},
        {"J",KEY_J,10,0}, {"K",KEY_K,10,0}, {"L",KEY_L,10,0},
        {";",KEY_SEMICOLON,10,0}, {"'",KEY_APOSTROPHE,10,0},
    };
    memcpy(rows[2].keys, r2, sizeof(r2));

    /* Row 3: Z X C V B N M , . / SHF */
    rows[3].nkeys = 11;
    Key r3[] = {
        {"Z",KEY_Z,10,0},   {"X",KEY_X,10,0},   {"C",KEY_C,10,0},
        {"V",KEY_V,10,0},   {"B",KEY_B,10,0},   {"N",KEY_N,10,0},
        {"M",KEY_M,10,0},   {",",KEY_COMMA,10,0},{".",KEY_DOT,10,0},
        {"/",KEY_SLASH,10,0},{"SHF",KEY_LEFTSHIFT,14,1},
    };
    memcpy(rows[3].keys, r3, sizeof(r3));

    /* Row 4: SPACE  LEFT UP DOWN RIGHT */
    rows[4].nkeys = 5;
    Key r4[] = {
        {"SPACE",KEY_SPACE,55,1},
        {"<",KEY_LEFT,12,1},{"^",KEY_UP,12,1},
        {"v",KEY_DOWN,12,1},{">",KEY_RIGHT,12,1},
    };
    memcpy(rows[4].keys, r4, sizeof(r4));

    nrows = 5;
}

/* ============================================================
 * Framebuffer state
 * ============================================================ */
typedef struct {
    int      fd;
    uint16_t *mem;          /* mmap'd framebuffer (RGB565 assumed)            */
    int       w, h;         /* full framebuffer dimensions                    */
    int       line_len;     /* bytes per line                                 */
    int       bpp;
    /* keyboard sub-region */
    int       kbd_y;        /* first row of keyboard area                     */
    int       kbd_h;        /* height of keyboard area in pixels              */
} FB;

static FB fb;

static int fb_open(const char *path)
{
    fb.fd = open(path, O_RDWR);
    if (fb.fd < 0) { perror("open fb"); return -1; }

    struct fb_var_screeninfo vinfo;
    struct fb_fix_screeninfo finfo;
    ioctl(fb.fd, FBIOGET_VSCREENINFO, &vinfo);
    ioctl(fb.fd, FBIOGET_FSCREENINFO, &finfo);

    fb.w        = (int)vinfo.xres;
    fb.h        = (int)vinfo.yres;
    fb.bpp      = (int)vinfo.bits_per_pixel;
    fb.line_len = (int)finfo.line_length;
    fb.kbd_h    = (int)(fb.h * KBD_HEIGHT_FRAC);
    fb.kbd_y    = fb.h - fb.kbd_h;

    size_t sz = (size_t)fb.line_len * (size_t)fb.h;
    fb.mem = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fb.fd, 0);
    if (fb.mem == MAP_FAILED) { perror("mmap fb"); return -1; }

    printf("[FB] %s  %dx%d  %dbpp  line=%d\n",
           path, fb.w, fb.h, fb.bpp, fb.line_len);
    return 0;
}

/* Write one RGB565 pixel. Only handles 16-bpp and 32-bpp. */
static inline void fb_pix(int x, int y, uint16_t col)
{
    if ((unsigned)x >= (unsigned)fb.w || (unsigned)y >= (unsigned)fb.h)
        return;
    if (fb.bpp == 16) {
        int off = y * (fb.line_len / 2) + x;
        fb.mem[off] = col;
    } else if (fb.bpp == 32) {
        uint32_t *p32 = (uint32_t *)fb.mem;
        int off = y * (fb.line_len / 4) + x;
        uint8_t r = (col >> 8) & 0xF8;
        uint8_t g = (col >> 3) & 0xFC;
        uint8_t b = (col << 3) & 0xF8;
        p32[off] = (uint32_t)(0xFF000000u | ((uint32_t)r << 16) |
                               ((uint32_t)g << 8) | b);
    }
}

static void fb_rect(int x, int y, int w, int h, uint16_t col)
{
    for (int dy = 0; dy < h; dy++)
        for (int dx = 0; dx < w; dx++)
            fb_pix(x + dx, y + dy, col);
}

static void fb_rect_border(int x, int y, int w, int h,
                            uint16_t fill, uint16_t border)
{
    fb_rect(x, y, w, h, fill);
    for (int dx = 0; dx < w; dx++) {
        fb_pix(x + dx, y,         border);
        fb_pix(x + dx, y + h - 1, border);
    }
    for (int dy = 0; dy < h; dy++) {
        fb_pix(x,         y + dy, border);
        fb_pix(x + w - 1, y + dy, border);
    }
}

/* Draw one glyph from font5x7 at (x,y). Scale = pixel size of each bit. */
static void fb_char(int x, int y, char c, uint16_t col, int scale)
{
    int idx = (unsigned char)c - 32;
    if (idx < 0 || idx >= (int)(sizeof(font5x7)/FONT_W)) return;
    const uint8_t *glyph = font5x7[idx];
    for (int col_i = 0; col_i < FONT_W; col_i++) {
        uint8_t column = glyph[col_i];
        for (int row_i = 0; row_i < FONT_H; row_i++) {
            if (column & (1 << (FONT_H - 1 - row_i))) {
                fb_rect(x + col_i * scale, y + row_i * scale,
                        scale, scale, col);
            }
        }
    }
}

static void fb_str(int x, int y, const char *s, uint16_t col, int scale)
{
    int adv = (FONT_W + 1) * scale;
    for (; *s; s++, x += adv)
        fb_char(x, y, *s, col, scale);
}

/* Measure string width in pixels */
static int fb_str_w(const char *s, int scale)
{
    int n = (int)strlen(s);
    return n ? (FONT_W * n + (n - 1)) * scale : 0;
}

/* ============================================================
 * Key geometry cache
 * ============================================================ */
typedef struct {
    int row, col;
    int x, y, w, h;
} KeyRect;

#define MAX_KEY_RECTS 128
static KeyRect krects[MAX_KEY_RECTS];
static int     nkrects = 0;

static void build_key_rects(void)
{
    nkrects = 0;
    int row_h = fb.kbd_h / nrows;
    int pad   = 2;

    for (int ri = 0; ri < nrows; ri++) {
        int total_units = 0;
        for (int ci = 0; ci < rows[ri].nkeys; ci++)
            total_units += rows[ri].keys[ci].width10;

        float unit_px = (float)fb.w / (float)total_units;
        float x = 0.0f;

        for (int ci = 0; ci < rows[ri].nkeys; ci++) {
            const Key *k = &rows[ri].keys[ci];
            int kw = (int)(k->width10 * unit_px) - pad * 2;
            int kh = row_h - pad * 2;
            int kx = (int)x + pad;
            int ky = fb.kbd_y + ri * row_h + pad;

            krects[nkrects++] = (KeyRect){ri, ci, kx, ky, kw, kh};
            x += k->width10 * unit_px;
        }
    }
}

/* ============================================================
 * Keyboard rendering
 * ============================================================ */
static int  kbd_visible    = 0;
static int  shift_on       = 0;
static int  highlight_row  = -1;
static int  highlight_col  = -1;

static void render_keyboard(void)
{
    /* Top separator bar */
    fb_rect(0, fb.kbd_y, fb.w, 3, C_BAR);

    for (int i = 0; i < nkrects; i++) {
        const KeyRect *r = &krects[i];
        const Key     *k = &rows[r->row].keys[r->col];

        uint16_t bg;
        if (r->row == highlight_row && r->col == highlight_col)
            bg = C_PRESSED;
        else if (k->keycode == KEY_LEFTSHIFT && shift_on)
            bg = C_SHIFT_ON;
        else if (k->is_special)
            bg = C_SPECIAL;
        else
            bg = C_KEY;

        fb_rect_border(r->x, r->y, r->w, r->h, bg, C_BORDER);

        /* Label — choose scale so it fits */
        const char *label = k->label;
        int scale = (r->h >= 18) ? 2 : 1;
        int tw = fb_str_w(label, scale);
        int th = FONT_H * scale;
        while (tw > r->w - 4 && scale > 1) {
            scale--;
            tw = fb_str_w(label, scale);
            th = FONT_H * scale;
        }
        int tx = r->x + (r->w - tw) / 2;
        int ty = r->y + (r->h - th) / 2;
        fb_str(tx, ty, label, C_TEXT, scale);
    }
}

static void clear_kbd_area(void)
{
    fb_rect(0, fb.kbd_y, fb.w, fb.kbd_h, C_BG);
}

/* ============================================================
 * uinput virtual keyboard
 * ============================================================ */
static int ui_fd = -1;

static int uinput_open(void)
{
    ui_fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (ui_fd < 0) { perror("open /dev/uinput"); return -1; }

    ioctl(ui_fd, UI_SET_EVBIT,  EV_KEY);
    ioctl(ui_fd, UI_SET_EVBIT,  EV_SYN);

    /* Enable every key code present in our layout */
    for (int ri = 0; ri < nrows; ri++)
        for (int ci = 0; ci < rows[ri].nkeys; ci++)
            ioctl(ui_fd, UI_SET_KEYBIT, rows[ri].keys[ci].keycode);

    /* Also enable LEFTSHIFT separately (used as modifier) */
    ioctl(ui_fd, UI_SET_KEYBIT, KEY_LEFTSHIFT);

    struct uinput_setup usetup;
    memset(&usetup, 0, sizeof(usetup));
    usetup.id.bustype = BUS_USB;
    usetup.id.vendor  = 0x4B53;  /* KS */
    usetup.id.product = 0x444F;  /* DO */
    strncpy(usetup.name, "KSDOS Virtual Keyboard", UINPUT_MAX_NAME_SIZE - 1);

    if (ioctl(ui_fd, UI_DEV_SETUP, &usetup) < 0) {
        perror("UI_DEV_SETUP"); return -1;
    }
    if (ioctl(ui_fd, UI_DEV_CREATE) < 0) {
        perror("UI_DEV_CREATE"); return -1;
    }

    /* Small delay so the kernel registers the device */
    usleep(200000);
    printf("[UINPUT] Virtual keyboard created.\n");
    return 0;
}

static void ui_send_event(int type, int code, int value)
{
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type  = type;
    ev.code  = code;
    ev.value = value;
    if (write(ui_fd, &ev, sizeof(ev)) < 0)
        perror("uinput write");
}

static void ui_press_key(int keycode, int with_shift)
{
    if (with_shift) {
        ui_send_event(EV_KEY, KEY_LEFTSHIFT, 1);
        ui_send_event(EV_SYN, SYN_REPORT, 0);
    }
    ui_send_event(EV_KEY, keycode, 1);
    ui_send_event(EV_SYN, SYN_REPORT, 0);
    usleep(30000);
    ui_send_event(EV_KEY, keycode, 0);
    ui_send_event(EV_SYN, SYN_REPORT, 0);
    if (with_shift) {
        ui_send_event(EV_KEY, KEY_LEFTSHIFT, 0);
        ui_send_event(EV_SYN, SYN_REPORT, 0);
    }
}

static void uinput_close(void)
{
    if (ui_fd >= 0) {
        ioctl(ui_fd, UI_DEV_DESTROY);
        close(ui_fd);
        ui_fd = -1;
    }
}

/* ============================================================
 * Touch device
 * ============================================================ */
static int   touch_fd    = -1;
static int   touch_x_min = 0, touch_x_max = 800;
static int   touch_y_min = 0, touch_y_max = 480;
static int   cur_raw_x   = 0, cur_raw_y   = 0;

static void touch_calibrate(int fd)
{
    struct input_absinfo abs_x, abs_y;
    if (ioctl(fd, EVIOCGABS(ABS_X), &abs_x) == 0) {
        touch_x_min = abs_x.minimum;
        touch_x_max = abs_x.maximum ? abs_x.maximum : 800;
    }
    if (ioctl(fd, EVIOCGABS(ABS_Y), &abs_y) == 0) {
        touch_y_min = abs_y.minimum;
        touch_y_max = abs_y.maximum ? abs_y.maximum : 480;
    }
    printf("[TOUCH] X: %d-%d  Y: %d-%d\n",
           touch_x_min, touch_x_max, touch_y_min, touch_y_max);
}

static int touch_map_x(int raw)
{
    int range = touch_x_max - touch_x_min;
    if (range == 0) return 0;
    return (raw - touch_x_min) * fb.w / range;
}

static int touch_map_y(int raw)
{
    int range = touch_y_max - touch_y_min;
    if (range == 0) return 0;
    return (raw - touch_y_min) * fb.h / range;
}

/* Find the first evdev device that has ABS_X and ABS_Y axes */
static int find_touch_device(char *out_path, size_t sz)
{
    glob_t g;
    if (glob("/dev/input/event*", 0, NULL, &g) != 0) return -1;
    int found = -1;
    for (size_t i = 0; i < g.gl_pathc; i++) {
        int fd = open(g.gl_pathv[i], O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;
        uint8_t bits[(ABS_CNT + 7) / 8];
        memset(bits, 0, sizeof(bits));
        ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(bits)), bits);
        int has_x = (bits[ABS_X / 8] >> (ABS_X % 8)) & 1;
        int has_y = (bits[ABS_Y / 8] >> (ABS_Y % 8)) & 1;
        if (has_x && has_y) {
            snprintf(out_path, sz, "%s", g.gl_pathv[i]);
            char name[256] = "unknown";
            ioctl(fd, EVIOCGNAME(sizeof(name)), name);
            printf("[TOUCH] Found: %s (%s)\n", g.gl_pathv[i], name);
            close(fd);
            found = 0;
            break;
        }
        close(fd);
    }
    globfree(&g);
    return found;
}

/* ============================================================
 * Key hit-test
 * ============================================================ */
static int hit_test(int fx, int fy, int *out_row, int *out_col)
{
    for (int i = 0; i < nkrects; i++) {
        const KeyRect *r = &krects[i];
        if (fx >= r->x && fx < r->x + r->w &&
            fy >= r->y && fy < r->y + r->h) {
            *out_row = r->row;
            *out_col = r->col;
            return 1;
        }
    }
    return 0;
}

/* ============================================================
 * Auto-hide timer
 * ============================================================ */
static struct timespec last_touch_ts;

static void touch_timestamp(void)
{
    clock_gettime(CLOCK_MONOTONIC, &last_touch_ts);
}

static long long elapsed_ns(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    long long s  = (long long)(now.tv_sec  - last_touch_ts.tv_sec);
    long long ns = (long long)(now.tv_nsec - last_touch_ts.tv_nsec);
    return s * 1000000000LL + ns;
}

/* ============================================================
 * Refresh thread
 * ============================================================ */
static volatile int running = 1;

static void *refresh_thread(void *arg)
{
    (void)arg;
    while (running) {
        usleep(REFRESH_MS * 1000);
        if (kbd_visible) {
            if (elapsed_ns() > HIDE_DELAY_NS) {
                /* Auto-hide */
                kbd_visible = 0;
                clear_kbd_area();
            } else {
                render_keyboard();
            }
        }
    }
    return NULL;
}

/* ============================================================
 * Touch event processing
 * ============================================================ */
static void handle_touch_down(void)
{
    int fx = touch_map_x(cur_raw_x);
    int fy = touch_map_y(cur_raw_y);

    touch_timestamp();

    if (!kbd_visible) {
        /* Show keyboard only if touch is in the keyboard zone */
        if (fy >= fb.kbd_y) {
            kbd_visible = 1;
            render_keyboard();
        }
        return;
    }

    /* Keyboard is visible — check for key press */
    int hit_row, hit_col;
    if (!hit_test(fx, fy, &hit_row, &hit_col)) return;

    const Key *k = &rows[hit_row].keys[hit_col];

    /* Shift toggle */
    if (k->keycode == KEY_LEFTSHIFT) {
        shift_on = !shift_on;
        render_keyboard();
        return;
    }

    /* Highlight pressed key, inject it, un-highlight */
    highlight_row = hit_row;
    highlight_col = hit_col;
    render_keyboard();

    ui_press_key(k->keycode, shift_on && k->keycode != KEY_LEFTSHIFT);

    if (shift_on) shift_on = 0;  /* one-shot shift */

    usleep(80000);
    highlight_row = highlight_col = -1;
    render_keyboard();
}

/* ============================================================
 * Signal handler
 * ============================================================ */
static void on_signal(int sig)
{
    (void)sig;
    running = 0;
}

/* ============================================================
 * main
 * ============================================================ */
int main(int argc, char *argv[])
{
    signal(SIGTERM, on_signal);
    signal(SIGINT,  on_signal);

    /* Parse arguments */
    const char *fb_path    = (argc > 1) ? argv[1] : "/dev/fb1";
    const char *touch_path_arg = (argc > 2) ? argv[2] : NULL;

    printf("=== KSDOS Virtual Keyboard ===\n");

    /* Init layout */
    layout_init();

    /* Open framebuffer */
    if (fb_open(fb_path) < 0) return 1;
    build_key_rects();

    /* Open uinput */
    if (uinput_open() < 0) return 1;

    /* Find touch device */
    char touch_path[256];
    if (touch_path_arg) {
        snprintf(touch_path, sizeof(touch_path), "%s", touch_path_arg);
    } else {
        if (find_touch_device(touch_path, sizeof(touch_path)) < 0) {
            fprintf(stderr, "[TOUCH] No touch device found.\n"
                            "  Specify one: %s /dev/fb1 /dev/input/eventX\n",
                    argv[0]);
            uinput_close();
            return 1;
        }
    }

    touch_fd = open(touch_path, O_RDONLY | O_NONBLOCK);
    if (touch_fd < 0) { perror("open touch"); uinput_close(); return 1; }
    touch_calibrate(touch_fd);
    printf("[TOUCH] Listening on %s\n", touch_path);

    /* Grab touch device so events don't reach the VT */
    ioctl(touch_fd, EVIOCGRAB, 1);

    /* Init auto-hide timer */
    touch_timestamp();

    /* Start refresh thread */
    pthread_t tid;
    pthread_create(&tid, NULL, refresh_thread, NULL);

    /* Main loop: read touch events */
    while (running) {
        struct input_event ev;
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(touch_fd, &fds);
        struct timeval tv = {0, REFRESH_MS * 1000};
        int r = select(touch_fd + 1, &fds, NULL, NULL, &tv);
        if (r <= 0) continue;

        if (read(touch_fd, &ev, sizeof(ev)) != sizeof(ev)) continue;

        if (ev.type == EV_ABS) {
            if (ev.code == ABS_X || ev.code == ABS_MT_POSITION_X)
                cur_raw_x = ev.value;
            else if (ev.code == ABS_Y || ev.code == ABS_MT_POSITION_Y)
                cur_raw_y = ev.value;
        } else if (ev.type == EV_KEY) {
            if (ev.code == BTN_TOUCH && ev.value == 1)
                handle_touch_down();
        }
    }

    /* Cleanup */
    running = 0;
    pthread_join(tid, NULL);
    ioctl(touch_fd, EVIOCGRAB, 0);
    close(touch_fd);
    uinput_close();
    clear_kbd_area();
    printf("[VKBD] Exited cleanly.\n");
    return 0;
}
