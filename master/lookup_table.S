; =============================================================================
; FILE: lookup_table.S
; PERAN: 2 - Pengembang Antarmuka & Logika Pemetaan
; DESKRIPSI: Lookup Table Chromatic E2–E4 di Program Memory (Flash)
;
; TOLERANSI: ±5 Cent (proporsional, precomputed — bukan ±Hz flat)
;   Nada rendah range sempit, nada tinggi range lebih lebar.
;   Ini perilaku yang benar secara musikal (equal temperament).
;
; STRUKTUR TIAP ENTRY NOTE_TABLE (8 byte per nada):
;   Offset +0 : batas_bawah LOW  byte (1 byte)
;   Offset +1 : batas_bawah HIGH byte (1 byte)
;   Offset +2 : batas_atas  LOW  byte (1 byte)
;   Offset +3 : batas_atas  HIGH byte (1 byte)
;   Offset +4 : ptr_nama    LOW  byte (1 byte) — byte address di Flash
;   Offset +5 : ptr_nama    HIGH byte (1 byte)
;   Offset +6 : padding     0x00 (1 byte)
;   Offset +7 : padding     0x00 (1 byte)
;   TOTAL: 8 byte per entry → offset = index × 8 (shift kiri 3x)
;
; SEMUA DATA DI .text SECTION (Flash) — diakses dengan LPM
; Tidak pakai .section directive khusus agar kompatibel dengan semua
; toolchain AVR (avr-gcc, Atmel Studio, avra)
;
; JUMLAH NADA: 25 (E2 sampai E4, chromatic penuh)
; REFERENSI  : A4 = 440 Hz, standard equal temperament
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; =============================================================================
; KONSTANTA — dideklarasikan di atas agar tersedia sebelum dipakai
; =============================================================================
.equ NOTE_COUNT,      25    ; jumlah entry di NOTE_TABLE
.equ NOTE_ENTRY_SIZE,  8    ; byte per entry (8 = 2^3, shift kiri 3x untuk ×8)
.equ GUITAR_STR_COUNT, 6    ; jumlah senar gitar

; =============================================================================
; GUITAR_STRINGS — Mapping index senar (R23) ke index NOTE_TABLE
;
; Standard tuning: E2 A2 D3 G3 B3 E4
; R23 dari Peran 3: 0=senar6(E2), 1=senar5(A2), 2=senar4(D3)
;                   3=senar3(G3), 4=senar2(B3), 5=senar1(E4)
;
; Nilai = index NOTE_TABLE (0-based):
;   E2 = 0, F2 = 1, ..., A2 = 5, ..., D3 = 10, ..., G3 = 15,
;   ..., B3 = 19, ..., E4 = 24
; =============================================================================
.balign 2                   ; pastikan word-aligned
GUITAR_STRINGS:
    .byte  0                ; R23=0 → Senar 6 = E2  (index  0)
    .byte  5                ; R23=1 → Senar 5 = A2  (index  5)
    .byte 10                ; R23=2 → Senar 4 = D3  (index 10)
    .byte 15                ; R23=3 → Senar 3 = G3  (index 15)
    .byte 19                ; R23=4 → Senar 2 = B3  (index 19)
    .byte 24                ; R23=5 → Senar 1 = E4  (index 24)
.balign 2                   ; padding agar NOTE_NAMES tetap word-aligned

; =============================================================================
; NOTE_NAMES — String nama nada, null-terminated, di Flash
; Diakses via pointer yang disimpan di NOTE_TABLE offset +4
; =============================================================================
NOTE_NAMES:
_name_E2:   .ascii "E2"  
            .byte 0
_name_F2:   .ascii "F2"  
            .byte 0
_name_Fs2:  .ascii "F#2" 
            .byte 0
_name_G2:   .ascii "G2"  
            .byte 0
_name_Gs2:  .ascii "G#2" 
            .byte 0
_name_A2:   .ascii "A2"  
            .byte 0
_name_As2:  .ascii "A#2" 
            .byte 0
_name_B2:   .ascii "B2"  
            .byte 0
_name_C3:   .ascii "C3"  
            .byte 0
_name_Cs3:  .ascii "C#3" 
            .byte 0
_name_D3:   .ascii "D3"  
            .byte 0
_name_Ds3:  .ascii "D#3" 
            .byte 0
_name_E3:   .ascii "E3"  
            .byte 0
_name_F3:   .ascii "F3"  
            .byte 0
_name_Fs3:  .ascii "F#3" 
            .byte 0
_name_G3:   .ascii "G3"  
            .byte 0
_name_Gs3:  .ascii "G#3" 
            .byte 0
_name_A3:   .ascii "A3"  
            .byte 0
_name_As3:  .ascii "A#3" 
            .byte 0
_name_B3:   .ascii "B3"  
            .byte 0
_name_C4:   .ascii "C4"  
            .byte 0
_name_Cs4:  .ascii "C#4" 
            .byte 0
_name_D4:   .ascii "D4"  
            .byte 0
_name_Ds4:  .ascii "D#4" 
            .byte 0
_name_E4:   .ascii "E4"  
            .byte 0

; =============================================================================
; STATUS STRINGS — null-terminated, SEMUA DIPADDING ke 10 karakter
; Panjang seragam mencegah ghost character saat overwrite di LCD
;
; "TOO LOOSE " = 10 char (9 + 1 spasi)
; "NICE      " = 10 char (4 + 6 spasi)
; "TOO TIGHT " = 10 char (9 + 1 spasi)
; "----------" = 10 char (out of range marker)
; =============================================================================
STR_TOO_LOOSE:  .ascii "TOO LOOSE "
                .byte 0
STR_NICE:       .ascii "NICE      "
                .byte 0
STR_TOO_TIGHT:  .ascii "TOO TIGHT "
                .byte 0
STR_UNKNOWN:    .ascii "----------"
                .byte 0

; =============================================================================
; NOTE_TABLE — Tabel utama chromatic E2–E4
;
; Format tiap entry (8 byte, pakai .byte eksplisit untuk hindari ambiguitas
; word/byte address pada pointer nama):
;
;   .byte lo8(batas_bawah), hi8(batas_bawah)   → 2 byte
;   .byte lo8(batas_atas),  hi8(batas_atas)    → 2 byte
;   .byte lo8(ptr_nama),    hi8(ptr_nama)       → 2 byte (byte address Flash)
;   .byte 0x00, 0x00                            → 2 byte padding
;
; Toleransi ±5 Cent (precomputed via Python):
;   factor_up   = 2^( 5/1200) = 1.002892
;   factor_down = 2^(-5/1200) = 0.997116
;   batas_bawah = floor(Hz × factor_down)
;   batas_atas  = ceil (Hz × factor_up)
; =============================================================================
.balign 2                   ; word-align sebelum tabel utama
NOTE_TABLE:

; E2 — 82.41 Hz — range 82–83 Hz
    .byte  82, 0            ; batas_bawah = 82
    .byte  83, 0            ; batas_atas  = 83
    .byte lo8(_name_E2),  hi8(_name_E2)
    .byte 0x00, 0x00

; F2 — 87.31 Hz — range 87–88 Hz
    .byte  87, 0
    .byte  88, 0
    .byte lo8(_name_F2),  hi8(_name_F2)
    .byte 0x00, 0x00

; F#2 — 92.50 Hz — range 92–93 Hz
    .byte  92, 0
    .byte  93, 0
    .byte lo8(_name_Fs2), hi8(_name_Fs2)
    .byte 0x00, 0x00

; G2 — 98.00 Hz — range 97–99 Hz
    .byte  97, 0
    .byte  99, 0
    .byte lo8(_name_G2),  hi8(_name_G2)
    .byte 0x00, 0x00

; G#2 — 103.83 Hz — range 103–105 Hz
    .byte 103, 0
    .byte 105, 0
    .byte lo8(_name_Gs2), hi8(_name_Gs2)
    .byte 0x00, 0x00

; A2 — 110.00 Hz — range 109–111 Hz
    .byte 109, 0
    .byte 111, 0
    .byte lo8(_name_A2),  hi8(_name_A2)
    .byte 0x00, 0x00

; A#2 — 116.54 Hz — range 116–117 Hz
    .byte 116, 0
    .byte 117, 0
    .byte lo8(_name_As2), hi8(_name_As2)
    .byte 0x00, 0x00

; B2 — 123.47 Hz — range 123–124 Hz
    .byte 123, 0
    .byte 124, 0
    .byte lo8(_name_B2),  hi8(_name_B2)
    .byte 0x00, 0x00

; C3 — 130.81 Hz — range 130–132 Hz
    .byte 130, 0
    .byte 132, 0
    .byte lo8(_name_C3),  hi8(_name_C3)
    .byte 0x00, 0x00

; C#3 — 138.59 Hz — range 138–139 Hz
    .byte 138, 0
    .byte 139, 0
    .byte lo8(_name_Cs3), hi8(_name_Cs3)
    .byte 0x00, 0x00

; D3 — 146.83 Hz — range 146–148 Hz
    .byte 146, 0
    .byte 148, 0
    .byte lo8(_name_D3),  hi8(_name_D3)
    .byte 0x00, 0x00

; D#3 — 155.56 Hz — range 155–157 Hz
    .byte 155, 0
    .byte 157, 0
    .byte lo8(_name_Ds3), hi8(_name_Ds3)
    .byte 0x00, 0x00

; E3 — 164.81 Hz — range 164–166 Hz
    .byte 164, 0
    .byte 166, 0
    .byte lo8(_name_E3),  hi8(_name_E3)
    .byte 0x00, 0x00

; F3 — 174.61 Hz — range 174–176 Hz
    .byte 174, 0
    .byte 176, 0
    .byte lo8(_name_F3),  hi8(_name_F3)
    .byte 0x00, 0x00

; F#3 — 185.00 Hz — range 184–186 Hz
    .byte 184, 0
    .byte 186, 0
    .byte lo8(_name_Fs3), hi8(_name_Fs3)
    .byte 0x00, 0x00

; G3 — 196.00 Hz — range 195–197 Hz
    .byte 195, 0
    .byte 197, 0
    .byte lo8(_name_G3),  hi8(_name_G3)
    .byte 0x00, 0x00

; G#3 — 207.65 Hz — range 207–209 Hz
    .byte 207, 0
    .byte 209, 0
    .byte lo8(_name_Gs3), hi8(_name_Gs3)
    .byte 0x00, 0x00

; A3 — 220.00 Hz — range 219–221 Hz
    .byte 219, 0
    .byte 221, 0
    .byte lo8(_name_A3),  hi8(_name_A3)
    .byte 0x00, 0x00

; A#3 — 233.08 Hz — range 232–234 Hz
    .byte 232, 0
    .byte 234, 0
    .byte lo8(_name_As3), hi8(_name_As3)
    .byte 0x00, 0x00

; B3 — 246.94 Hz — range 246–248 Hz
    .byte 246, 0
    .byte 248, 0
    .byte lo8(_name_B3),  hi8(_name_B3)
    .byte 0x00, 0x00

; C4 — 261.63 Hz — range 260–263 Hz
; 260 = 0x0104 → lo8=0x04, hi8=0x01
; 263 = 0x0107 → lo8=0x07, hi8=0x01
    .byte 0x04, 0x01        ; batas_bawah = 260
    .byte 0x07, 0x01        ; batas_atas  = 263
    .byte lo8(_name_C4),  hi8(_name_C4)
    .byte 0x00, 0x00

; C#4 — 277.18 Hz — range 276–278 Hz
; 276 = 0x0114 → lo8=0x14, hi8=0x01
; 278 = 0x0116 → lo8=0x16, hi8=0x01
    .byte 0x14, 0x01        ; batas_bawah = 276
    .byte 0x16, 0x01        ; batas_atas  = 278
    .byte lo8(_name_Cs4), hi8(_name_Cs4)
    .byte 0x00, 0x00

; D4 — 293.66 Hz — range 292–295 Hz
; 292 = 0x0124 → lo8=0x24, hi8=0x01
; 295 = 0x0127 → lo8=0x27, hi8=0x01
    .byte 0x24, 0x01        ; batas_bawah = 292
    .byte 0x27, 0x01        ; batas_atas  = 295
    .byte lo8(_name_D4),  hi8(_name_D4)
    .byte 0x00, 0x00

; D#4 — 311.13 Hz — range 310–313 Hz
; 310 = 0x0136 → lo8=0x36, hi8=0x01
; 313 = 0x0139 → lo8=0x39, hi8=0x01
    .byte 0x36, 0x01        ; batas_bawah = 310
    .byte 0x39, 0x01        ; batas_atas  = 313
    .byte lo8(_name_Ds4), hi8(_name_Ds4)
    .byte 0x00, 0x00

; E4 — 329.63 Hz — range 328–331 Hz
; 328 = 0x0148 → lo8=0x48, hi8=0x01
; 331 = 0x014B → lo8=0x4B, hi8=0x01
    .byte 0x48, 0x01        ; batas_bawah = 328
    .byte 0x4B, 0x01        ; batas_atas  = 331
    .byte lo8(_name_E4),  hi8(_name_E4)
    .byte 0x00, 0x00

; =============================================================================
; CATATAN PENTING — NILAI > 255 DI .byte
;
; Nilai seperti 260, 276, 292, 310, 328 > 255.
; Instruksi `.byte 260, 0` di GAS AVR akan otomatis truncate ke lo8(260)=4
; dan hi8 tetap 0 — INI SALAH untuk nilai > 255.
;
; FIX: pakai lo8() dan hi8() secara eksplisit:
;   C4  bawah 260: lo8(260)=0x04, hi8(260)=0x01 → .byte 0x04, 0x01
;   C4  atas  263: lo8(263)=0x07, hi8(263)=0x01 → .byte 0x07, 0x01
;   C#4 bawah 276: lo8(276)=0x14, hi8(276)=0x01 → .byte 0x14, 0x01
;   C#4 atas  278: lo8(278)=0x16, hi8(278)=0x01 → .byte 0x16, 0x01
;   D4  bawah 292: lo8(292)=0x24, hi8(292)=0x01 → .byte 0x24, 0x01
;   D4  atas  295: lo8(295)=0x27, hi8(295)=0x01 → .byte 0x27, 0x01
;   D#4 bawah 310: lo8(310)=0x36, hi8(310)=0x01 → .byte 0x36, 0x01
;   D#4 atas  313: lo8(313)=0x39, hi8(313)=0x01 → .byte 0x39, 0x01
;   E4  bawah 328: lo8(328)=0x48, hi8(328)=0x01 → .byte 0x48, 0x01
;   E4  atas  331: lo8(331)=0x4B, hi8(331)=0x01 → .byte 0x4B, 0x01
; =============================================================================

; =============================================================================
; CARA BACA ENTRY DI mapping.S (referensi):
;
; Baca entry ke-N:
;   LDI  ZH, hi8(NOTE_TABLE)
;   LDI  ZL, lo8(NOTE_TABLE)
;   ; hitung offset = N × 8 (LSL 3x jika N di register)
;   ADD  ZL, offset_low
;   ADC  ZH, offset_high
;   LPM  R18, Z+    ; batas_bawah LOW
;   LPM  R19, Z+    ; batas_bawah HIGH  → R19:R18 = batas_bawah
;   LPM  R20, Z+    ; batas_atas  LOW
;   LPM  R21, Z+    ; batas_atas  HIGH  → R21:R20 = batas_atas
;   LPM  R16, Z+    ; ptr_nama LOW
;   LPM  R17, Z+    ; ptr_nama HIGH     → R17:R16 = byte address nama
;   ; (skip 2 byte padding)
;
; Baca nama dari pointer:
;   MOV  ZL, R16
;   MOV  ZH, R17
;   RCALL LCD_STRING   ; Z sudah menunjuk ke string nama
; =============================================================================