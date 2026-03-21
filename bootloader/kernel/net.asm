; =============================================================================
; net.asm - KSDOS Real Network Stack
; NE2000 ISA (port 0x300) + DHCP + ARP + TCP + HTTP
; Uses QEMU user-mode networking (slirp) for real internet access
; NOTE: All I/O to ports > 255 MUST use MOV DX, port / IN-OUT DX
; =============================================================================

; NE2000 register offsets from NE_BASE (always access via DX)
NE_BASE         equ 0x300
NE_R_CR         equ 0x00    ; Command Register
NE_R_PSTART     equ 0x01    ; Page Start
NE_R_PSTOP      equ 0x02    ; Page Stop
NE_R_BNRY       equ 0x03    ; Boundary Pointer
NE_R_TPSR       equ 0x04    ; TX Page Start
NE_R_TBCR0      equ 0x05    ; TX Byte Count lo
NE_R_TBCR1      equ 0x06    ; TX Byte Count hi
NE_R_ISR        equ 0x07    ; Interrupt Status
NE_R_RSAR0      equ 0x08    ; Remote Start Address lo
NE_R_RSAR1      equ 0x09    ; Remote Start Address hi
NE_R_RBCR0      equ 0x0A    ; Remote Byte Count lo
NE_R_RBCR1      equ 0x0B    ; Remote Byte Count hi
NE_R_RCR        equ 0x0C    ; Receive Config
NE_R_TCR        equ 0x0D    ; Transmit Config
NE_R_DCR        equ 0x0E    ; Data Config
NE_R_IMR        equ 0x0F    ; Interrupt Mask
NE_R_DATA       equ 0x10    ; Remote DMA data port
NE_R_CURR       equ 0x07    ; Current page (Page 1 only)
NE_R_RESET      equ 0x1F    ; Reset port

; NE2000 memory page layout
NE_TX_PAGE      equ 0x40    ; TX buffer at page 0x40
NE_RX_START     equ 0x46    ; RX ring start page
NE_RX_STOP      equ 0x80    ; RX ring stop page

; Helper macros for NE2000 port I/O
%macro NE_OUT 2             ; NE_OUT register_offset, value
    mov dx, NE_BASE + %1
    mov al, %2
    out dx, al
%endmacro

%macro NE_IN 1              ; NE_IN register_offset  → AL
    mov dx, NE_BASE + %1
    in al, dx
%endmacro

%macro NE_OUT_REG 2         ; NE_OUT_REG register_offset, al_already_set
    mov dx, NE_BASE + %1
    out dx, al
%endmacro

; Network packet buffers live in segment 0x3000 (physical 0x30000 = 192KB)
NET_SEG         equ 0x3000
NET_TX_OFF      equ 0x0000  ; TX packet buffer (1600 bytes)
NET_RX_OFF      equ 0x0640  ; RX packet buffer (1600 bytes)

; ==========================================================================
; Network state (kernel segment DS=0x1000)
; ==========================================================================
net_our_mac:    times 6 db 0
net_our_ip:     dd 0
net_gw_ip:      db 10, 0, 2, 2      ; QEMU slirp gateway
net_gw_mac:     times 6 db 0
net_dns_ip:     db 10, 0, 2, 3      ; QEMU slirp DNS
net_dst_ip:     dd 0
net_ip_id:      dw 0x1234
net_tcp_seq:    dd 0x00C0FFEE
net_tcp_ack:    dd 0
net_tcp_sport:  dw 0xC12A           ; source port 49450
net_dhcp_xid:   dd 0xBEEFCAFE
net_gw_arp_ok:  db 0
net_dhcp_ok:    db 0
net_rx_len:     dw 0
net_rx_next:    db 0
net_prom:       times 32 db 0
net_arg_buf:    times 128 db 0
net_tcp_port:   dw 80
_net_music_sav: db 0                ; spare

; ==========================================================================
; ne_init: reset and initialize NE2000, read MAC address
; ==========================================================================
ne_init:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; Hardware reset
    NE_IN NE_R_RESET
    NE_OUT_REG NE_R_RESET, 0
    ; Wait for RST bit in ISR
    mov cx, 0x4000
.rst_loop:
    NE_IN NE_R_ISR
    test al, 0x80
    jnz .rst_ok
    loop .rst_loop
.rst_ok:
    ; Clear all ISR bits
    NE_OUT NE_R_ISR, 0xFF
    ; CR: page 0, stop, no DMA
    NE_OUT NE_R_CR, 0x21
    ; DCR: 16-bit, burst mode, FIFO threshold 8
    NE_OUT NE_R_DCR, 0x49
    ; Clear remote byte count
    NE_OUT NE_R_RBCR0, 0x00
    NE_OUT NE_R_RBCR1, 0x00
    ; RCR: monitor mode
    NE_OUT NE_R_RCR, 0x20
    ; TCR: loopback
    NE_OUT NE_R_TCR, 0x02
    ; TX page
    NE_OUT NE_R_TPSR, NE_TX_PAGE
    ; RX ring
    NE_OUT NE_R_PSTART, NE_RX_START
    NE_OUT NE_R_PSTOP,  NE_RX_STOP
    NE_OUT NE_R_BNRY,   NE_RX_START

    ; Switch to page 1 to set CURR and MAR
    NE_OUT NE_R_CR, 0x61
    NE_OUT NE_R_CURR, NE_RX_START + 1
    ; Clear multicast (MAR0-MAR7 = ports 0x08-0x0F in page 1)
    xor al, al
    mov dx, NE_BASE + 0x08
    mov cx, 8
.mar:
    out dx, al
    inc dx
    loop .mar
    ; Back to page 0
    NE_OUT NE_R_CR, 0x21

    ; Read MAC from PROM via remote DMA (32 bytes from address 0)
    NE_OUT NE_R_RBCR0, 32
    NE_OUT NE_R_RBCR1, 0
    NE_OUT NE_R_RSAR0, 0
    NE_OUT NE_R_RSAR1, 0
    ; Remote read
    NE_OUT NE_R_CR, 0x0A
    ; Read 16 words from data port
    mov ax, ds
    mov es, ax
    mov di, net_prom
    mov cx, 16
    mov dx, NE_BASE + NE_R_DATA
.prom_rd:
    in ax, dx
    stosw
    loop .prom_rd
    ; Wait for RDC
.rdc1:
    NE_IN NE_R_ISR
    test al, 0x40
    jz .rdc1
    NE_OUT NE_R_ISR, 0x40

    ; Extract MAC: even bytes of PROM (0,2,4,6,8,10)
    mov si, net_prom
    mov di, net_our_mac
    mov al, [si+0];  mov [di+0], al
    mov [di+0], al
    mov al, [si+2];  mov [di+1], al
    mov [di+1], al
    mov al, [si+4];  mov [di+2], al
    mov [di+2], al
    mov al, [si+6];  mov [di+3], al
    mov [di+3], al
    mov al, [si+8];  mov [di+4], al
    mov [di+4], al
    mov al, [si+10]; mov [di+5], al
    mov [di+5], al

    ; Set MAC in page 1 PAR0-PAR5 registers
    NE_OUT NE_R_CR, 0x61
    mov si, net_our_mac
    mov dx, NE_BASE + NE_R_PSTART   ; PAR0 = page1 reg 1 = NE_BASE+1
    mov cx, 6
.par:
    lodsb
    out dx, al
    inc dx
    loop .par
    ; Back to page 0
    NE_OUT NE_R_CR, 0x21

    ; Enable receiver
    NE_OUT NE_R_RCR, 0x0C  ; accept unicast + broadcast
    NE_OUT NE_R_TCR, 0x00  ; normal TX (no loopback)
    NE_OUT NE_R_ISR, 0xFF  ; clear pending
    NE_OUT NE_R_IMR, 0x00  ; mask all (polling mode)
    ; Start
    NE_OUT NE_R_CR, 0x22

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; ne_send_pkt: transmit packet from NET_SEG:NET_TX_OFF, AX = byte length
; ==========================================================================
ne_send_pkt:
    push ax
    push bx
    push cx
    push dx
    push si
    push es

    ; Pad to minimum 60 bytes
    cmp ax, 60
    jae .nopad
    push ax
    mov bx, NET_SEG
    mov es, bx
    mov bx, NET_TX_OFF
    add bx, ax
    mov cx, 60
    sub cx, ax
    xor al, al
.pad:
    mov byte [es:bx], al
    inc bx
    loop .pad
    pop ax
    mov ax, 60
.nopad:
    ; Set remote DMA to write length bytes
    mov bx, ax              ; save length in BX
    NE_OUT NE_R_RBCR0, 0    ; will set below properly
    mov al, bl
    mov dx, NE_BASE + NE_R_RBCR0
    out dx, al
    mov al, bh
    mov dx, NE_BASE + NE_R_RBCR1
    out dx, al
    ; Remote start address = TX page * 256 = 0x4000 internal
    NE_OUT NE_R_RSAR0, 0x00
    NE_OUT NE_R_RSAR1, NE_TX_PAGE
    ; Remote write command
    NE_OUT NE_R_CR, 0x12
    ; Write packet data word by word via data port
    mov ax, NET_SEG
    mov es, ax
    mov si, NET_TX_OFF
    mov cx, bx              ; byte count
    add cx, 1
    shr cx, 1               ; word count (round up)
    mov dx, NE_BASE + NE_R_DATA
.tx_wr:
    mov ax, [es:si]
    out dx, ax
    add si, 2
    loop .tx_wr
    ; Wait for remote DMA complete (RDC bit)
.rdc_tx:
    NE_IN NE_R_ISR
    test al, 0x40
    jz .rdc_tx
    NE_OUT NE_R_ISR, 0x40
    ; Set TX page and byte count
    NE_OUT NE_R_TPSR, NE_TX_PAGE
    mov al, bl
    mov dx, NE_BASE + NE_R_TBCR0
    out dx, al
    mov al, bh
    mov dx, NE_BASE + NE_R_TBCR1
    out dx, al
    ; Transmit
    NE_OUT NE_R_CR, 0x26
    ; Wait for PTX or TXE
    mov cx, 0x8000
.tx_wait:
    NE_IN NE_R_ISR
    test al, 0x0A
    jnz .tx_done
    loop .tx_wait
.tx_done:
    NE_OUT NE_R_ISR, 0x0A
    NE_OUT NE_R_CR, 0x22   ; back to normal START mode

    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; ne_recv_pkt: poll for received packet
; Returns: AX = length in NET_SEG:NET_RX_OFF, CF=1 if no packet
; ==========================================================================
_nrx_hdr:   times 4 db 0

ne_recv_pkt:
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; Read CURR (page 1 register 7)
    NE_OUT NE_R_CR, 0x62    ; page 1
    NE_IN NE_R_CURR
    mov bl, al              ; BL = CURR
    NE_OUT NE_R_CR, 0x22    ; page 0

    ; Read BNRY
    NE_IN NE_R_BNRY
    inc al                  ; BNRY + 1 = next read page
    cmp al, NE_RX_STOP
    jb .no_wrap
    mov al, NE_RX_START
.no_wrap:
    cmp al, bl              ; if BNRY+1 == CURR → empty
    je .no_pkt
    mov byte [net_rx_next], al      ; this is the page to read

    ; Read 4-byte header from start of receive page
    NE_OUT NE_R_RBCR0, 4
    NE_OUT NE_R_RBCR1, 0
    ; RSAR0=0, RSAR1=page
    NE_OUT NE_R_RSAR0, 0
    mov al, [net_rx_next]
    mov dx, NE_BASE + NE_R_RSAR1
    out dx, al
    ; Remote read
    NE_OUT NE_R_CR, 0x0A
    mov dx, NE_BASE + NE_R_DATA
    in ax, dx               ; bytes: status, next_page
    mov [_nrx_hdr], ax
    in ax, dx               ; bytes: len_lo, len_hi
    mov [_nrx_hdr+2], ax
.rdc_hdr:
    NE_IN NE_R_ISR
    test al, 0x40
    jz .rdc_hdr
    NE_OUT NE_R_ISR, 0x40

    NE_OUT NE_R_CR, 0x22

    ; Calculate data length (packet_len - 4 byte header)
    mov al, [_nrx_hdr+2]   ; len lo
    mov ah, [_nrx_hdr+3]   ; len hi
    sub ax, 4               ; subtract header
    jbe .bad_pkt
    cmp ax, 1518
    ja .bad_pkt
    mov [net_rx_len], ax

    ; Read packet data (start at offset 4 in the page)
    ; Round up to even for 16-bit transfers
    mov bx, ax
    inc bx
    and bx, 0xFFFE          ; make even
    mov al, bl
    mov dx, NE_BASE + NE_R_RBCR0
    out dx, al
    mov al, bh
    mov dx, NE_BASE + NE_R_RBCR1
    out dx, al
    ; Start address: page*256 + 4
    NE_OUT NE_R_RSAR0, 4
    mov al, [net_rx_next]
    mov dx, NE_BASE + NE_R_RSAR1
    out dx, al
    NE_OUT NE_R_CR, 0x0A    ; remote read

    ; Read into NET_SEG:NET_RX_OFF
    mov ax, NET_SEG
    mov es, ax
    mov di, NET_RX_OFF
    mov cx, bx
    shr cx, 1               ; word count
    mov dx, NE_BASE + NE_R_DATA
.rx_rd:
    in ax, dx
    stosw
    loop .rx_rd
.rdc_rx:
    NE_IN NE_R_ISR
    test al, 0x40
    jz .rdc_rx
    NE_OUT NE_R_ISR, 0x40
    NE_OUT NE_R_CR, 0x22

    ; Update BNRY = next_page - 1
    mov al, [_nrx_hdr+1]   ; next page from header
    mov byte [net_rx_next], al
    dec al
    cmp al, NE_RX_START
    jge .bnry_ok
    mov al, NE_RX_STOP - 1
.bnry_ok:
    mov dx, NE_BASE + NE_R_BNRY
    out dx, al

    mov ax, [net_rx_len]
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    clc
    ret

.bad_pkt:
    ; Skip bad packet: update BNRY to next page
    mov al, [_nrx_hdr+1]
    dec al
    cmp al, NE_RX_START
    jge .bad_bnry_ok
    mov al, NE_RX_STOP - 1
.bad_bnry_ok:
    mov dx, NE_BASE + NE_R_BNRY
    out dx, al
.no_pkt:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    stc
    ret

; ==========================================================================
; net_checksum: one's complement checksum
; Input: DS:SI = data start, CX = byte count
; Returns: AX = checksum (ready to store, already complemented)
; NOTE: uses DS:SI (not ES:SI) to avoid segment confusion
; ==========================================================================
net_checksum:
    push bx
    push cx
    push si
    xor bx, bx
.loop:
    cmp cx, 2
    jl .odd
    mov ax, [si]
    add bx, ax
    adc bx, 0
    add si, 2
    sub cx, 2
    jmp .loop
.odd:
    test cx, cx
    jz .done
    xor ah, ah
    mov al, [si]
    add bx, ax
    adc bx, 0
.done:
    not bx
    mov ax, bx
    pop si
    pop cx
    pop bx
    ret

; ==========================================================================
; Byte-swap word in AX (host↔network byte order)
; ==========================================================================
%macro BSWAP16 0
    xchg al, ah
%endmacro

; ==========================================================================
; net_send_arp: send ARP request for IP at DS:SI (4 bytes)
; Uses broadcast destination
; ==========================================================================
net_send_arp:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov ax, NET_SEG
    mov es, ax
    xor di, di              ; DI = NET_TX_OFF = 0

    ; Ethernet: dest = broadcast
    mov al, 0xFF
    mov cx, 6
.bcast: stosb
    loop .bcast
    ; Ethernet: src = our MAC
    push si
    mov si, net_our_mac
    mov cx, 6
.src_mac: lodsb
    stosb
    loop .src_mac
    pop si
    ; EtherType: ARP = 0x0806 → bytes 08 06 → stored BE as 08 06
    mov al, 0x08
    stosb
    mov al, 0x06
    stosb

    ; ARP header
    ; Hardware type: 0x0001 → 00 01
    mov ax, 0x0001
    BSWAP16
    stosw
    ; Protocol: 0x0800 → 08 00
    mov ax, 0x0800
    BSWAP16
    stosw
    ; HW len = 6, proto len = 4
    mov al, 6
    stosb
    mov al, 4
    stosb
    ; Operation: 1 = request → 00 01
    mov ax, 0x0001
    BSWAP16
    stosw
    ; Sender MAC
    push si
    mov si, net_our_mac
    mov cx, 6
.sha: lodsb
    stosb
    loop .sha
    pop si
    ; Sender IP
    mov ax, [net_our_ip]
    BSWAP16
    stosw
    mov ax, [net_our_ip+2]
    BSWAP16
    stosw
    ; Target MAC = zeros
    xor ax, ax
    stosw
    stosw
    stosw
    ; Target IP (from DS:SI)
    lodsw
    BSWAP16
    stosw
    lodsw
    BSWAP16
    stosw

    ; Packet = 14 (eth) + 28 (ARP) = 42, padded to 60
    mov ax, 42
    call ne_send_pkt

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; net_do_arp: resolve net_gw_ip, fill net_gw_mac
; Returns CF=1 on timeout
; ==========================================================================
net_do_arp:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; Send ARP request
    mov si, net_gw_ip
    call net_send_arp

    ; Poll for ARP reply
    mov cx, 0xFFFF
.wait:
    push cx
    call ne_recv_pkt
    pop cx
    jc .next

    ; Got packet: check EtherType = ARP (bytes at offset 12-13: 08 06)
    mov ax, NET_SEG
    mov es, ax
    cmp byte [es:NET_RX_OFF+12], 0x08
    jne .next
    cmp byte [es:NET_RX_OFF+13], 0x06
    jne .next
    ; ARP opcode at offset 20-21: 00 02 = reply
    cmp byte [es:NET_RX_OFF+20], 0x00
    jne .next
    cmp byte [es:NET_RX_OFF+21], 0x02
    jne .next
    ; Sender IP at offset 28-31 = net_gw_ip?
    ; net_gw_ip is stored as raw bytes: 10, 0, 2, 2
    ; In ARP packet they appear as network byte order = same (big-endian)
    ; Compare byte by byte
    mov si, net_gw_ip
    mov di, NET_RX_OFF + 28
    mov al, [si]
    cmp [es:di], al
    jne .next
    mov al, [si+1]
    cmp [es:di+1], al
    jne .next
    mov al, [si+2]
    cmp [es:di+2], al
    jne .next
    mov al, [si+3]
    cmp [es:di+3], al
    jne .next
    ; Extract sender MAC from offset 22-27
    mov di, net_gw_mac
    mov si, NET_RX_OFF + 22
    mov ax, ds
    ; We need to copy from ES (NET_SEG) to DS
    push ds
    push es
    mov bx, NET_SEG
    mov ds, bx
    ; DS:SI = NET_SEG:22
    mov ax, [si]
    pop es
    pop ds
    ; Restore and copy manually
    push es
    mov ax, NET_SEG
    mov es, ax
    mov al, [es:NET_RX_OFF+22]
    mov [net_gw_mac+0], al
    mov al, [es:NET_RX_OFF+23]
    mov [net_gw_mac+1], al
    mov al, [es:NET_RX_OFF+24]
    mov [net_gw_mac+2], al
    mov al, [es:NET_RX_OFF+25]
    mov [net_gw_mac+3], al
    mov al, [es:NET_RX_OFF+26]
    mov [net_gw_mac+4], al
    mov al, [es:NET_RX_OFF+27]
    mov [net_gw_mac+5], al
    pop es

    mov byte [net_gw_arp_ok], 1
    clc
    jmp .arp_done
.next:
    dec cx
    jnz .wait
    stc
.arp_done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; _net_fill_eth: fill Ethernet header in _scratch_eth for a unicast IP pkt
; Destination = net_gw_mac, Source = net_our_mac, Type = IP (08 00)
; ==========================================================================
_scratch_eth: times 14 db 0

_net_fill_eth:
    push cx
    push si
    push di
    mov di, _scratch_eth
    mov si, net_gw_mac
    mov cx, 6
.dst: lodsb
    mov [di], al
    inc di
    loop .dst
    mov si, net_our_mac
    mov cx, 6
.src: lodsb
    mov [di], al
    inc di
    loop .src
    mov byte [di], 0x08
    inc di
    mov byte [di], 0x00
    pop di
    pop si
    pop cx
    ret

; ==========================================================================
; _net_write_ip: write 20-byte IP header at ES:BX
; AH=protocol, [_ip_payload_len]=payload length, _ip_dst=destination IP
; Returns: BX past IP header
; ==========================================================================
_ip_payload_len: dw 0
_ip_dst:         times 4 db 0
_ip_hdr_off:     dw 0

_net_write_ip:
    push ax
    push cx
    push si

    mov [_ip_hdr_off], bx
    ; Version + IHL
    mov byte [es:bx], 0x45
    inc bx
    ; DSCP
    mov byte [es:bx], 0x00
    inc bx
    ; Total length = 20 + payload_len, big-endian
    mov ax, [_ip_payload_len]
    add ax, 20
    xchg al, ah
    mov [es:bx], ax
    add bx, 2
    ; ID
    mov ax, [net_ip_id]
    xchg al, ah
    mov [es:bx], ax
    add bx, 2
    inc word [net_ip_id]
    ; Flags: DF=1, offset=0 → 0x4000 BE → bytes 40 00
    mov byte [es:bx], 0x40
    mov byte [es:bx+1], 0x00
    add bx, 2
    ; TTL=64
    mov byte [es:bx], 64
    inc bx
    ; Protocol (passed in AH)
    mov [es:bx], ah
    inc bx
    ; Checksum = 0 for now
    mov word [es:bx], 0
    add bx, 2
    ; Source IP (our IP, stored in host order — write as raw bytes)
    mov si, net_our_ip
    mov al, [si]
    mov [es:bx], al
    mov al, [si+1]
    mov [es:bx+1], al
    mov al, [si+2]
    mov [es:bx+2], al
    mov al, [si+3]
    mov [es:bx+3], al
    add bx, 4
    ; Destination IP
    mov si, _ip_dst
    mov al, [si]
    mov [es:bx], al
    mov al, [si+1]
    mov [es:bx+1], al
    mov al, [si+2]
    mov [es:bx+2], al
    mov al, [si+3]
    mov [es:bx+3], al
    add bx, 4

    ; Compute IP checksum over the 20-byte header
    push bx
    push es
    ; Copy header to a temp DS buffer for net_checksum
    push di
    mov di, _ip_chk_tmp
    mov si, [_ip_hdr_off]
    mov cx, 20
.cp_hdr:
    mov al, [es:si]
    mov [di], al
    inc si
    inc di
    loop .cp_hdr
    pop di
    pop es
    ; Now compute checksum on DS:_ip_chk_tmp
    mov si, _ip_chk_tmp
    mov cx, 20
    call net_checksum
    ; Store checksum at offset 10 in the header
    pop bx
    push bx
    mov si, [_ip_hdr_off]
    add si, 10
    mov [es:si], ax
    pop bx

    pop si
    pop cx
    pop ax
    ret

_ip_chk_tmp: times 20 db 0

; ==========================================================================
; net_do_dhcp: DHCP discover → get our IP
; Returns CF=1 on failure
; ==========================================================================
net_do_dhcp:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; Zero TX buffer (first 400 bytes)
    mov ax, NET_SEG
    mov es, ax
    xor di, di
    mov cx, 200
    xor ax, ax
    rep stosw

    ; ---- Build Ethernet header (broadcast) ----
    ; dst = FF:FF:FF:FF:FF:FF
    xor di, di
    mov al, 0xFF
    mov cx, 6
.bcast: stosb
    loop .bcast
    ; src = our MAC
    mov si, net_our_mac
    mov cx, 6
.smac: lodsb
    stosb
    loop .smac
    ; EtherType = IP
    mov byte [es:di], 0x08
    inc di
    mov byte [es:di], 0x00
    inc di
    ; DI = 14 (start of IP header)

    ; ---- IP header (20 bytes) ----
    ; We'll build manually since src IP = 0.0.0.0
    mov byte [es:di], 0x45  ; ver+ihl
    inc di
    mov byte [es:di], 0x00  ; dscp
    inc di
    ; Total length = 20+8+236+12 = 276 → BE: 01 14
    mov byte [es:di], 0x01
    inc di
    mov byte [es:di], 0x14
    inc di
    ; ID
    mov byte [es:di], 0x12
    inc di
    mov byte [es:di], 0x34
    inc di
    ; Flags: DF
    mov byte [es:di], 0x40
    inc di
    mov byte [es:di], 0x00
    inc di
    ; TTL=128
    mov byte [es:di], 128
    inc di
    ; Protocol=UDP=17
    mov byte [es:di], 17
    inc di
    ; Checksum placeholder
    mov word [es:di], 0
    add di, 2
    ; Src IP = 0.0.0.0
    mov dword [es:di], 0
    add di, 4
    ; Dst IP = 255.255.255.255
    mov byte [es:di], 255
    mov byte [es:di+1], 255
    mov byte [es:di+2], 255
    mov byte [es:di+3], 255
    add di, 4
    ; DI = 34 (end of IP header)

    ; ---- UDP header ----
    ; Src port = 68 → BE: 00 44
    mov byte [es:di], 0x00
    mov byte [es:di+1], 0x44
    add di, 2
    ; Dst port = 67 → BE: 00 43
    mov byte [es:di], 0x00
    mov byte [es:di+1], 0x43
    add di, 2
    ; UDP length = 8 + 248 = 256 → BE: 01 00
    mov byte [es:di], 0x01
    mov byte [es:di+1], 0x00
    add di, 2
    ; UDP checksum = 0
    mov word [es:di], 0
    add di, 2
    ; DI = 42 (start of DHCP payload)

    ; ---- DHCP payload ----
    mov byte [es:di], 1     ; op = BOOTREQUEST
    inc di
    mov byte [es:di], 1     ; htype = Ethernet
    inc di
    mov byte [es:di], 6     ; hlen = 6
    inc di
    mov byte [es:di], 0     ; hops
    inc di
    ; xid (4 bytes)
    mov ax, [net_dhcp_xid]
    ; store big-endian
    mov byte [es:di], ah
    mov byte [es:di+1], al
    add di, 2
    mov ax, [net_dhcp_xid+2]
    mov byte [es:di], ah
    mov byte [es:di+1], al
    add di, 2
    ; secs=0, flags=broadcast (80 00)
    mov word [es:di], 0
    add di, 2
    mov byte [es:di], 0x80  ; broadcast flag
    mov byte [es:di+1], 0x00
    add di, 2
    ; ciaddr, yiaddr, siaddr, giaddr = all zeros (already zero)
    add di, 16
    ; chaddr = our MAC (6 bytes) + 10 zeros padding to make 16
    mov si, net_our_mac
    mov cx, 6
.dhcp_mac: lodsb
    mov [es:di], al
    inc di
    loop .dhcp_mac
    add di, 10              ; pad to 16 bytes
    ; sname = 64 zeros
    add di, 64
    ; file = 128 zeros
    add di, 128
    ; magic cookie: 63 82 53 63
    mov byte [es:di], 0x63
    mov byte [es:di+1], 0x82
    mov byte [es:di+2], 0x53
    mov byte [es:di+3], 0x63
    add di, 4
    ; DHCP options:
    ; Option 53 = DHCP Message Type = Discover (1)
    mov byte [es:di], 53
    mov byte [es:di+1], 1
    mov byte [es:di+2], 1   ; Discover
    add di, 3
    ; Option 255 = End
    mov byte [es:di], 255
    inc di
    ; DI = total packet length

    ; Compute IP header checksum (over bytes 14..33)
    push di
    push es
    ; copy IP header to DS scratch
    mov si, 14
    mov di, _ip_chk_tmp
    mov cx, 20
.cp_dhcp_ip:
    mov al, [es:si]
    mov [di], al
    inc si
    inc di
    loop .cp_dhcp_ip
    pop es
    pop di
    mov si, _ip_chk_tmp
    mov cx, 20
    call net_checksum
    ; Store at offset 14+10 = 24
    mov word [es:24], ax

    ; Send
    mov ax, di              ; total packet length
    call ne_send_pkt

    ; ---- Wait for DHCP Offer ----
    mov cx, 0xFFFF
.dhcp_poll:
    push cx
    call ne_recv_pkt
    pop cx
    jc .dhcp_next

    ; EtherType = IP?
    cmp byte [es:NET_RX_OFF+12], 0x08
    jne .dhcp_next
    cmp byte [es:NET_RX_OFF+13], 0x00
    jne .dhcp_next
    ; Protocol = UDP?
    cmp byte [es:NET_RX_OFF+23], 17
    jne .dhcp_next
    ; Dst port = 68? (offset 14+20+2 = 36, bytes 0x00 0x44)
    cmp byte [es:NET_RX_OFF+36], 0x00
    jne .dhcp_next
    cmp byte [es:NET_RX_OFF+37], 0x44
    jne .dhcp_next
    ; DHCP op = 2 (BOOTREPLY) at offset 42
    cmp byte [es:NET_RX_OFF+42], 2
    jne .dhcp_next
    ; yiaddr at offset 58 (14+20+8+16 = 58)
    mov al, [es:NET_RX_OFF+58]
    mov [net_our_ip+0], al
    mov al, [es:NET_RX_OFF+59]
    mov [net_our_ip+1], al
    mov al, [es:NET_RX_OFF+60]
    mov [net_our_ip+2], al
    mov al, [es:NET_RX_OFF+61]
    mov [net_our_ip+3], al
    ; Check it's not 0.0.0.0
    mov ax, [net_our_ip]
    or ax, [net_our_ip+2]
    jz .dhcp_next
    mov byte [net_dhcp_ok], 1
    clc
    jmp .dhcp_done

.dhcp_next:
    loop .dhcp_poll
    stc
.dhcp_done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; net_send_tcp_pkt: build and send a TCP segment
; BL = flags, CX = payload length, SI = DS:SI payload data, DX = dst port
; Assumes: net_dst_ip, net_our_ip, net_gw_mac, net_our_mac all set
; ==========================================================================
_tcp_pay_len:  dw 0
_tcp_pay_off:  dw 0       ; offset in _tcp_scratch of payload start
_tcp_flags:    db 0
_tcp_dport:    dw 0
_tcp_scratch:  times 40 db 0  ; header scratch area for checksum

net_send_tcp_pkt:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov [_tcp_pay_len], cx
    mov [_tcp_flags], bl
    mov [_tcp_dport], dx

    ; Zero TX buffer
    mov ax, NET_SEG
    mov es, ax
    xor di, di
    mov cx, 80
    xor ax, ax
    rep stosw
    xor di, di

    ; ---- Ethernet header ----
    mov si, net_gw_mac
    mov cx, 6
.eth_dst: lodsb
    stosb
    loop .eth_dst
    mov si, net_our_mac
    mov cx, 6
.eth_src: lodsb
    stosb
    loop .eth_src
    mov byte [es:di], 0x08
    inc di
    mov byte [es:di], 0x00
    inc di
    ; DI=14

    ; ---- IP header ----
    mov byte [es:di], 0x45  ; ver+ihl
    inc di
    mov byte [es:di], 0x00
    inc di
    ; Total = 20 + 20 + payload
    mov ax, [_tcp_pay_len]
    add ax, 40
    xchg al, ah             ; BE
    mov [es:di], ax
    add di, 2
    ; ID
    mov ax, [net_ip_id]
    xchg al, ah
    mov [es:di], ax
    add di, 2
    inc word [net_ip_id]
    ; Flags: DF
    mov byte [es:di], 0x40
    mov byte [es:di+1], 0x00
    add di, 2
    ; TTL=64, Proto=TCP=6
    mov byte [es:di], 64
    mov byte [es:di+1], 6
    add di, 2
    ; Checksum=0 placeholder
    mov word [es:di], 0
    add di, 2
    ; Src IP
    mov al, [net_our_ip+0]
    mov [es:di], al
    mov al, [net_our_ip+1]
    mov [es:di+1], al
    mov al, [net_our_ip+2]
    mov [es:di+2], al
    mov al, [net_our_ip+3]
    mov [es:di+3], al
    add di, 4
    ; Dst IP
    mov al, [net_dst_ip+0]
    mov [es:di], al
    mov al, [net_dst_ip+1]
    mov [es:di+1], al
    mov al, [net_dst_ip+2]
    mov [es:di+2], al
    mov al, [net_dst_ip+3]
    mov [es:di+3], al
    add di, 4
    ; DI=34 (end of IP hdr)

    ; Compute IP checksum
    push di
    push es
    mov si, 14              ; start of IP header in TX buffer (ES:14)
    mov di, _ip_chk_tmp
    mov cx, 20
    mov bx, NET_SEG
.cp_ip_tcp:
    ; Read from ES (NET_SEG) to DS
    push ds
    mov ds, bx
    mov al, [si]
    pop ds
    mov [di], al
    inc si
    inc di
    loop .cp_ip_tcp
    pop es
    pop di
    mov si, _ip_chk_tmp
    mov cx, 20
    call net_checksum
    mov [es:24], ax         ; offset 14+10=24

    ; ---- TCP header ----
    ; DI=34
    ; Src port
    mov ax, [net_tcp_sport]
    xchg al, ah
    mov [es:di], ax
    add di, 2
    ; Dst port
    mov ax, [_tcp_dport]
    xchg al, ah
    mov [es:di], ax
    add di, 2
    ; Sequence number (stored little-endian in net_tcp_seq, send big-endian)
    mov al, [net_tcp_seq+3]
    mov [es:di], al
    mov al, [net_tcp_seq+2]
    mov [es:di+1], al
    mov al, [net_tcp_seq+1]
    mov [es:di+2], al
    mov al, [net_tcp_seq+0]
    mov [es:di+3], al
    add di, 4
    ; ACK number
    mov al, [net_tcp_ack+3]
    mov [es:di], al
    mov al, [net_tcp_ack+2]
    mov [es:di+1], al
    mov al, [net_tcp_ack+1]
    mov [es:di+2], al
    mov al, [net_tcp_ack+0]
    mov [es:di+3], al
    add di, 4
    ; Data offset = 5 (20 bytes / 4), flags
    mov byte [es:di], 0x50  ; offset=5, reserved=0
    inc di
    mov al, [_tcp_flags]
    mov [es:di], al
    inc di
    ; Window = 0x2000 = 8192
    mov byte [es:di], 0x20
    mov byte [es:di+1], 0x00
    add di, 2
    ; Checksum = 0 placeholder
    mov word [es:di], 0
    add di, 2
    ; Urgent = 0
    mov word [es:di], 0
    add di, 2
    ; DI = 54 (start of payload)

    ; Copy payload
    push di
    mov cx, [_tcp_pay_len]
    test cx, cx
    jz .no_tcp_payload
    ; SI already points to payload in DS
.tcp_copy:
    lodsb
    mov [es:di], al
    inc di
    loop .tcp_copy
.no_tcp_payload:
    pop di                  ; restore DI = start of payload in TX buf

    ; ---- TCP Pseudo-header checksum ----
    ; pseudo = src_ip(4) + dst_ip(4) + 0(1) + proto(1) + tcp_len(2)
    ; tcp_len = 20 + payload_len
    ; Build pseudo in _tcp_scratch
    mov di, _tcp_scratch
    mov al, [net_our_ip+0]
    stosb
    mov al, [net_our_ip+1]
    stosb
    mov al, [net_our_ip+2]
    stosb
    mov al, [net_our_ip+3]
    stosb
    mov al, [net_dst_ip+0]
    stosb
    mov al, [net_dst_ip+1]
    stosb
    mov al, [net_dst_ip+2]
    stosb
    mov al, [net_dst_ip+3]
    stosb
    mov al, 0
    stosb
    mov al, 6               ; TCP
    stosb
    mov ax, [_tcp_pay_len]
    add ax, 20              ; TCP header + payload
    xchg al, ah             ; BE
    stosw

    ; Checksum the pseudo-header (12 bytes)
    mov si, _tcp_scratch
    mov cx, 12
    call net_checksum
    ; net_checksum returns NOT(sum), but we want the partial sum
    ; Workaround: un-complement it to get the raw sum, then add TCP+payload
    not ax                  ; get back the raw one's complement sum

    mov bx, ax              ; BX = partial pseudo-header sum

    ; Add TCP header + payload (from NET_SEG)
    ; TCP header starts at ES:34, length = 20 + payload_len
    push es
    mov ax, NET_SEG
    mov es, ax
    mov si, 34              ; TCP header offset in TX buffer
    mov cx, [_tcp_pay_len]
    add cx, 20              ; header + payload
    add cx, 1
    shr cx, 1               ; word count
.tcp_csum:
    mov ax, [es:si]
    add bx, ax
    adc bx, 0
    add si, 2
    loop .tcp_csum
    pop es

    ; Final one's complement
    not bx
    ; Store at TCP checksum (offset 34+16=50 in TX buffer)
    mov [es:50], bx

    ; ---- Send packet ----
    mov ax, [_tcp_pay_len]
    add ax, 54              ; 14+20+20
    call ne_send_pkt

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; net_tcp_connect: open TCP connection to net_dst_ip port BX
; Returns CF=1 on failure
; ==========================================================================
net_tcp_connect:
    push ax
    push bx
    push cx
    push dx
    push si
    push es

    mov [net_tcp_port], bx

    ; Init sequence number
    mov dword [net_tcp_seq], 0x00C0FFEE
    mov dword [net_tcp_ack], 0

    ; Send SYN
    xor cx, cx
    xor si, si
    mov bl, 0x02            ; SYN flag
    mov dx, [net_tcp_port]
    call net_send_tcp_pkt
    ; SYN consumes one sequence number
    inc dword [net_tcp_seq]

    ; Wait for SYN-ACK
    mov ax, NET_SEG
    mov es, ax
    mov cx, 0xFFFF
.syn_poll:
    push cx
    call ne_recv_pkt
    pop cx
    jc .syn_next

    ; IP?
    cmp byte [es:NET_RX_OFF+12], 0x08
    jne .syn_next
    cmp byte [es:NET_RX_OFF+13], 0x00
    jne .syn_next
    ; TCP?
    cmp byte [es:NET_RX_OFF+23], 6
    jne .syn_next
    ; Dst port = our source port? (offset 36-37, BE)
    mov al, [es:NET_RX_OFF+36]
    mov ah, [es:NET_RX_OFF+37]
    xchg al, ah             ; host order
    cmp ax, [net_tcp_sport]
    jne .syn_next
    ; Flags (offset 47): SYN+ACK = 0x12
    mov al, [es:NET_RX_OFF+47]
    and al, 0x12
    cmp al, 0x12
    jne .syn_next
    ; Extract their SEQ (offset 38-41), store as our ACK (+1)
    ; Network byte order → host byte order
    mov al, [es:NET_RX_OFF+41]
    mov [net_tcp_ack+0], al
    mov al, [es:NET_RX_OFF+40]
    mov [net_tcp_ack+1], al
    mov al, [es:NET_RX_OFF+39]
    mov [net_tcp_ack+2], al
    mov al, [es:NET_RX_OFF+38]
    mov [net_tcp_ack+3], al
    ; ACK = server_seq + 1
    inc dword [net_tcp_ack]
    ; Send ACK
    xor cx, cx
    xor si, si
    mov bl, 0x10            ; ACK
    mov dx, [net_tcp_port]
    call net_send_tcp_pkt
    clc
    jmp .conn_done

.syn_next:
    loop .syn_poll
    stc
.conn_done:
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; net_update_ack: update net_tcp_ack based on received packet
; Input: ES = NET_SEG, TCP data length in AX
; ==========================================================================
net_update_ack:
    add [net_tcp_ack], ax
    adc word [net_tcp_ack+2], 0
    ret

; ==========================================================================
; net_parse_ip: parse dotted-decimal IP in DS:SI, write 4 bytes at DS:DI
; Returns: CF=0 ok, CF=1 error; SI/DI advanced
; ==========================================================================
net_parse_ip:
    push ax
    push bx
    push cx
    mov bx, 4               ; octet count
.oct:
    xor ax, ax
.digit:
    mov cl, [si]
    cmp cl, '0'
    jb .eoct
    cmp cl, '9'
    ja .eoct
    sub cl, '0'
    xor ch, ch
    push cx
    mov cx, 10
    mul cx
    pop cx
    add al, cl
    inc si
    jmp .digit
.eoct:
    mov [di], al
    inc di
    dec bx
    jz .done
    cmp byte [si], '.'
    jne .err
    inc si
    jmp .oct
.done:
    pop cx
    pop bx
    pop ax
    clc
    ret
.err:
    pop cx
    pop bx
    pop ax
    stc
    ret

; ==========================================================================
; net_print_ip: print 4 bytes at DS:SI as n.n.n.n
; ==========================================================================
net_print_ip:
    push ax
    push cx
    push si
    mov cx, 4
.lp:
    mov al, [si]
    xor ah, ah
    call print_word_dec
    inc si
    dec cx
    jz .done
    mov al, '.'
    call vid_putchar
    jmp .lp
.done:
    pop si
    pop cx
    pop ax
    ret

; ==========================================================================
; net_is_ip: check if DS:SI looks like a dotted IP (only digits and dots)
; Returns CF=0 = looks like IP, CF=1 = probably hostname
; ==========================================================================
net_is_ip:
    push ax
    push si
.chk:
    mov al, [si]
    test al, al
    jz .yes
    cmp al, '.'
    je .next
    cmp al, '0'
    jb .no
    cmp al, '9'
    ja .no
.next:
    inc si
    jmp .chk
.yes:
    pop si
    pop ax
    clc
    ret
.no:
    pop si
    pop ax
    stc
    ret

; ==========================================================================
; net_http_get: full HTTP fetch
; Input: net_dst_ip set, DS:SI = hostname string (for Host: header)
; ==========================================================================
_http_host_ptr: dw 0
_http_req:      times 200 db 0
_http_shown:    dw 0

net_http_get:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov [_http_host_ptr], si

    ; ARP for gateway
    mov si, str_net_arp
    call vid_print
    call net_do_arp
    jc .err_arp
    mov si, str_net_ok
    call vid_println

    ; TCP connect to port 80
    mov si, str_net_conn
    call vid_print
    mov bx, 80
    call net_tcp_connect
    jc .err_tcp
    mov si, str_net_ok
    call vid_println

    ; Build HTTP request in DS:_http_req
    mov di, _http_req
    mov si, str_http_req1   ; "GET / HTTP/1.0\r\n"
.cpy1: lodsb
    test al, al
    jz .r1d
    mov [di], al
    inc di
    jmp .cpy1
.r1d:
    mov si, str_http_host   ; "Host: "
.cpy2: lodsb
    test al, al
    jz .r2d
    mov [di], al
    inc di
    jmp .cpy2
.r2d:
    mov si, [_http_host_ptr]
.cpy3: lodsb
    test al, al
    jz .r3d
    mov [di], al
    inc di
    jmp .cpy3
.r3d:
    mov byte [di], 0x0D
    inc di
    mov byte [di], 0x0A
    inc di
    mov si, str_http_conn   ; "Connection: close\r\n\r\n"
.cpy4: lodsb
    test al, al
    jz .r4d
    mov [di], al
    inc di
    jmp .cpy4
.r4d:
    ; CX = request length
    mov cx, di
    sub cx, _http_req

    ; Send HTTP GET
    mov si, str_net_send
    call vid_println
    mov si, _http_req
    mov bl, 0x18            ; PSH+ACK
    mov dx, 80
    call net_send_tcp_pkt
    ; Advance SEQ by payload length
    add [net_tcp_seq], cx
    adc word [net_tcp_seq+2], 0

    ; Print response header
    mov si, str_net_resp
    call vid_println
    mov al, '-'
    mov cx, 60
.sep: call vid_putchar
    loop .sep
    call vid_nl

    ; Receive loop
    mov word [_http_shown], 0
    mov ax, NET_SEG
    mov es, ax
    mov cx, 0xFFFF
.recv_lp:
    push cx
    call ne_recv_pkt
    pop cx
    jc .recv_to

    ; IP/TCP?
    cmp byte [es:NET_RX_OFF+12], 0x08
    jne .recv_next
    cmp byte [es:NET_RX_OFF+13], 0x00
    jne .recv_next
    cmp byte [es:NET_RX_OFF+23], 6
    jne .recv_next
    ; Our port?
    mov al, [es:NET_RX_OFF+36]
    mov ah, [es:NET_RX_OFF+37]
    xchg al, ah
    cmp ax, [net_tcp_sport]
    jne .recv_next

    ; Check FIN flag
    mov al, [es:NET_RX_OFF+47]
    test al, 0x01
    jnz .got_fin

    ; TCP payload length:
    ; IP total at offset 16-17 (BE)
    mov al, [es:NET_RX_OFF+16]
    mov ah, [es:NET_RX_OFF+17]
    xchg al, ah             ; host order: IP total length
    mov bx, ax
    sub bx, 20              ; minus IP header
    ; TCP data offset at byte 46 (upper nibble * 4)
    mov al, [es:NET_RX_OFF+46]
    shr al, 4
    xor ah, ah
    shl ax, 2               ; TCP header length in bytes
    sub bx, ax              ; BX = payload length
    test bx, bx
    jle .recv_next

    ; Update ACK
    add [net_tcp_ack], bx
    adc word [net_tcp_ack+2], 0

    ; Send ACK
    push bx
    push es
    push cx
    xor cx, cx
    xor si, si
    mov bl, 0x10            ; ACK
    mov dx, 80
    call net_send_tcp_pkt
    pop cx
    pop es
    pop bx

    ; Check if we've shown enough
    add [_http_shown], bx
    cmp word [_http_shown], 3000
    jge .got_fin

    ; Print payload bytes
    ; Payload starts at offset 14+20+TCP_data_offset
    mov al, [es:NET_RX_OFF+46]
    shr al, 4
    xor ah, ah
    shl ax, 2
    add ax, 34              ; 14+20 = 34
    mov si, ax              ; SI = payload offset in RX buffer

.disp:
    test bx, bx
    jz .recv_next
    mov al, [es:NET_RX_OFF+si]
    inc si
    dec bx
    cmp al, 0x0D
    je .disp
    cmp al, 0x0A
    jne .not_nl
    call vid_nl
    jmp .disp
.not_nl:
    cmp al, 0x20
    jb .disp
    cmp al, 0x7E
    ja .disp
    call vid_putchar
    jmp .disp

.recv_next:
    dec cx
    jnz .recv_lp

.recv_to:
.got_fin:
    ; Send FIN+ACK
    xor cx, cx
    xor si, si
    mov bl, 0x11            ; FIN+ACK
    mov dx, 80
    call net_send_tcp_pkt
    call vid_nl
    mov si, str_net_done
    call vid_println
    clc
    jmp .http_out

.err_arp:
    mov si, str_net_err_arp
    call vid_println
    stc
    jmp .http_out
.err_tcp:
    mov si, str_net_err_tcp
    call vid_println
    stc

.http_out:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; net_run: NET command handler
; Usage: NET <hostname_or_ip>
; ==========================================================================
net_run:
    push ax
    push bx
    push cx
    push si
    push di
    push es

    mov si, str_net_banner
    call vid_println

    cmp byte [sh_arg], 0
    je .usage

    ; Copy argument to net_arg_buf
    mov si, sh_arg
    mov di, net_arg_buf
    mov cx, 127
.cp_arg:
    lodsb
    stosb
    test al, al
    jz .arg_done
    loop .cp_arg
.arg_done:

    ; Initialize NE2000
    mov si, str_net_init
    call vid_print
    call ne_init
    mov si, str_net_ok
    call vid_println

    ; Print MAC
    mov si, str_net_mac
    call vid_print
    mov si, net_our_mac
    mov cx, 6
.mac_pr:
    mov al, [si]
    call print_hex_byte
    inc si
    dec cx
    jz .mac_done
    mov al, ':'
    call vid_putchar
    jmp .mac_pr
.mac_done:
    call vid_nl

    ; DHCP
    mov si, str_net_dhcp
    call vid_print
    call net_do_dhcp
    jc .err_dhcp
    mov si, str_net_ip
    call vid_print
    mov si, net_our_ip
    call net_print_ip
    call vid_nl

    ; Resolve destination
    mov si, net_arg_buf
    call net_is_ip
    jnc .is_ip

    ; Hostname → print resolving message
    mov si, str_net_resolv
    call vid_print
    mov si, net_arg_buf
    call vid_println
    ; Simple: try to use a hard-coded resolution (user typed hostname)
    ; For now, print note and use 93.184.216.34 (example.com)
    ; Real DNS would require full UDP/DNS implementation
    ; A future update can add full DNS; for now suggest using IP directly
    mov si, str_net_use_ip
    call vid_println
    jmp .done_run

.is_ip:
    ; Parse IP
    mov si, net_arg_buf
    mov di, net_dst_ip
    call net_parse_ip
    jc .err_ip

    ; Print connecting message
    mov si, str_net_connecting
    call vid_print
    mov si, net_dst_ip
    call net_print_ip
    call vid_nl

    ; HTTP GET
    mov si, net_arg_buf
    call net_http_get
    jmp .done_run

.usage:
    mov si, str_net_usage
    call vid_println
    jmp .done_run

.err_dhcp:
    mov si, str_net_err_dhcp
    call vid_println
    jmp .done_run
.err_ip:
    mov si, str_net_err_ip
    call vid_println

.done_run:
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ==========================================================================
; Strings
; ==========================================================================
str_net_banner:     db "KSDOS-NET v1.0 - Real Internet via NE2000+QEMU", 0
str_net_usage:      db "Usage: NET <ip>   e.g. NET 93.184.216.34", 0x0A
                    db "  (For hostnames, use dotted IP - DNS coming soon)", 0
str_net_init:       db "NE2000: Init...", 0
str_net_ok:         db " [OK]", 0
str_net_mac:        db "NE2000: MAC = ", 0
str_net_dhcp:       db "DHCP: Requesting IP...", 0
str_net_ip:         db "DHCP: Got IP = ", 0
str_net_arp:        db "ARP: Gateway...", 0
str_net_conn:       db "TCP: Connecting to port 80...", 0
str_net_send:       db "HTTP: Sending GET /", 0
str_net_resp:       db "HTTP: Response:", 0
str_net_done:       db "[Transfer complete]", 0
str_net_resolv:     db "DNS: Resolving hostname: ", 0
str_net_connecting: db "NET: Connecting to ", 0
str_net_use_ip:     db "Note: Hostname DNS not yet supported.", 0x0A
                    db "Please use a dotted IP address instead.", 0x0A
                    db "Example: NET 93.184.216.34", 0
str_net_err_dhcp:   db "Error: DHCP failed (no IP assigned).", 0
str_net_err_arp:    db "Error: ARP failed (gateway unreachable).", 0
str_net_err_tcp:    db "Error: TCP connection failed.", 0
str_net_err_ip:     db "Error: Invalid IP address format.", 0
str_http_req1:      db "GET / HTTP/1.0", 0x0D, 0x0A, 0
str_http_host:      db "Host: ", 0
str_http_conn:      db "Connection: close", 0x0D, 0x0A, 0x0D, 0x0A, 0
