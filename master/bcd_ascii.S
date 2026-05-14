; =============================================================================
; FILE: bcd_ascii.S
; PERAN: 2 - Pengembang Antarmuka & Logika Pemetaan
; DESKRIPSI: Konverter bilangan biner 16-bit → string ASCII desimal
;            Dipakai untuk menampilkan nilai Hz aktual di LCD
;
; DEPENDENSI: lcd_driver.S harus di-#include SEBELUM file ini
;
; FUNGSI PUBLIK:
;   PRINT_HZ → cetak nilai Hz dari R25:R24 langsung ke LCD
;              format output: "XXX" (3 digit, max 999)
;              cursor harus sudah diset dengan LCD_GOTOXY sebelum RCALL
;
; MENGAPA HANYA 3 DIGIT?
;   Range frekuensi kita E2(82Hz) - E4(330Hz), max 3 digit desimal.
;   Tidak perlu 4 digit → hemat kolom LCD.
;
; ALGORITMA:
;   Bilangan 16-bit dibagi berulang dengan 10 (division by repeated subtraction
;   atau shift — kita pakai metode divide 16-bit karena AVR tidak punya DIV):
;   1. Bagi Hz dengan 100 → dapat digit ratusan
;   2. Sisa bagi 10       → dapat digit puluhan
;   3. Sisa               → digit satuan
;   4. Tiap digit + 0x30  → ASCII
;   5. Kirim ke LCD via LCD_CHAR
;
; REGISTER YANG DIPAKAI INTERNAL:
;   R25:R24 = nilai Hz input (tidak dimodifikasi — di-PUSH/POP)
;   R20     = digit ratusan
;   R21     = digit puluhan
;   R22     = digit satuan
;   R16     = temp untuk LCD_CHAR
;   R18     = temp pembagian
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; =============================================================================
; DIV16_BY_CONST  [INTERNAL MACRO HELPER]
; Karena AVR tidak punya instruksi DIV, kita pakai subrutin pembagian
; 16-bit dengan konstanta via repeated subtraction.
;
; Untuk nilai kita (max 330Hz), repeated subtraction cukup cepat:
;   330 / 100 = maks 3 iterasi → sangat ringan
;   30  / 10  = maks 9 iterasi → masih ringan
; =============================================================================

; =============================================================================
; DIV16_100  [INTERNAL]
; Deskripsi : Bagi R25:R24 dengan 100
;             Hasil bagi → R20 (digit ratusan)
;             Sisa       → R25:R24 (untuk tahap berikutnya)
; Input     : R25:R24 = bilangan yang dibagi
; Output    : R20     = hasil bagi (0–3 untuk range kita)
;             R25:R24 = sisa pembagian
; Modifikasi: R18, R19 (di-PUSH/POP)
; =============================================================================
DIV16_100:
    PUSH R18
    PUSH R19

    CLR  R20                ; hasil bagi = 0

_div100_loop:
    ; Cek apakah R25:R24 >= 100
    ; Caranya: kurangi 100, kalau hasilnya negatif (carry) → berhenti
    LDI  R18, LOW(100)
    LDI  R19, HIGH(100)     ; R19:R18 = 100

    ; Coba kurangi: R25:R24 - 100
    SUB  R24, R18
    SBC  R25, R19           ; kurangi dengan borrow

    BRCS _div100_done       ; kalau carry (hasil negatif) → selesai

    INC  R20                ; hasil bagi++
    RJMP _div100_loop

_div100_done:
    ; Karena kita overdraft (kurang sekali terlalu banyak), kembalikan
    ADD  R24, R18
    ADC  R25, R19           ; sisa = sisa + 100 (batalkan pengurangan terakhir)

    POP  R19
    POP  R18
    RET

; =============================================================================
; DIV16_10  [INTERNAL]
; Deskripsi : Bagi R25:R24 dengan 10
;             Hasil bagi → R21 (digit puluhan)
;             Sisa       → R25:R24 (untuk tahap berikutnya)
; Input     : R25:R24 = sisa dari DIV16_100 (nilai 0–99)
; Output    : R21     = hasil bagi (0–9)
;             R25:R24 = sisa pembagian (0–9)
; Modifikasi: R18, R19 (di-PUSH/POP)
; =============================================================================
DIV16_10:
    PUSH R18
    PUSH R19

    CLR  R21                ; hasil bagi = 0

_div10_loop:
    LDI  R18, LOW(10)
    LDI  R19, HIGH(10)      ; R19:R18 = 10

    SUB  R24, R18
    SBC  R25, R19

    BRCS _div10_done

    INC  R21
    RJMP _div10_loop

_div10_done:
    ; Kembalikan overdraft
    ADD  R24, R18
    ADC  R25, R19

    POP  R19
    POP  R18
    RET

; =============================================================================
; PRINT_HZ
; Deskripsi : Konversi nilai Hz 16-bit ke ASCII dan cetak ke LCD
;             Format output: "XXX" (3 digit, zero-padded)
;             Contoh: 82Hz → "082", 110Hz → "110", 330Hz → "330"
;
;             PERHATIAN: Set posisi cursor dengan LCD_GOTOXY dulu
;             sebelum memanggil fungsi ini.
;
; Input     : R25:R24 = nilai Hz (dari Peran 3, range 0–999)
; Output    : Tidak ada (langsung cetak ke LCD)
; Modifikasi: Semua register di-PUSH/POP — aman dipanggil dari mana saja
; =============================================================================
PRINT_HZ:
    PUSH R16
    PUSH R18
    PUSH R19
    PUSH R20
    PUSH R21
    PUSH R22
    PUSH R24
    PUSH R25

    ; --- Tahap 1: Ekstrak digit ratusan ---
    RCALL DIV16_100         ; R20 = ratusan, R25:R24 = sisa

    ; --- Tahap 2: Ekstrak digit puluhan ---
    RCALL DIV16_10          ; R21 = puluhan, R25:R24 = sisa

    ; --- Tahap 3: Digit satuan = sisa ---
    MOV  R22, R24           ; R22 = satuan (R25 pasti 0 di sini)

    ; --- Tahap 4: Konversi ke ASCII dan print ---
    ; Digit ratusan
    MOV  R16, R20
    ORI  R16, 0x30          ; tambah 0x30 → ASCII ('0'=0x30, '1'=0x31, dst)
    RCALL LCD_CHAR

    ; Digit puluhan
    MOV  R16, R21
    ORI  R16, 0x30
    RCALL LCD_CHAR

    ; Digit satuan
    MOV  R16, R22
    ORI  R16, 0x30
    RCALL LCD_CHAR

    POP  R25
    POP  R24
    POP  R22
    POP  R21
    POP  R20
    POP  R19
    POP  R18
    POP  R16
    RET

; =============================================================================
; PRINT_STR_FLASH  [HELPER PUBLIK]
; Deskripsi : Shortcut print string dari Flash dengan pointer langsung
;             Wrapper atas LCD_STRING agar display.S lebih rapi
;
; Input     : ZH:ZL = pointer ke string di Flash
; Output    : Tidak ada
; Modifikasi: R16, R18 via LCD_STRING (di-PUSH/POP di dalam LCD_STRING)
;             Z register akan berubah setelah selesai (by design)
; =============================================================================
PRINT_STR_FLASH:
    RCALL LCD_STRING        ; langsung delegasi ke LCD_STRING
    RET

; =============================================================================
; CONTOH PENGGUNAAN (jangan hapus komentar ini):
;
; Print Hz aktual di baris 1 kolom 3:
;   LDI  R16, 1             ; baris 1
;   LDI  R17, 3             ; kolom 3
;   RCALL LCD_GOTOXY
;   ; R25:R24 sudah berisi Hz dari Peran 3
;   RCALL PRINT_HZ          ; cetak "110" (kalau Hz=110)
;
; Print string status dari Flash:
;   LDI  ZH, hi8(STR_TOO_LOOSE)
;   LDI  ZL, lo8(STR_TOO_LOOSE)
;   RCALL PRINT_STR_FLASH
;
; =============================================================================