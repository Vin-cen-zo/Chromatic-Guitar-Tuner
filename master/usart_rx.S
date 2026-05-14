#include <avr/io.h>

.global USART_INIT
.global USART_RX_ISR

.section .data
rx_state:   .byte 0     ; 0=wait sync, 1=wait low, 2=wait high
rx_temp_lo: .byte 0

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
    ret

USART_RX_ISR:
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
    mov r25, r16        ; Update R25 (High Byte)
    lds r24, rx_temp_lo ; Update R24 (Low Byte)
    
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
