#define __SFR_OFFSET 0x00
#include <avr/io.h>

.global BUZZER_INIT
.global BUZZER_TOGGLE
.global BUZZER_UPDATE_FREQ

; Alokasi variabel SRAM secara absolut
.equ buzzer_state, 0x0104   ; 0 = off, 1 = on

.section .text

; OCR1A Lookup Table (from infoFinpro.md):
; E2 (0) = 0x2F65
; A2 (1) = 0x2382
; D3 (2) = 0x1A9A
; G3 (3) = 0x13ED
; B3 (4) = 0x0FD1
; E4 (5) = 0x0BD9
buzzer_lookup:
    .word 0x2F65, 0x2382, 0x1A9A, 0x13ED, 0x0FD1, 0x0BD9

BUZZER_INIT:
    ; PB1 (OC1A) as Output
    sbi DDRB, 1
    
    ; Initial timer config: CTC mode, stopped
    ; WGM13:0 = 0100 (CTC Mode, top OCR1A)
    ldi r16, 0x00
    sts TCCR1A, r16
    ; Precaler 8 -> CS12:0 = 010
    ldi r16, (1<<WGM12)
    sts TCCR1B, r16
    
    ; Initial state off
    ldi r16, 0
    sts buzzer_state, r16
    cbi PORTB, 1
    
    ret

BUZZER_UPDATE_FREQ:
    ; r23 has the string index (0 to 5)
    andi r23, 0x07          ; safety mask
    cpi r23, 6
    brsh skip_freq_update   ; if > 5, ignore
    
    ; load address of buzzer_lookup
    ldi zl, lo8(buzzer_lookup)
    ldi zh, hi8(buzzer_lookup)
    
    ; R23 * 2 (because 2 bytes per word)
    mov r16, r23
    lsl r16
    add zl, r16
    adc zh, r1
    
    ; Read sequence from program memory using LPM
    lpm r16, z+     ; read low byte
    lpm r17, z      ; read high byte
    
    ; Write to OCR1A (high byte first)
    sts OCR1AH, r17
    sts OCR1AL, r16

skip_freq_update:
    ret

BUZZER_TOGGLE:
    sbic PIND, 3          ; Jika PD3 dilepas/HIGH, lompati perintah rjmp turn_on
    rjmp turn_off         ; Melompat ke turn_off jika tombol dilepas
    ; Jika sampai di sini berarti PD3 = LOW (ditekan)
    
turn_on:
    ; Cegah mengulang nyala bila sudah nyala
    lds r16, buzzer_state
    cpi r16, 1
    breq _bt_end

    ldi r16, 1
    sts buzzer_state, r16
    
    ; Update frequency based on current R23 before turning on
    rcall BUZZER_UPDATE_FREQ
    
    ; Toggle on Compare Match -> COM1A1:0 = 01
    ldi r16, (1<<COM1A0)
    sts TCCR1A, r16
    
    ; Start timer, prescaler 8 -> CS12:0 = 010
    ldi r16, (1<<WGM12) | (1<<CS11)
    sts TCCR1B, r16
    
_bt_end:
    ret

turn_off:
    ; Cegah mengulang mati bila sudah mati
    lds r16, buzzer_state
    cpi r16, 0
    breq _bt_end

    ldi r16, 0
    sts buzzer_state, r16
    
    ; Stop Toggle on Compare Match
    ldi r16, 0x00
    sts TCCR1A, r16
    ; Stop timer
    ldi r16, 0x00
    sts TCCR1B, r16
    
    cbi PORTB, 1
    ret
