#define __SFR_OFFSET 0x00
#include "avr/io.h"

.global main

main:
    ; --- Inisialisasi USART (9600 bps, 8 Data, 1 Stop) ---
    ldi r16, 0x00
    sts UBRR0H, r16
    ldi r16, 0x67
    sts UBRR0L, r16
    ldi r16, (1<<TXEN0)
    sts UCSR0B, r16
    ldi r16, (1<<UCSZ01) | (1<<UCSZ00)
    sts UCSR0C, r16

    ; --- Inisialisasi ADC (Single Conversion Mode, Pin PC0) ---
    ; 1. Pastikan PC0 = input tanpa pull-up
    ldi r16, 0x00
    sts DDRC, r16           ; PORTC semua input
    sts PORTC, r16          ; Pull-up dimatikan

    ; 2. Disable digital input buffer pada ADC0
    ldi r16, (1<<ADC0D)
    sts DIDR0, r16

    ; 3. Set referensi AVCC, channel ADC0
    ldi r16, (1<<REFS0)
    sts ADMUX, r16

    ; 4. Enable ADC, prescaler 128
    ldi r16, (1<<ADEN) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0) 
    sts ADCSRA, r16
    ldi r16, 0x00
    sts ADCSRB, r16

    ; 5. Dummy first conversion (hasil dibuang)
    lds r16, ADCSRA
    ori r16, (1<<ADSC)
    sts ADCSRA, r16
dummy_wait:
    lds r16, ADCSRA
    sbrc r16, ADSC
    rjmp dummy_wait

    ; --- Inisialisasi Timer 1 (Normal Mode, belum jalan) ---
    ldi r16, 0x00
    sts TCCR1A, r16
    sts TCCR1B, r16         ; Timer 1 mati dulu

    ; --- Macro untuk membaca ADC (Single Conversion Polling) ---
    .macro BACA_ADC
        lds r19, ADCSRA
        ori r19, (1<<ADSC)
        sts ADCSRA, r19
    wait_adc_\@:
        lds r19, ADCSRA
        sbrc r19, ADSC
        rjmp wait_adc_\@
        lds r16, ADCL
        lds r17, ADCH
    .endm

    ; --- Macro untuk kirim 1 byte via USART ---
    .macro KIRIM_BYTE reg
    wait_tx_\@:
        lds r19, UCSR0A
        sbrs r19, UDRE0
        rjmp wait_tx_\@
        sts UDR0, \reg
    .endm

main_loop:

    ; Reset Timer 1 counter
    ldi r16, 0x00
    sts TCCR1B, r16         ; Stop timer
    sts TCNT1H, r16         ; Reset counter
    sts TCNT1L, r16

    ; --- Fase 1: Tunggu sinyal turun di bawah 320 (0x0140) ---
fase_1_turun:
    BACA_ADC
    cpi r16, 0x40
    ldi r18, 0x01
    cpc r17, r18
    brsh fase_1_turun

    ; --- Fase 2: Tunggu sinyal naik di atas 355 (0x0163) -> START ---
fase_2_naik:
    BACA_ADC
    cpi r16, 0x63
    ldi r18, 0x01
    cpc r17, r18
    brlo fase_2_naik

    ; Gelombang pertama terdeteksi! Mulai Timer 1 (Prescaler 8)
    ldi r16, (1<<CS11)
    sts TCCR1B, r16

    ; --- Fase 3: Tunggu sinyal turun lagi di bawah 320 ---
fase_3_turun:
    BACA_ADC
    cpi r16, 0x40
    ldi r18, 0x01
    cpc r17, r18
    brsh fase_3_turun

    ; --- Fase 4: Tunggu sinyal naik lagi di atas 355 -> STOP ---
fase_4_naik:
    BACA_ADC
    cpi r16, 0x63
    ldi r18, 0x01
    cpc r17, r18
    brlo fase_4_naik

    ; 1 Periode Selesai! Hentikan Timer 1
    ldi r16, 0x00
    sts TCCR1B, r16

    ; Baca durasi periode (ticks) dari Timer 1
    lds r20, TCNT1L
    lds r21, TCNT1H

    ; --- Validasi: skip jika ticks = 0 ---
    mov r16, r20
    or  r16, r21
    brne div_start
    rjmp main_loop

div_start:

    ; --- Hitung Frekuensi: Hz = 2.000.000 / ticks ---
    ; Dividend (32-bit): 2.000.000 = 0x001E8480 -> r15:r14:r13:r12
    ; Divisor (16-bit): ticks -> r21:r20
    ; Quotient (16-bit): Hz -> r25:r24

    ldi r16, 0x80
    mov r12, r16
    ldi r16, 0x84
    mov r13, r16
    ldi r16, 0x1E
    mov r14, r16
    clr r15

    clr r22
    clr r23
    clr r24
    clr r25

    ldi r18, 32

div_loop:
    lsl r12
    rol r13
    rol r14
    rol r15
    rol r22
    rol r23

    sub r22, r20
    sbc r23, r21

    brcc div_no_restore

    add r22, r20
    adc r23, r21
    rjmp div_next

div_no_restore:
    ori r24, 0x01

div_next:
    dec r18
    breq div_done

    lsl r24
    rol r25
    rjmp div_loop

div_done:
    ; r25:r24 = frekuensi dalam Hz (16-bit)

    ; --- 1. Pencegahan Konflik Data ---
    ; Sync Byte = 0xFF, jadi data aktual tidak boleh bernilai 0xFF
    cpi r25, 0xFF
    brne cek_low_byte
    ldi r25, 0xFE           ; Paksa turun ke 0xFE

cek_low_byte:
    cpi r24, 0xFF
    brne transmisi_mulai
    ldi r24, 0xFE           ; Paksa turun ke 0xFE

transmisi_mulai:
    ; --- 2. Transmisi USART (Protokol: Sync -> Low -> High) ---
    ldi r16, 0xFF
    KIRIM_BYTE r16          ; Sync Byte (penanda awal paket)
    KIRIM_BYTE r24          ; Low Byte (Little-Endian)
    KIRIM_BYTE r25          ; High Byte

    ; --- 3. Rate Limiting (Delay ~150ms @ 16 MHz) ---
    ; Mencegah Slave membanjiri USART, beri Master waktu proses LCD
    ldi r18, 13
delay_outer:
    ldi r19, 250
delay_inner:
    ldi r20, 250
delay_core:
    dec r20
    brne delay_core
    dec r19
    brne delay_inner
    dec r18
    brne delay_outer

    rjmp main_loop