; =============================================================================
; FILE: lcd_driver.S
; PERAN: 2 - Pengembang Antarmuka & Logika Pemetaan
; DESKRIPSI: Driver LCD 16x2 via I2C (PCF8574 internal di JHD-2X16-I2C)
;            Mode 4-bit, HD44780 compatible
;
; DEPENDENSI: lcd_i2c.S harus di-#include SEBELUM file ini
;
; PINOUT PCF8574 (Versi A — standar LiquidCrystal_I2C):
;   P0 = RS   (Register Select: 0=Command, 1=Data)
;   P1 = RW   (Read/Write: selalu 0=Write)
;   P2 = EN   (Enable pulse)
;   P3 = BL   (Backlight: 1=ON)
;   P4 = D4
;   P5 = D5
;   P6 = D6
;   P7 = D7
;
; KONVENSI PEMANGGILAN:
;   LCD_CMD    → R16 = byte command sebelum RCALL
;   LCD_CHAR   → R16 = karakter ASCII sebelum RCALL
;   LCD_GOTOXY → R16 = baris (0/1), R17 = kolom (0–15) sebelum RCALL
;   LCD_STRING → Z (ZH:ZL) = pointer ke string di Flash sebelum RCALL
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; =============================================================================
; KONSTANTA BIT MASK PCF8574
; =============================================================================
.equ LCD_BL,  0x08      ; P3 — Backlight ON
.equ LCD_EN,  0x04      ; P2 — Enable
.equ LCD_RW,  0x02      ; P1 — RW (selalu 0)
.equ LCD_RS,  0x01      ; P0 — RS

; Command HD44780
.equ LCD_CLEAR,       0x01   ; Clear display
.equ LCD_HOME,        0x02   ; Return home
.equ LCD_ENTRY_MODE,  0x06   ; Entry mode: increment, no shift
.equ LCD_DISPLAY_ON,  0x0C   ; Display ON, cursor OFF, blink OFF
.equ LCD_4BIT_2LINE,  0x28   ; 4-bit mode, 2 baris, 5x8 font
.equ LCD_ROW0,        0x80   ; DDRAM address baris 0, kolom 0
.equ LCD_ROW1,        0xC0   ; DDRAM address baris 1, kolom 0

; =============================================================================
; LCD_SEND_NIBBLE  [INTERNAL]
; Deskripsi : Kirim 4-bit upper nibble dari R16 ke LCD via PCF8574
;             Menghasilkan EN pulse: HIGH → LOW
; Input     : R16 = byte yang upper nibble-nya akan dikirim
;             R18 = nilai RS (0x00 = command, LCD_RS = data)
; Output    : Tidak ada
; Modifikasi: R17 (di-PUSH/POP)
; =============================================================================
LCD_SEND_NIBBLE:
    PUSH R17

    ; Ambil upper nibble R16, geser ke posisi D4-D7 (bit 4-7)
    ; PCF8574: D4=P4, D5=P5, D6=P6, D7=P7
    MOV  R17, R16
    ANDI R17, 0xF0          ; ambil hanya upper nibble

    ; Gabungkan dengan BL + RS
    OR   R17, R18           ; tambah RS (command/data)
    ORI  R17, LCD_BL        ; backlight selalu ON

    ; Kirim dengan EN=HIGH
    MOV  R16, R17
    ORI  R16, LCD_EN        ; set EN bit
    RCALL TWI_START
    RCALL TWI_WRITE_ADDR
    RCALL TWI_WRITE         ; kirim dengan EN high
    RCALL TWI_STOP

    ; Kirim dengan EN=LOW (falling edge = LCD latch data)
    MOV  R16, R17
    ANDI R16, ~LCD_EN       ; clear EN bit
    RCALL TWI_START
    RCALL TWI_WRITE_ADDR
    RCALL TWI_WRITE         ; kirim dengan EN low
    RCALL TWI_STOP

    POP R17
    RET

; =============================================================================
; LCD_SEND_BYTE  [INTERNAL]
; Deskripsi : Kirim 1 byte penuh ke LCD dalam 2 nibble (mode 4-bit)
;             Upper nibble dulu, lalu lower nibble
; Input     : R16 = byte yang akan dikirim (command atau data)
;             R18 = mode (0x00 = command, LCD_RS = data karakter)
; Output    : Tidak ada
; Modifikasi: R16, R17, R19 (di-PUSH/POP)
; =============================================================================
LCD_SEND_BYTE:
    PUSH R17
    PUSH R19

    MOV  R19, R16           ; simpan byte asli di R19

    ; Kirim upper nibble (bit 7-4)
    RCALL LCD_SEND_NIBBLE

    ; Geser lower nibble ke posisi upper
    MOV  R16, R19
    SWAP R16                ; tukar nibble: lower naik ke atas
    RCALL LCD_SEND_NIBBLE

    ; Delay singkat setelah kirim byte (~40us cukup untuk kebanyakan command)
    RCALL LCD_DELAY_SHORT

    POP R19
    POP R17
    RET

; =============================================================================
; LCD_CMD
; Deskripsi : Kirim 1 byte command ke LCD (RS=0)
; Input     : R16 = command byte
; Output    : Tidak ada
; Modifikasi: R18 (di-PUSH/POP), R16, R17, R19 via LCD_SEND_BYTE
; =============================================================================
LCD_CMD:
    PUSH R18
    LDI  R18, 0x00          ; RS=0 → command mode
    RCALL LCD_SEND_BYTE
    POP  R18
    RET

; =============================================================================
; LCD_CHAR
; Deskripsi : Kirim 1 karakter ASCII ke LCD (RS=1)
; Input     : R16 = karakter ASCII (misal: 0x41 = 'A')
; Output    : Tidak ada
; Modifikasi: R18 (di-PUSH/POP), R16, R17, R19 via LCD_SEND_BYTE
; =============================================================================
LCD_CHAR:
    PUSH R18
    LDI  R18, LCD_RS        ; RS=1 → data/karakter mode
    RCALL LCD_SEND_BYTE
    POP  R18
    RET

; =============================================================================
; LCD_STRING
; Deskripsi : Print string null-terminated dari Flash ke LCD
;             Posisi cursor mengikuti posisi saat ini (set dulu dengan GOTOXY)
; Input     : Z (ZH:ZL) = pointer ke string di Flash (dari lookup_table.S)
; Output    : Tidak ada
; Modifikasi: R16, R18 (di-PUSH/POP)
; =============================================================================
LCD_STRING:
    PUSH R16
    PUSH R18

_lcd_string_loop:
    LPM  R16, Z+            ; baca 1 karakter dari Flash, Z auto-increment
    CPI  R16, 0x00          ; cek null terminator
    BREQ _lcd_string_done   ; kalau null → selesai
    RCALL LCD_CHAR          ; print karakter
    RJMP _lcd_string_loop

_lcd_string_done:
    POP  R18
    POP  R16
    RET

; =============================================================================
; LCD_GOTOXY
; Deskripsi : Pindah posisi cursor ke baris dan kolom tertentu
; Input     : R16 = baris (0 = baris atas, 1 = baris bawah)
;             R17 = kolom (0–15)
; Output    : Tidak ada
; Modifikasi: R16, R17, R18, R19 (di-PUSH/POP)
; =============================================================================
LCD_GOTOXY:
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R19               ; R19 = temp kalkulasi DDRAM, pisah dari input R16

    ; Hitung DDRAM address ke R19 — R16 (input baris) tidak disentuh
    ; Baris 0: address = 0x80 + kolom
    ; Baris 1: address = 0xC0 + kolom
    CPI  R16, 0             ; cek baris dari input asli
    BREQ _gotoxy_row0
    LDI  R19, LCD_ROW1      ; baris 1 → base 0xC0
    RJMP _gotoxy_set
_gotoxy_row0:
    LDI  R19, LCD_ROW0      ; baris 0 → base 0x80
_gotoxy_set:
    ADD  R19, R17           ; tambah offset kolom (R17 = input kolom, tidak disentuh)
    MOV  R16, R19           ; pindah hasil ke R16 untuk LCD_CMD
    RCALL LCD_CMD           ; kirim sebagai command

    POP  R19
    POP  R18
    POP  R17
    POP  R16               ; R16 dikembalikan ke nilai asli pemanggil
    RET

; =============================================================================
; LCD_CLEAR
; Deskripsi : Bersihkan seluruh layar LCD dan kembalikan cursor ke home
; Input     : Tidak ada
; Output    : Tidak ada
; Modifikasi: R16, R18 via LCD_CMD
; =============================================================================
LCD_CLEAR_SCREEN:
    PUSH R16
    LDI  R16, LCD_CLEAR
    RCALL LCD_CMD
    RCALL LCD_DELAY_LONG    ; clear butuh waktu lebih lama ~1.52ms
    POP  R16
    RET

; =============================================================================
; LCD_INIT
; Deskripsi : Inisialisasi LCD HD44780 mode 4-bit via PCF8574
;             Wajib dipanggil SEKALI di bagian RESET sebelum fungsi lain
; Input     : Tidak ada
; Output    : Tidak ada
; =============================================================================
LCD_INIT:
    PUSH R16
    PUSH R17
    PUSH R18

    ; Inisialisasi TWI dulu
    RCALL TWI_INIT

    ; Tunggu LCD power-on stable (>40ms setelah VCC naik ke 2.7V)
    RCALL LCD_DELAY_LONG
    RCALL LCD_DELAY_LONG
    RCALL LCD_DELAY_LONG

    ; =========================================================
    ; Sequence inisialisasi 4-bit mode (per datasheet HD44780)
    ; Kirim 0x30 sebagai nibble 3x dengan delay
    ; =========================================================

    ; Step 1: Kirim 0x3 (upper nibble 0x30) — function set pertama
    LDI  R16, 0x30
    LDI  R18, 0x00
    RCALL LCD_SEND_NIBBLE
    RCALL LCD_DELAY_LONG    ; tunggu >4.1ms

    ; Step 2: Kirim 0x3 lagi — function set kedua
    LDI  R16, 0x30
    RCALL LCD_SEND_NIBBLE
    RCALL LCD_DELAY_SHORT   ; tunggu >100us

    ; Step 3: Kirim 0x3 lagi — function set ketiga
    LDI  R16, 0x30
    RCALL LCD_SEND_NIBBLE
    RCALL LCD_DELAY_SHORT

    ; Step 4: Switch ke 4-bit mode — kirim 0x2
    LDI  R16, 0x20
    RCALL LCD_SEND_NIBBLE
    RCALL LCD_DELAY_SHORT

    ; =========================================================
    ; Mulai dari sini LCD sudah dalam 4-bit mode
    ; Kirim command lengkap (2 nibble per byte)
    ; =========================================================

    ; Function Set: 4-bit, 2 baris, font 5x8
    LDI  R16, LCD_4BIT_2LINE
    RCALL LCD_CMD

    ; Display OFF
    LDI  R16, 0x08
    RCALL LCD_CMD

    ; Clear Display
    LDI  R16, LCD_CLEAR
    RCALL LCD_CMD
    RCALL LCD_DELAY_LONG    ; clear perlu ~1.52ms

    ; Entry Mode Set: increment cursor, no display shift
    LDI  R16, LCD_ENTRY_MODE
    RCALL LCD_CMD

    ; Display ON, cursor OFF, blink OFF
    LDI  R16, LCD_DISPLAY_ON
    RCALL LCD_CMD

    POP  R18
    POP  R17
    POP  R16
    RET

; =============================================================================
; LCD_DELAY_SHORT  [INTERNAL]
; Deskripsi : Delay ~200us pada 16MHz (atau ~400us pada 8MHz)
;             Dipakai antar nibble / setelah command ringan
; =============================================================================
LCD_DELAY_SHORT:
    PUSH R16
    PUSH R17
    LDI  R17, 10            ; outer loop
_dshort_outer:
    LDI  R16, 0xFF          ; inner loop ~255 × 3 cycle = 765 cycle
_dshort_inner:
    DEC  R16
    BRNE _dshort_inner
    DEC  R17
    BRNE _dshort_outer
    POP  R17
    POP  R16
    RET

; =============================================================================
; LCD_DELAY_LONG  [INTERNAL]
; Deskripsi : Delay ~5ms pada 16MHz
;             Dipakai setelah LCD_CLEAR dan saat init sequence
; =============================================================================
LCD_DELAY_LONG:
    PUSH R16
    PUSH R17
    LDI  R17, 0xFF          ; outer loop
_dlong_outer:
    LDI  R16, 0xFF
_dlong_inner:
    DEC  R16
    BRNE _dlong_inner
    DEC  R17
    BRNE _dlong_outer
    POP  R17
    POP  R16
    RET

; =============================================================================
; CONTOH PENGGUNAAN (jangan hapus komentar ini):
;
; Print "Hello" di baris 0 kolom 0:
;   RCALL LCD_INIT
;   LDI  R16, 0             ; baris 0
;   LDI  R17, 0             ; kolom 0
;   RCALL LCD_GOTOXY
;   LDI  R16, 'H'
;   RCALL LCD_CHAR
;   LDI  R16, 'e'
;   RCALL LCD_CHAR
;   ... dst
;
; Print string dari Flash:
;   LDI  ZH, hi8(STR_NICE)
;   LDI  ZL, lo8(STR_NICE)
;   RCALL LCD_STRING
;
; =============================================================================