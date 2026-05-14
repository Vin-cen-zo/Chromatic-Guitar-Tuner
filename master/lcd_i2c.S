#define __SFR_OFFSET 0x00
#include "avr/io.h"

; KONSTANTA
.equ LCD_I2C_ADDR,  0x4E        ; I2C write address (0x27 << 1)
.equ TWI_FREQ,      100000      ; target I2C clock 100kHz
.equ CPU_FREQ,      16000000    ; clock MCU 16MHz
                                ; Jika pakai internal oscillator 8MHz:
                                ; ganti jadi 8000000

; Rumus TWBR: TWBR = (CPU_FREQ / TWI_FREQ - 16) / 2
; = (16000000 / 100000 - 16) / 2 = (160 - 16) / 2 = 72
.equ TWBR_VAL,      72          ; untuk 16MHz → 100kHz
                                ; Jika CPU 8MHz: TWBR_VAL = 32

; TWI_INIT
; Inisialisasi modul TWI hardware ATmega328P
TWI_INIT:
    PUSH R16

    ; Set TWBR - menentukan kecepatan clock I2C
    LDI R16, TWBR_VAL
    STS TWBR, R16

    ; Set TWSR - prescaler = 1 (bit TWPS1:TWPS0 = 00)
    LDI R16, 0x00
    STS TWSR, R16

    ; Enable TWI module
    LDI R16, (1 << TWEN)
    STS TWCR, R16

    POP R16
    RET


; TWI_START
; Kirim kondisi START ke bus I2C
TWI_START:
    PUSH R16

    ; Kirim START condition
    ; TWINT=1 (clear flag), TWSTA=1 (START), TWEN=1 (enable)
    LDI R16, (1 << TWINT) | (1 << TWSTA) | (1 << TWEN)
    STS TWCR, R16

    ; Tunggu sampai START selesai dikirim
    RCALL TWI_WAIT

    POP R16
    RET


; TWI_STOP
; Kirim kondisi STOP ke bus I2C, mengakhiri transaksi
TWI_STOP:
    PUSH R16

    ; Kirim STOP condition
    ; TWINT=1 (clear flag), TWSTO=1 (STOP), TWEN=1 (enable)
    LDI R16, (1 << TWINT) | (1 << TWSTO) | (1 << TWEN)
    STS TWCR, R16

    ; STOP tidak perlu tunggu TWINT - hardware handle otomatis
    ; Tapi beri sedikit waktu bus kembali idle
    NOP
    NOP
    NOP
    NOP

    POP R16
    RET


; TWI_WRITE
; Kirim 1 byte data ke bus I2C
; Input: R16 = byte yang akan dikirim
TWI_WRITE:
    PUSH R17

    ; Tulis data ke register TWDR
    STS TWDR, R16

    ; Clear TWINT untuk mulai transmisi
    ; TWINT=1 (clear/start), TWEN=1 (enable)
    LDI R17, (1 << TWINT) | (1 << TWEN)
    STS TWCR, R17

    ; Tunggu transmisi selesai
    RCALL TWI_WAIT

    POP R17
    RET


; TWI_WAIT  [jangan dipanggil langsung dari luar file ini]
; Polling TWINT flag sampai operasi TWI selesai
TWI_WAIT:
    PUSH R16

_twi_wait_loop:
    ; Baca TWCR
    LDS R16, TWCR

    ; Cek bit TWINT — kalau sudah 1 berarti operasi selesai
    SBRS R16, TWINT
    RJMP _twi_wait_loop     ; belum selesai, loop lagi

    POP R16
    RET


; TWI_WRITE_ADDR  [Helper — kirim address + R/W bit]
; Kirim I2C address dengan Write bit (0)
TWI_WRITE_ADDR:
    PUSH R16

    LDI R16, LCD_I2C_ADDR   ; 0x4E = address write LCD
    RCALL TWI_WRITE

    POP R16
    RET

; =============================================================================
; CONTOH URUTAN PENGGUNAAN (jangan hapus komentar ini):
;
;   RCALL TWI_START          ; 1. Kirim START
;   RCALL TWI_WRITE_ADDR     ; 2. Kirim address LCD (0x4E)
;   LDI R16, 0xFF            ; 3. Siapkan data
;   RCALL TWI_WRITE          ; 4. Kirim data
;   RCALL TWI_STOP           ; 5. Kirim STOP
;
; =============================================================================