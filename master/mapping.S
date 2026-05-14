; =============================================================================
; FILE: mapping.S
; PERAN: 2 - Pengembang Antarmuka & Logika Pemetaan
; DESKRIPSI: Logika pencarian nada dan penentuan status tuning
;
; DEPENDENSI:
;   - lcd_i2c.S      (TWI primitives)
;   - lcd_driver.S   (LCD functions)
;   - lookup_table.S (NOTE_TABLE, GUITAR_STRINGS, konstanta)
;   - bcd_ascii.S    (PRINT_HZ)
;   Semua harus di-#include SEBELUM file ini
;
; FUNGSI PUBLIK:
;   FIND_NOTE   → cari nada aktual dari R25:R24, hasil di R26 (index) dan Z
;   GET_STATUS  → tentukan TOO LOOSE / NICE / TOO TIGHT
;                 berdasarkan Hz aktual vs target senar
;
; ALUR KERJA:
;   R25:R24 (Hz aktual) + R23 (index senar target)
;       ↓
;   FIND_NOTE  → cari di NOTE_TABLE → R26 = index nada aktual
;       ↓
;   GET_STATUS → bandingkan Hz aktual vs batas target
;             → Z = pointer ke string status (TOO LOOSE/NICE/TOO TIGHT)
;
; STRUKTUR NOTE_TABLE (dari lookup_table.S, 8 byte per entry):
;   Offset +0 : batas_bawah low byte
;   Offset +1 : batas_bawah high byte
;   Offset +2 : batas_atas low byte
;   Offset +3 : batas_atas high byte
;   Offset +4 : ptr_nama low byte
;   Offset +5 : ptr_nama high byte
;   Offset +6 : padding (0x00)
;   Offset +7 : padding (0x00)
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; =============================================================================
; FIND_NOTE
; Deskripsi : Linear search di NOTE_TABLE untuk menemukan nada
;             yang range-nya mencakup nilai Hz aktual di R25:R24
;
; Input     : R25:R24 = Hz aktual (dari Peran 3)
; Output    : R26     = index nada di NOTE_TABLE (0–24)
;                       0xFF jika tidak ditemukan (out of range)
;             Z       = pointer ke nama nada di Flash (string null-terminated)
;                       menunjuk ke STR_UNKNOWN jika tidak ditemukan
; Modifikasi: R16–R21, R26, ZH:ZL (di-PUSH/POP kecuali output R26 dan Z)
; =============================================================================
FIND_NOTE:
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R19
    PUSH R20
    PUSH R21

    ; Inisialisasi Z ke awal NOTE_TABLE
    LDI  ZH, hi8(NOTE_TABLE)
    LDI  ZL, lo8(NOTE_TABLE)

    CLR  R26                    ; R26 = index counter, mulai dari 0

_find_loop:
    ; Cek apakah sudah melewati semua 25 nada
    CPI  R26, NOTE_COUNT        ; NOTE_COUNT = 25
    BREQ _find_not_found        ; sudah habis → tidak ditemukan

    ; Baca batas_bawah dari Flash (2 byte, little-endian)
    LPM  R18, Z+                ; R18 = batas_bawah low byte
    LPM  R19, Z+                ; R19 = batas_bawah high byte

    ; Baca batas_atas dari Flash (2 byte)
    LPM  R20, Z+                ; R20 = batas_atas low byte
    LPM  R21, Z+                ; R21 = batas_atas high byte

    ; Baca ptr_nama dari Flash (2 byte) — simpan dulu di R16:R17
    LPM  R16, Z+                ; R16 = ptr_nama low byte
    LPM  R17, Z+                ; R17 = ptr_nama high byte

    ; Skip padding (2 byte)
    LPM  R0,  Z+                ; buang padding byte 1
    LPM  R0,  Z+                ; buang padding byte 2
    ; Z sekarang menunjuk ke entry berikutnya (sudah +8 dari awal entry)

    ; --- Cek: Hz aktual >= batas_bawah? ---
    ; Bandingkan R25:R24 dengan R19:R18
    ; Caranya: hitung R25:R24 - R19:R18, cek carry
    MOV  R0,  R24
    SUB  R0,  R18               ; low byte
    MOV  R0,  R25
    SBC  R0,  R19               ; high byte dengan borrow
    BRCS _find_next             ; carry set → Hz < batas_bawah → coba entry berikut

    ; --- Cek: Hz aktual <= batas_atas? ---
    ; Bandingkan R21:R20 dengan R25:R24
    ; Caranya: hitung R21:R20 - R25:R24, cek carry
    MOV  R0,  R20
    SUB  R0,  R24               ; low byte
    MOV  R0,  R21
    SBC  R0,  R25               ; high byte dengan borrow
    BRCS _find_next             ; carry set → Hz > batas_atas → coba entry berikut

    ; --- DITEMUKAN ---
    ; Set Z ke pointer nama nada
    MOV  ZL, R16
    MOV  ZH, R17
    RJMP _find_done

_find_next:
    INC  R26                    ; index++
    RJMP _find_loop             ; coba entry berikutnya

_find_not_found:
    LDI  R26, 0xFF              ; flag tidak ditemukan
    LDI  ZH, hi8(STR_UNKNOWN)
    LDI  ZL, lo8(STR_UNKNOWN)

_find_done:
    POP  R21
    POP  R20
    POP  R19
    POP  R18
    POP  R17
    POP  R16
    RET

; =============================================================================
; GET_TARGET_BOUNDS
; Deskripsi : Ambil batas bawah dan atas dari nada TARGET (dari R23)
;             Resolve R23 → index NOTE_TABLE → baca batas dari Flash
;
; Input     : R23 = index senar (0–5), dari Peran 3
; Output    : R18:R19 = batas_bawah target (R18=low, R19=high)
;             R20:R21 = batas_atas target  (R20=low, R21=high)
;             Z       = pointer ke nama nada target di Flash
; Modifikasi: R16, R17 (di-PUSH/POP)
; =============================================================================
GET_TARGET_BOUNDS:
    PUSH R16
    PUSH R17

    ; Step 1: Resolve R23 → index NOTE_TABLE via GUITAR_STRINGS
    LDI  ZH, hi8(GUITAR_STRINGS)
    LDI  ZL, lo8(GUITAR_STRINGS)

    ; Tambah offset R23 ke Z
    ADD  ZL, R23
    CLR  R16
    ADC  ZH, R16                ; handle carry dari ZL

    LPM  R16, Z                 ; R16 = index NOTE_TABLE (0,5,10,15,19,24)

    ; Step 2: Hitung alamat entry di NOTE_TABLE
    ; Alamat = NOTE_TABLE + (R16 × NOTE_ENTRY_SIZE)
    ; NOTE_ENTRY_SIZE = 8
    ; Kita shift kiri 3x untuk ×8
    LSL  R16                    ; ×2
    LSL  R16                    ; ×4
    LSL  R16                    ; ×8 → offset dalam byte

    LDI  ZH, hi8(NOTE_TABLE)
    LDI  ZL, lo8(NOTE_TABLE)
    ADD  ZL, R16
    CLR  R17
    ADC  ZH, R17                ; Z = NOTE_TABLE + offset

    ; Step 3: Baca data entry target dari Flash
    LPM  R18, Z+                ; batas_bawah low
    LPM  R19, Z+                ; batas_bawah high
    LPM  R20, Z+                ; batas_atas low
    LPM  R21, Z+                ; batas_atas high
    LPM  R16, Z+                ; ptr_nama low
    LPM  R17, Z+                ; ptr_nama high

    ; Set Z ke nama nada target
    MOV  ZL, R16
    MOV  ZH, R17

    POP  R17
    POP  R16
    RET

; =============================================================================
; GET_STATUS
; Deskripsi : Tentukan status tuning berdasarkan Hz aktual vs target senar
;             Tiga kondisi: TOO LOOSE, NICE, TOO TIGHT
;
; Input     : R25:R24 = Hz aktual
;             R23     = index senar target (0–5)
; Output    : Z = pointer ke string status di Flash:
;                 → STR_TOO_LOOSE jika Hz aktual < batas_bawah target
;                 → STR_NICE      jika Hz aktual dalam range target
;                 → STR_TOO_TIGHT jika Hz aktual > batas_atas target
; Modifikasi: R16–R21 (di-PUSH/POP), Z adalah output
; =============================================================================
GET_STATUS:
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R19
    PUSH R20
    PUSH R21

    ; Ambil exact Target Hz dari TARGET_EXACT_HZ berdasarkan R23
    LDI  ZH, hi8(TARGET_EXACT_HZ)
    LDI  ZL, lo8(TARGET_EXACT_HZ)
    MOV  R16, R23
    LSL  R16
    ADD  ZL, R16
    CLR  R17
    ADC  ZH, R17
    LPM  R18, Z+             ; R18 = exact Hz low
    LPM  R19, Z              ; R19 = exact Hz high

    ; --- Batas bawah = exact Hz - 2 ---
    MOV  R20, R18
    MOV  R21, R19
    SUBI R18, 2
    SBCI R19, 0              ; R18:R19 = batas bawah

    ; --- Batas atas = exact Hz + 2 ---
    SUBI R20, -2
    SBCI R21, -1             ; R20:R21 = batas atas

    ; --- Cek TOO LOOSE: Hz aktual < batas_bawah? ---
    ; Hitung R25:R24 - R19:R18, cek carry
    MOV  R16, R24
    SUB  R16, R18               ; low byte
    MOV  R16, R25
    SBC  R16, R19               ; high byte
    BRCS _status_too_loose      ; carry → Hz < batas_bawah

    ; --- Cek TOO TIGHT: Hz aktual > batas_atas? ---
    ; Hitung R21:R20 - R25:R24, cek carry
    MOV  R16, R20
    SUB  R16, R24               ; low byte
    MOV  R16, R21
    SBC  R16, R25               ; high byte
    BRCS _status_too_tight      ; carry → Hz > batas_atas

    ; --- NICE: dalam range ---
_status_nice:
    LDI  ZH, hi8(STR_NICE)
    LDI  ZL, lo8(STR_NICE)
    RJMP _status_done

_status_too_loose:
    LDI  ZH, hi8(STR_TOO_LOOSE)
    LDI  ZL, lo8(STR_TOO_LOOSE)
    RJMP _status_done

_status_too_tight:
    LDI  ZH, hi8(STR_TOO_TIGHT)
    LDI  ZL, lo8(STR_TOO_TIGHT)

_status_done:
    POP  R21
    POP  R20
    POP  R19
    POP  R18
    POP  R17
    POP  R16
    RET

; =============================================================================
; CATATAN UNTUK DISPLAY.S:
;
; Urutan pemanggilan yang benar di display.S:
;
;   ; 1. Dapatkan nama nada AKTUAL
;   RCALL FIND_NOTE         ; Z = ptr nama aktual, R26 = index (0xFF=unknown)
;   ; simpan Z ke SRAM kalau perlu (karena GET_STATUS akan timpa Z)
;
;   ; 2. Dapatkan status tuning
;   RCALL GET_STATUS        ; Z = ptr string status
;   ; simpan Z ke SRAM
;
;   ; 3. Dapatkan nama nada TARGET (untuk baris 1 LCD)
;   RCALL GET_TARGET_BOUNDS ; Z = ptr nama target
;
;   Semua Z pointer yang dibutuhkan lalu di-render oleh display.S
; =============================================================================