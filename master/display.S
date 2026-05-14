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

; String literal pendek untuk label di baris 0 & 1
; Disimpan di Flash, diakses dengan LPM
_str_hz_space:  .ascii "Hz "
                .byte 0
_str_hz_clear:  .ascii "Hz       "
                .byte 0

; =============================================================================
; UPDATE_DISPLAY
; Deskripsi : Update seluruh tampilan LCD berdasarkan input dari Peran 3.
;             Baris 0: "{Target_Name} {Target_Hz}Hz {Status}" (mis. "E2 082Hz loosen ")
;             Baris 1: "{Current_Name} {Current_Hz}Hz      " (mis. "E#2 083Hz      ")
;
; Input     : R25:R24 = Hz aktual (dari Peran 3, sudah di R25:R24)
;             R23     = index senar target (0-5)
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
    PUSH R20
    PUSH R21

    ; =========================================================
    ; BARIS 0: "{T_NAME} {T_HZ}Hz {STATUS}"
    ; =========================================================

    ; --- Kolom 0: Target Name ---
    LDI  R16, 0
    LDI  R17, 0
    RCALL LCD_GOTOXY
    RCALL GET_TARGET_BOUNDS     ; Z = pointer nama target (pasti 2 chars, mis. "E2")
    RCALL LCD_STRING

    ; --- Kolom 2: Spasi khusus ---
    ; Nama target selalu 2 char, jadi kolom 2 selalu dikosongkan
    LDI  R16, 0
    LDI  R17, 2
    RCALL LCD_GOTOXY
    LDI  R16, ' '
    RCALL LCD_CHAR

    ; --- Kolom 3: Target Hz ---
    LDI  R16, 0
    LDI  R17, 3
    RCALL LCD_GOTOXY
    
    ; Ambil Target Hz dari array TARGET_EXACT_HZ berdasarkan index str R23
    LDI  ZH, hi8(TARGET_EXACT_HZ)
    LDI  ZL, lo8(TARGET_EXACT_HZ)
    ; offset = R23 * 2
    MOV  R16, R23
    LSL  R16
    ADD  ZL, R16
    CLR  R16
    ADC  ZH, R16
    LPM  R20, Z+                 ; Target Hz Low Byte
    LPM  R21, Z                  ; Target Hz High Byte
    
    ; Ganti R25:R24 secara sementara untuk memanggil PRINT_HZ
    MOV  R16, R24
    MOV  R17, R25
    MOV  R24, R20
    MOV  R25, R21
    RCALL PRINT_HZ
    
    ; Kembalikan R25:R24 aktual (Current Hz) untuk diproses di bawah
    MOV  R24, R16
    MOV  R25, R17

    ; --- Kolom 6: "Hz " ---
    LDI  R16, 0
    LDI  R17, 6
    RCALL LCD_GOTOXY
    LDI  ZH, hi8(_str_hz_space)
    LDI  ZL, lo8(_str_hz_space)
    RCALL LCD_STRING

    ; --- Kolom 9: Status Message ---
    LDI  R16, 0
    LDI  R17, 9
    RCALL LCD_GOTOXY
    RCALL GET_STATUS            ; Z = pointer ke status (sudah dipadding 7 char)
    RCALL LCD_STRING

    ; =========================================================
    ; BARIS 1: "{CURRENT_NAME} {CURRENT_HZ}Hz       "
    ; =========================================================

    ; --- Antisipasi nama 2 char vs 3 char (mis. E2 vs E#2) ---
    ; Clear kolom 2 dan 3 untuk mencegah residual ghost karakter "2" atau spasi
    LDI  R16, 1
    LDI  R17, 2
    RCALL LCD_GOTOXY
    LDI  R16, ' '
    RCALL LCD_CHAR
    LDI  R16, 1
    LDI  R17, 3
    RCALL LCD_GOTOXY
    LDI  R16, ' '
    RCALL LCD_CHAR

    ; --- Kolom 0: Current Note Name ---
    LDI  R16, 1
    LDI  R17, 0
    RCALL LCD_GOTOXY
    
    ; Cari Note berdasarkan Hz Aktual di R25:R24
    RCALL FIND_NOTE             ; Z = pointer nama nada aktual, R26 = index
    RCALL LCD_STRING

    ; --- Kolom 4: Current Hz ---
    LDI  R16, 1
    LDI  R17, 4
    RCALL LCD_GOTOXY
    RCALL PRINT_HZ              ; R25:R24 aktual (Current Hz)

    ; --- Kolom 7: "Hz       " (juga sekalian bersihkan sisa layar) ---
    LDI  R16, 1
    LDI  R17, 7
    RCALL LCD_GOTOXY
    LDI  ZH, hi8(_str_hz_clear)
    LDI  ZL, lo8(_str_hz_clear)
    RCALL LCD_STRING

    POP  R21
    POP  R20
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

    ; [FIX PROTEUS] Kurangi delay startup dari 164 (~2 detik) menjadi 10 (~120ms).
    ; Proteus seringkali berjalan jauh lebih lambat dari waktu nyata (Real Time),
    ; sehingga delay 2 detik bisa terasa seperti macet selamanya.
    LDI  R16, 82
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