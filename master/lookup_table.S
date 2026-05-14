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
; TARGET_EXACT_HZ — Nilai frekuensi referensi aktual (Exact Hz)
; Untuk UI `display.S` pada baris referensi (Tuning String)
; =============================================================================
TARGET_EXACT_HZ:
    .word 82
    .word 110
    .word 147
    .word 196
    .word 247
    .word 330
.balign 2

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
; STATUS STRINGS — null-terminated, SEMUA DIPADDING ke 7 karakter
; Panjang seragam mencegah ghost character saat overwrite di LCD
;
; "loosen " = 7 char
; "nice   " = 7 char
; "tighten" = 7 char
; "-------" = 7 char (out of range marker)
; =============================================================================
STR_TOO_LOOSE:  .ascii "LOOSEN "
                .byte 0
STR_NICE:       .ascii "NICE   "
                .byte 0
STR_TOO_TIGHT:  .ascii "TIGHTEN"
                .byte 0
STR_UNKNOWN:    .ascii "-------"
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

; E2 - 82.41 Hz
    .byte   0, 0
    .byte  84, 0
    .byte lo8(_name_E2),  hi8(_name_E2)
    .byte 0x00, 0x00

; F2 - 87.31 Hz
    .byte  85, 0
    .byte  89, 0
    .byte lo8(_name_F2),  hi8(_name_F2)
    .byte 0x00, 0x00

; F#2 - 92.50 Hz
    .byte  90, 0
    .byte  94, 0
    .byte lo8(_name_Fs2), hi8(_name_Fs2)
    .byte 0x00, 0x00

; G2 - 98.00 Hz
    .byte  95, 0
    .byte 100, 0
    .byte lo8(_name_G2),  hi8(_name_G2)
    .byte 0x00, 0x00

; G#2 - 103.83 Hz
    .byte 101, 0
    .byte 106, 0
    .byte lo8(_name_Gs2), hi8(_name_Gs2)
    .byte 0x00, 0x00

; A2 - 110.00 Hz
    .byte 107, 0
    .byte 112, 0
    .byte lo8(_name_A2),  hi8(_name_A2)
    .byte 0x00, 0x00

; A#2 - 116.54 Hz
    .byte 113, 0
    .byte 119, 0
    .byte lo8(_name_As2), hi8(_name_As2)
    .byte 0x00, 0x00

; B2 - 123.47 Hz
    .byte 120, 0
    .byte 126, 0
    .byte lo8(_name_B2),  hi8(_name_B2)
    .byte 0x00, 0x00

; C3 - 130.81 Hz
    .byte 127, 0
    .byte 134, 0
    .byte lo8(_name_C3),  hi8(_name_C3)
    .byte 0x00, 0x00

; C#3 - 138.59 Hz
    .byte 135, 0
    .byte 142, 0
    .byte lo8(_name_Cs3), hi8(_name_Cs3)
    .byte 0x00, 0x00

; D3 - 146.83 Hz
    .byte 143, 0
    .byte 150, 0
    .byte lo8(_name_D3),  hi8(_name_D3)
    .byte 0x00, 0x00

; D#3 - 155.56 Hz
    .byte 151, 0
    .byte 159, 0
    .byte lo8(_name_Ds3), hi8(_name_Ds3)
    .byte 0x00, 0x00

; E3 - 164.81 Hz
    .byte 160, 0
    .byte 169, 0
    .byte lo8(_name_E3),  hi8(_name_E3)
    .byte 0x00, 0x00

; F3 - 174.61 Hz
    .byte 170, 0
    .byte 179, 0
    .byte lo8(_name_F3),  hi8(_name_F3)
    .byte 0x00, 0x00

; F#3 - 185.00 Hz
    .byte 180, 0
    .byte 189, 0
    .byte lo8(_name_Fs3), hi8(_name_Fs3)
    .byte 0x00, 0x00

; G3 - 196.00 Hz
    .byte 190, 0
    .byte 201, 0
    .byte lo8(_name_G3),  hi8(_name_G3)
    .byte 0x00, 0x00

; G#3 - 207.65 Hz
    .byte 202, 0
    .byte 213, 0
    .byte lo8(_name_Gs3), hi8(_name_Gs3)
    .byte 0x00, 0x00

; A3 - 220.00 Hz
    .byte 214, 0
    .byte 225, 0
    .byte lo8(_name_A3),  hi8(_name_A3)
    .byte 0x00, 0x00

; A#3 - 233.08 Hz
    .byte 226, 0
    .byte 239, 0
    .byte lo8(_name_As3), hi8(_name_As3)
    .byte 0x00, 0x00

; B3 - 246.94 Hz
    .byte 240, 0
    .byte 253, 0
    .byte lo8(_name_B3),  hi8(_name_B3)
    .byte 0x00, 0x00

; C4 - 261.63 Hz
    .byte 254, 0
    .byte lo8(268), hi8(268)
    .byte lo8(_name_C4),  hi8(_name_C4)
    .byte 0x00, 0x00

; C#4 - 277.18 Hz
    .byte lo8(269), hi8(269)
    .byte lo8(284), hi8(284)
    .byte lo8(_name_Cs4), hi8(_name_Cs4)
    .byte 0x00, 0x00

; D4 - 293.66 Hz
    .byte lo8(285), hi8(285)
    .byte lo8(301), hi8(301)
    .byte lo8(_name_D4),  hi8(_name_D4)
    .byte 0x00, 0x00

; D#4 - 311.13 Hz
    .byte lo8(302), hi8(302)
    .byte lo8(319), hi8(319)
    .byte lo8(_name_Ds4), hi8(_name_Ds4)
    .byte 0x00, 0x00

; E4 - 329.63 Hz
    .byte lo8(320), hi8(320)
    .byte lo8(999), hi8(999)
    .byte lo8(_name_E4),  hi8(_name_E4)
    .byte 0x00, 0x00