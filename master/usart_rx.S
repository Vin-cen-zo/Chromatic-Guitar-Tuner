#define __SFR_OFFSET 0x00
#include <avr/io.h>

.global USART_INIT
.global USART_RX_vect

; --- FIX MEMORY ALLOCATION ---
; Hapus .section .data dan ganti dengan absolute address (.equ) di SRAM (0x0100+).
; Ini sangat kritikal di raw assembly agar variabel SRAM tidak tumpang tindih
; dengan Register CPU (R0-R31) saat linker menempatkan .data di alamat 0x0000.
.equ rx_state,      0x0100    ; 0=wait sync, 1=wait low, 2=wait high
.equ rx_temp_lo,    0x0101
.equ rx_final_lo,   0x0102    ; Low Byte Hz terakhir yang valid
.equ rx_final_hi,   0x0103    ; High Byte Hz terakhir yang valid

.section .text

USART_INIT:
    ; 9600 bps at 16MHz
    ldi r16, 0x00
    sts UBRR0H, r16
    ldi r16, 0x67
    sts UBRR0L, r16
    
    ; Enable RX, enable RX Interrupt
    ldi r16, (1<<RXEN0) | (1<<RXCIE0)
    sts UCSR0B, r16
    
    ; 8 data bits, 1 stop bit, no parity
    ldi r16, (1<<UCSZ01) | (1<<UCSZ00)
    sts UCSR0C, r16

    ; init variables
    ldi r16, 0
    sts rx_state, r16
    ; [FIX RACE CONDITION] Inisialisasi variabel SRAM baru ke 0
    sts rx_final_lo, r16
    sts rx_final_hi, r16
    ret

USART_RX_vect:
    push r16
    in r16, SREG
    push r16
    push r17

    lds r16, UDR0       ; Read data

    lds r17, rx_state
    cpi r17, 0
    breq state_0
    cpi r17, 1
    breq state_1
    cpi r17, 2
    breq state_2
    rjmp reset_state

state_0:
    cpi r16, 0xFF       ; Check for Sync Byte
    brne end_isr        ; Ignore if not sync byte
    ldi r17, 1
    sts rx_state, r17
    rjmp end_isr

state_1:
    sts rx_temp_lo, r16 ; Save Low Byte
    ldi r17, 2
    sts rx_state, r17
    rjmp end_isr

state_2:
    ; R16 contains High Byte
    ; [FIX RACE CONDITION] Simpan ke SRAM, BUKAN langsung ke R24/R25.
    ; R17 aman dipakai di sini karena sudah di-PUSH di awal ISR (baris push r17).
    sts rx_final_hi, r16    ; simpan High Byte ke SRAM
    lds r17, rx_temp_lo     ; ambil Low Byte dari temp
    sts rx_final_lo, r17    ; simpan Low Byte ke SRAM

    ; Set flag that new data is ready
    ldi r22, 0x01
    
reset_state:
    ldi r17, 0
    sts rx_state, r17

end_isr:
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti
