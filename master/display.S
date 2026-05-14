; =============================================================================
; FILE: display.S
; PERAN: 2 - Pengembang Antarmuka & Logika Pemetaan
; DESKRIPSI: Fungsi utama UPDATE_DISPLAY — merakit semua output ke LCD
;
; DEPENDENSI (harus di-#include sebelum file ini, urutan ini persis):
;   1. lcd_i2c.S
;   2. lcd_driver.S
;   3. lookup_table.S
;   4. bcd_ascii.S
;   5. mapping.S
;   6. display.S  ← file ini, SELALU TERAKHIR
;
; FUNGSI PUBLIK:
;   UPDATE_DISPLAY → satu-satunya fungsi yang Peran 3 panggil dari main.S
;
; LAYOUT LCD 16x2:
;   +----------------+
;   |T:A2   A:110 Hz |   ← Baris 0
;   |TOO LOOSE       |   ← Baris 1
;   +----------------+
;
;   Kolom 0–3  : "T:XX"  → nama nada target (dari R23)
;   Kolom 4–6  : "   "   → spasi separator
;   Kolom 7–8  : "A:"    → label aktual
;   Kolom 9–11 : "XXX"   → Hz aktual 3 digit (dari R25:R24)
;   Kolom 12–14: " Hz"   → satuan
;   Kolom 15   : " "     → spasi akhir
;   Baris 1    : status message (10 karakter + spasi padding)
;
; INPUT DARI PERAN 3 (harus diisi sebelum RCALL UPDATE_DISPLAY):
;   R25 = High Byte Hz aktual
;   R24 = Low  Byte Hz aktual
;   R23 = index senar target (0=E2, 1=A2, 2=D3, 3=G3, 4=B3, 5=E4)
;
; [PLACEHOLDER] FLAG DATA BARU:
;   Saat ini UPDATE_DISPLAY langsung dijalankan tanpa cek flag.
;   Kalau Peran 3 mau pakai flag, ganti bagian awal UPDATE_DISPLAY:
;
;   ; --- GANTI BARIS INI ---
;   ; SBRS R22, 0          ; cek bit 0 R22 (flag data baru)
;   ; RET                  ; kalau belum ada data baru → skip
;   ; CLR  R22             ; clear flag setelah diproses
;   ; --- SAMPAI SINI ---
;
;   Konfirmasi ke Peran 3 apakah flag diperlukan atau langsung RCALL.
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; String literal pendek untuk label di baris 0
; Disimpan di Flash, diakses dengan LPM
_str_t_colon:   .ascii "T:"
                .byte 0
_str_a_colon:   .ascii "A:"
                .byte 0
_str_hz:        .ascii " Hz"
                .byte 0
_str_spaces:    .ascii "   "
                .byte 0

; =============================================================================
; UPDATE_DISPLAY
; Deskripsi : Update seluruh tampilan LCD berdasarkan input dari Peran 3.
;             Tidak menggunakan LCD_CLEAR — overwrite langsung untuk
;             menghindari flicker (refresh ~6-7x/detik dari Peran 1).
;
; Input     : R25:R24 = Hz aktual (dari Peran 3, sudah di R25:R24)
;             R23     = index senar target (0–5)
; Output    : Tidak ada
; Modifikasi: Semua register di-PUSH/POP — aman
; =============================================================================
UPDATE_DISPLAY:
    PUSH R16
    PUSH R17
    PUSH R23
    PUSH R24
    PUSH R25
    PUSH ZH
    PUSH ZL

    ; =========================================================
    ; BARIS 0: "T:A2   A:110 Hz "
    ; =========================================================

    ; --- Posisi kolom 0: print "T:" ---
    LDI  R16, 0                ; baris 0
    LDI  R17, 0                ; kolom 0
    RCALL LCD_GOTOXY

    LDI  ZH, hi8(_str_t_colon)
    LDI  ZL, lo8(_str_t_colon)
    RCALL LCD_STRING            ; print "T:"

    ; --- Kolom 2: print nama nada TARGET ---
    ; (cursor otomatis di kolom 2 setelah print "T:")
    ; [FIX BUG #2] GET_TARGET_NAME tidak pernah didefinisikan di mana pun.
    ; Fungsi yang setara adalah GET_TARGET_BOUNDS (mapping.S): mengembalikan
    ; Z ke pointer nama nada target di Flash. R18-R21 (bounds) tidak dipakai di sini.
    RCALL GET_TARGET_BOUNDS     ; Z = pointer nama target (R18-R21 bounds, diabaikan)
    RCALL LCD_STRING            ; print "A2" / "E2" / dll

    ; --- Kolom 4–6: print "   " (3 spasi separator) ---
    ; Nama nada max 3 karakter (misal "F#2"), cursor di kolom 5
    ; Kita set eksplisit ke kolom 4 untuk keamanan
    LDI  R16, 0
    LDI  R17, 4
    RCALL LCD_GOTOXY

    LDI  ZH, hi8(_str_spaces)
    LDI  ZL, lo8(_str_spaces)
    RCALL LCD_STRING            ; print "   "

    ; --- Kolom 7: print "A:" ---
    LDI  R16, 0
    LDI  R17, 7
    RCALL LCD_GOTOXY

    LDI  ZH, hi8(_str_a_colon)
    LDI  ZL, lo8(_str_a_colon)
    RCALL LCD_STRING            ; print "A:"

    ; --- Kolom 9: print Hz aktual 3 digit ---
    LDI  R16, 0
    LDI  R17, 9
    RCALL LCD_GOTOXY
    RCALL PRINT_HZ              ; print "082" / "110" / "330"

    ; --- Kolom 12: print " Hz" ---
    LDI  R16, 0
    LDI  R17, 12
    RCALL LCD_GOTOXY

    LDI  ZH, hi8(_str_hz)
    LDI  ZL, lo8(_str_hz)
    RCALL LCD_STRING            ; print " Hz"

    ; --- Kolom 15: spasi akhir (bersihkan sisa karakter) ---
    LDI  R16, 0
    LDI  R17, 15
    RCALL LCD_GOTOXY
    LDI  R16, ' '
    RCALL LCD_CHAR

    ; =========================================================
    ; BARIS 1: Status message "TOO LOOSE " / "NICE      " / "TOO TIGHT "
    ; =========================================================

    ; Set cursor ke baris 1 kolom 0
    LDI  R16, 1
    LDI  R17, 0
    RCALL LCD_GOTOXY

    ; Dapatkan pointer status string
    RCALL GET_STATUS            ; Z = pointer ke STR_TOO_LOOSE/NICE/TOO_TIGHT
    RCALL LCD_STRING            ; print status (sudah dipadding 10 karakter)

    ; Bersihkan sisa kolom 10–15 dengan spasi
    ; (antisipasi kalau string sebelumnya lebih panjang)
    LDI  R16, 1
    LDI  R17, 10
    RCALL LCD_GOTOXY
    LDI  R16, ' '
    RCALL LCD_CHAR
    LDI  R16, ' '
    RCALL LCD_CHAR
    LDI  R16, ' '
    RCALL LCD_CHAR
    LDI  R16, ' '
    RCALL LCD_CHAR
    LDI  R16, ' '
    RCALL LCD_CHAR
    LDI  R16, ' '
    RCALL LCD_CHAR

    POP  ZL
    POP  ZH
    POP  R25
    POP  R24
    POP  R23
    POP  R17
    POP  R16
    RET

; =============================================================================
; DISPLAY_STARTUP  [OPSIONAL]
; Deskripsi : Tampilkan pesan startup saat LCD pertama kali menyala.
;             Dipanggil sekali setelah LCD_INIT di bagian RESET.
;             Peran 3 bisa panggil ini atau skip sesuai kebutuhan.
;
;             Output LCD:
;             +----------------+
;             |  Audio Tuner   |
;             | Initializing.. |
;             +----------------+
;
; Input     : Tidak ada
; Output    : Tidak ada
; =============================================================================
_str_startup1: .ascii "  Audio Tuner   "
               .byte 0
_str_startup2: .ascii " Initializing.. "
               .byte 0

DISPLAY_STARTUP:
    PUSH R16
    PUSH R17
    PUSH ZH
    PUSH ZL

    LDI  R16, 0
    LDI  R17, 0
    RCALL LCD_GOTOXY

    LDI  ZH, hi8(_str_startup1)
    LDI  ZL, lo8(_str_startup1)
    RCALL LCD_STRING

    LDI  R16, 1
    LDI  R17, 0
    RCALL LCD_GOTOXY

    LDI  ZH, hi8(_str_startup2)
    LDI  ZL, lo8(_str_startup2)
    RCALL LCD_STRING

    ; [FIX BUG #7] Delay ~2 detik @ 16MHz
    ; LCD_DELAY_LONG ≈ 12.2ms (255×255×3 siklus / 16MHz)
    ; 164 × 12.2ms ≈ 2000ms = 2 detik
    ; (sebelumnya hanya 5× ≈ 61ms — terlalu cepat untuk terbaca)
    ; R16 sudah di-PUSH di awal fungsi, aman dipakai sebagai counter
    LDI  R16, 164
_startup_wait:
    RCALL LCD_DELAY_LONG
    DEC  R16
    BRNE _startup_wait

    POP  ZL
    POP  ZH
    POP  R17
    POP  R16
    RET

; =============================================================================
; RINGKASAN PUBLIC API PERAN 2 (untuk referensi Peran 3):
;
; Wajib dipanggil di RESET (sekali):
;   RCALL LCD_INIT
;   RCALL DISPLAY_STARTUP    ; opsional
;
; Dipanggil di MAIN_LOOP (tiap data baru):
;   ; Pastikan R25, R24, R23 sudah diisi Peran 3
;   RCALL UPDATE_DISPLAY
;
; Tidak ada fungsi lain yang perlu dipanggil dari main.S.
; =============================================================================