; =============================================================================
; music.asm - PC Speaker music engine for KSDOS
; Uses PIT channel 2 + 8255 PPI to drive the PC speaker
; =============================================================================

; PIT (8253/8254) constants
PIT_CH2_PORT    equ 0x42
PIT_CMD_PORT    equ 0x43
PIT_CMD_CH2     equ 0xB6    ; ch2, LSB+MSB, square wave, binary

; Speaker port (System Control Port B)
SPK_PORT        equ 0x61
SPK_ON          equ 0x03    ; bits 0+1 enable speaker + timer gate
SPK_OFF_MASK    equ 0xFC    ; mask to clear speaker bits

; Note divisors: PIT clock (1193182 Hz) / frequency
NOTE_REST       equ 0
NOTE_C4         equ 4560
NOTE_CS4        equ 4302
NOTE_D4         equ 4063
NOTE_DS4        equ 3834
NOTE_E4         equ 3621
NOTE_F4         equ 3417
NOTE_FS4        equ 3226
NOTE_G4         equ 3045
NOTE_GS4        equ 2875
NOTE_A4         equ 2712
NOTE_AS4        equ 2562
NOTE_B4         equ 2416
NOTE_C5         equ 2280
NOTE_CS5        equ 2153
NOTE_D5         equ 2031
NOTE_DS5        equ 1917
NOTE_E5         equ 1810
NOTE_F5         equ 1709
NOTE_FS5        equ 1613
NOTE_G5         equ 1522
NOTE_GS5        equ 1437
NOTE_A5         equ 1356
NOTE_AS5        equ 1281
NOTE_B5         equ 1208
NOTE_C6         equ 1140

SONG_END        equ 0xFFFF

; Duration constants in milliseconds
DUR_WHOLE       equ 2000
DUR_HALF        equ 1000
DUR_DOT_H       equ 1500
DUR_QRTR        equ 500
DUR_DOT_Q       equ 750
DUR_EIGHT       equ 250
DUR_DOT_E       equ 375
DUR_SIXTN       equ 125

; ==========================================================
; Song tables: word pairs (note_divisor, duration_ms)
; terminated by SONG_END
; ==========================================================

; ----- Tetris Theme (Korobeiniki) -----
song_tetris:
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_B4,  DUR_EIGHT
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_D5,  DUR_QRTR
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_B4,  DUR_EIGHT
    dw NOTE_A4,  DUR_QRTR
    dw NOTE_A4,  DUR_EIGHT
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_D5,  DUR_EIGHT
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_B4,  DUR_DOT_Q
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_D5,  DUR_QRTR
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_C5,  DUR_QRTR
    dw NOTE_A4,  DUR_QRTR
    dw NOTE_A4,  DUR_HALF
    dw NOTE_REST, DUR_EIGHT
    dw NOTE_D5,  DUR_DOT_Q
    dw NOTE_F5,  DUR_EIGHT
    dw NOTE_A5,  DUR_QRTR
    dw NOTE_G5,  DUR_EIGHT
    dw NOTE_F5,  DUR_EIGHT
    dw NOTE_E5,  DUR_DOT_Q
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_D5,  DUR_EIGHT
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_B4,  DUR_QRTR
    dw NOTE_B4,  DUR_EIGHT
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_D5,  DUR_QRTR
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_C5,  DUR_QRTR
    dw NOTE_A4,  DUR_QRTR
    dw NOTE_A4,  DUR_QRTR
    dw SONG_END, 0

; ----- Super Mario Bros Theme (simplified) -----
song_mario:
    dw NOTE_E5,  DUR_EIGHT
    dw NOTE_E5,  DUR_EIGHT
    dw NOTE_REST, DUR_EIGHT
    dw NOTE_E5,  DUR_EIGHT
    dw NOTE_REST, DUR_EIGHT
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_G5,  DUR_QRTR
    dw NOTE_REST, DUR_QRTR
    dw NOTE_G4,  DUR_QRTR
    dw NOTE_REST, DUR_QRTR
    dw NOTE_C5,  DUR_DOT_Q
    dw NOTE_G4,  DUR_EIGHT
    dw NOTE_REST, DUR_QRTR
    dw NOTE_E4,  DUR_DOT_Q
    dw NOTE_A4,  DUR_EIGHT
    dw NOTE_B4,  DUR_EIGHT
    dw NOTE_AS4, DUR_EIGHT
    dw NOTE_A4,  DUR_QRTR
    dw NOTE_G4,  DUR_EIGHT
    dw NOTE_E5,  DUR_EIGHT
    dw NOTE_G5,  DUR_EIGHT
    dw NOTE_A5,  DUR_QRTR
    dw NOTE_F5,  DUR_EIGHT
    dw NOTE_G5,  DUR_EIGHT
    dw NOTE_REST, DUR_EIGHT
    dw NOTE_E5,  DUR_EIGHT
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_D5,  DUR_EIGHT
    dw NOTE_B4,  DUR_DOT_Q
    dw SONG_END, 0

; ----- Imperial March (Star Wars) -----
song_imperial:
    dw NOTE_A4,  DUR_QRTR
    dw NOTE_A4,  DUR_QRTR
    dw NOTE_A4,  DUR_QRTR
    dw NOTE_F4,  DUR_DOT_E
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_A4,  DUR_QRTR
    dw NOTE_F4,  DUR_DOT_E
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_A4,  DUR_HALF
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_F5,  DUR_DOT_E
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_GS4, DUR_QRTR
    dw NOTE_F4,  DUR_DOT_E
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_A4,  DUR_HALF
    dw NOTE_A5,  DUR_QRTR
    dw NOTE_A4,  DUR_DOT_E
    dw NOTE_A4,  DUR_SIXTN
    dw NOTE_A5,  DUR_QRTR
    dw NOTE_GS5, DUR_DOT_E
    dw NOTE_G5,  DUR_SIXTN
    dw NOTE_FS5, DUR_SIXTN
    dw NOTE_F5,  DUR_SIXTN
    dw NOTE_FS5, DUR_EIGHT
    dw NOTE_REST, DUR_EIGHT
    dw NOTE_AS4, DUR_EIGHT
    dw NOTE_DS5, DUR_QRTR
    dw NOTE_D5,  DUR_DOT_E
    dw NOTE_CS5, DUR_SIXTN
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_B4,  DUR_SIXTN
    dw NOTE_C5,  DUR_EIGHT
    dw NOTE_REST, DUR_EIGHT
    dw NOTE_F4,  DUR_EIGHT
    dw NOTE_GS4, DUR_QRTR
    dw NOTE_F4,  DUR_DOT_E
    dw NOTE_A4,  DUR_SIXTN
    dw NOTE_C5,  DUR_QRTR
    dw NOTE_A4,  DUR_DOT_E
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_E5,  DUR_HALF
    dw SONG_END, 0

; ----- Happy Birthday -----
song_birthday:
    dw NOTE_C5,  DUR_DOT_E
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_D5,  DUR_QRTR
    dw NOTE_C5,  DUR_QRTR
    dw NOTE_F5,  DUR_QRTR
    dw NOTE_E5,  DUR_HALF
    dw NOTE_C5,  DUR_DOT_E
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_D5,  DUR_QRTR
    dw NOTE_C5,  DUR_QRTR
    dw NOTE_G5,  DUR_QRTR
    dw NOTE_F5,  DUR_HALF
    dw NOTE_C5,  DUR_DOT_E
    dw NOTE_C5,  DUR_SIXTN
    dw NOTE_C6,  DUR_QRTR
    dw NOTE_A5,  DUR_QRTR
    dw NOTE_F5,  DUR_QRTR
    dw NOTE_E5,  DUR_QRTR
    dw NOTE_D5,  DUR_QRTR
    dw NOTE_AS5, DUR_DOT_E
    dw NOTE_AS5, DUR_SIXTN
    dw NOTE_A5,  DUR_QRTR
    dw NOTE_F5,  DUR_QRTR
    dw NOTE_G5,  DUR_QRTR
    dw NOTE_F5,  DUR_HALF
    dw SONG_END, 0

; Song table (name_ptr, data_ptr pairs)
music_table:
    dw str_song1, song_tetris
    dw str_song2, song_mario
    dw str_song3, song_imperial
    dw str_song4, song_birthday
    dw 0, 0

str_song1:  db "1. Tetris (Korobeiniki)", 0
str_song2:  db "2. Super Mario Bros Theme", 0
str_song3:  db "3. Imperial March (Star Wars)", 0
str_song4:  db "4. Happy Birthday", 0
str_music_hdr:  db "KSDOS Music Player - PC Speaker", 0
str_music_sel:  db "Select song (1-4, Q=quit): ", 0
str_music_play: db "Playing... Press any key to stop.", 0
str_music_done: db "Done.", 0
str_music_stop: db " [stopped]", 0

; ==========================================================
; spk_set_freq: set PC speaker to frequency
;   AX = PIT divisor (0 = silence/off)
; ==========================================================
spk_set_freq:
    push ax
    push dx
    test ax, ax
    jz .silence
    ; Program PIT channel 2
    push ax
    mov al, PIT_CMD_CH2
    out PIT_CMD_PORT, al
    pop ax
    out PIT_CH2_PORT, al    ; low byte
    mov al, ah
    out PIT_CH2_PORT, al    ; high byte
    ; Enable speaker gate
    in al, SPK_PORT
    or al, SPK_ON
    out SPK_PORT, al
    jmp .done
.silence:
    in al, SPK_PORT
    and al, SPK_OFF_MASK
    out SPK_PORT, al
.done:
    pop dx
    pop ax
    ret

; ==========================================================
; spk_silence: turn off PC speaker
; ==========================================================
spk_silence:
    push ax
    in al, SPK_PORT
    and al, SPK_OFF_MASK
    out SPK_PORT, al
    pop ax
    ret

; ==========================================================
; spk_delay_ms: delay BX milliseconds using BIOS INT 15h
; ==========================================================
spk_delay_ms:
    push ax
    push bx
    push cx
    push dx
    ; BX ms → microseconds (BX * 1000)
    ; 1000 = 0x3E8
    xor dx, dx
    mov ax, bx
    mov cx, 1000
    mul cx              ; DX:AX = microseconds
    mov cx, dx          ; high word
    mov dx, ax          ; low word
    mov ah, 0x86
    int 0x15
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================
; beep_boot: play a short ascending startup beep
; ==========================================================
beep_boot:
    push ax
    push bx
    ; Three ascending tones
    mov ax, NOTE_C5
    call spk_set_freq
    mov bx, 80
    call spk_delay_ms
    mov ax, NOTE_E5
    call spk_set_freq
    mov bx, 80
    call spk_delay_ms
    mov ax, NOTE_G5
    call spk_set_freq
    mov bx, 120
    call spk_delay_ms
    call spk_silence
    pop bx
    pop ax
    ret

; ==========================================================
; music_play_song: play song at DS:SI (word pairs)
;   Checks kbd between notes - returns if key pressed
; ==========================================================
_music_stop: db 0   ; set to 1 when key pressed to stop

music_play_song:
    push ax
    push bx
    push si
    mov byte [_music_stop], 0
.note_loop:
    ; Load note divisor
    mov ax, [si]
    cmp ax, SONG_END
    je .done
    add si, 2
    ; Load duration
    mov bx, [si]
    add si, 2
    ; Play the note
    call spk_set_freq
    ; Check keyboard quickly between notes
    ; Delay one 'gap' before full duration (note separation)
    push bx
    mov bx, 20          ; 20ms gap (silence between notes)
    call spk_silence
    call spk_delay_ms
    ; Re-enable note
    pop bx
    mov ax, [si-4]      ; re-read divisor
    call spk_set_freq
    ; Delay for note duration (minus the gap)
    sub bx, 20
    jle .skip_delay
    call spk_delay_ms
.skip_delay:
    ; Check if a key was pressed (non-blocking)
    mov ah, 0x01
    int 0x16
    jz .note_loop
    ; Key pressed - consume it and stop
    mov ah, 0x00
    int 0x16
    mov byte [_music_stop], 1
.done:
    call spk_silence
    pop si
    pop bx
    pop ax
    ret

; ==========================================================
; music_run: MUSIC command handler
; ==========================================================
music_run:
    push ax
    push bx
    push si
    ; Print header
    mov si, str_music_hdr
    call vid_println
    ; List songs: table entries are (name_ptr:word, data_ptr:word)
    mov bx, music_table
.list_loop:
    cmp word [bx], 0
    je .list_done
    mov si, [bx]        ; name ptr
    call vid_println
    add bx, 4
    jmp .list_loop
.list_done:
    call vid_nl
    mov si, str_music_sel
    call vid_print
    ; Get key
    call kbd_getkey
    call vid_nl
    ; Q or q = quit
    cmp al, 'q'
    je .quit
    cmp al, 'Q'
    je .quit
    ; Convert '1'-'4' to 0-based index
    cmp al, '1'
    jb .quit
    cmp al, '4'
    ja .quit
    sub al, '1'         ; 0-based index (0..3)
    xor ah, ah
    shl ax, 2           ; AX *= 4 (each entry = 4 bytes)
    ; BX = pointer to table entry
    mov bx, ax
    add bx, music_table
    ; Print song name
    push bx
    mov si, [bx]        ; name ptr
    call vid_print
    mov al, ' '
    call vid_putchar
    pop bx
    ; Print "Playing..." message
    push bx
    mov si, str_music_play
    call vid_println
    pop bx
    ; SI = song data pointer
    mov si, [bx+2]      ; data ptr
    ; Play the song
    call music_play_song
    ; Report result
    cmp byte [_music_stop], 1
    je .stopped
    mov si, str_music_done
    call vid_println
    jmp .out
.stopped:
    mov si, str_music_stop
    call vid_println
    jmp .out
.quit:
.out:
    pop si
    pop bx
    pop ax
    ret
