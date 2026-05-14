; === FILE PERAN 2 — JANGAN UBAH URUTAN ===
; (Uncomment baris di bawah ini ketika file Peran 2 sudah siap untuk digabungkan)
; #include "lcd_i2c.S"        ; 1. TWI primitives dulu
; #include "lcd_driver.S"     ; 2. LCD driver (butuh TWI)
; #include "lookup_table.S"   ; 3. Data tabel di Flash
; #include "bcd_ascii.S"      ; 4. Konverter angka
; #include "mapping.S"        ; 5. Logika mapping (butuh tabel)
; #include "display.S"        ; 6. Update display (butuh semua di atas)
; === END FILE PERAN 2 ===

#include "usart_rx.S"
#include "buzzer_core.S"

.global main

; Interrupt Vectors
.section .vectors
    jmp RESET
    jmp EXT_INT0        ; INT0 Request (PD2) - Mode/Senar
    jmp EXT_INT1        ; INT1 Request (PD3) - Buzzer Toggle
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp UNHANDLED_INT
    jmp USART_RX_ISR    ; USART Rx Complete
    ; fill the rest to avoid crash if accidentally triggered...

UNHANDLED_INT:
    reti

.section .text

; --- FILE PERAN 2 --- 
; File dummy atau file rekan 2. Karena rekan 2 belum selesai,
; kita include file-nya. Jika belum ada, proses build akan error 
; tetapi secara kode assembly struktur `#include` ini sudah benar sesuai dokumen.
; Untuk compile, bisa uncomment ini jika file rekan 2 sudah siap.
;
; #include "lcd_i2c.S"
; #include "lcd_driver.S"
; #include "lookup_table.S"
; #include "bcd_ascii.S"
; #include "mapping.S"
; #include "display.S"

#include "usart_rx.S"
#include "buzzer_core.S"

RESET:
    ; Init Stack Pointer
    ldi r16, hi8(RAMEND)
    out SPH, r16
    ldi r16, lo8(RAMEND)
    out SPL, r16

    ; Clear Registers
    clr r1
    clr r22           ; R22 = Flag Data Baru
    clr r23           ; R23 = Index target senar (0 = E2)
    clr r24           ; R24 = Low Byte Hz
    clr r25           ; R25 = High Byte Hz

    ; Set INT0 (PD2) and INT1 (PD3) as Input with Pull-up
    cbi DDRD, 2
    sbi PORTD, 2
    cbi DDRD, 3
    sbi PORTD, 3

    ; Configure External Interrupts INT0 & INT1
    ; Trigger on Falling Edge
    ldi r16, (1<<ISC11) | (0<<ISC10) | (1<<ISC01) | (0<<ISC00)
    sts EICRA, r16
    ; Enable INT0 and INT1
    ldi r16, (1<<INT1) | (1<<INT0)
    out EIMSK, r16

    ; Initialize Modules
    rcall USART_INIT
    rcall BUZZER_INIT
    
    ; Panggil LCD_INIT milik Peran 2
    ; RCALL LCD_INIT

    ; Enable Global Interrupts
    sei

MAIN_LOOP:
    ; Check if flag data baru R22 == 0x01
    cpi r22, 0x01
    brne MAIN_LOOP
    
    ; Jika data baru ada, reset flag
    clr r22
    
    ; Panggil layar update
    ; RCALL UPDATE_DISPLAY

    rjmp MAIN_LOOP


; --- ISR for INT0 (Mode / String Index) ---
EXT_INT0:
    push r16
    in r16, SREG
    push r16

    ; Increment R23 Mode (0-5)
    inc r23
    cpi r23, 6
    brsh reset_mode
    rjmp end_int0
reset_mode:
    clr r23
end_int0:
    
    ; Secara opsional set R22=1 agar layar di-update pas ganti senar, walau blm ada input Hz baru
    ldi r22, 0x01

    ; Update frekuensi buzzer jika sedang nyala
    rcall BUZZER_UPDATE_FREQ

    pop r16
    out SREG, r16
    pop r16
    reti


; --- ISR for INT1 (Buzzer Toggle) ---
EXT_INT1:
    push r16
    in r16, SREG
    push r16

    rcall BUZZER_TOGGLE

    pop r16
    out SREG, r16
    pop r16
    reti
