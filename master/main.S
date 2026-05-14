; === FILE PERAN 2 — JANGAN UBAH URUTAN ===
; (Uncomment baris di bawah ini ketika file Peran 2 sudah siap untuk digabungkan)
; #include "lcd_i2c.S"        ; 1. TWI primitives dulu
; #include "lcd_driver.S"     ; 2. LCD driver (butuh TWI)
; #include "lookup_table.S"   ; 3. Data tabel di Flash
; #include "bcd_ascii.S"      ; 4. Konverter angka
; #include "mapping.S"        ; 5. Logika mapping (butuh tabel)
; #include "display.S"        ; 6. Update display (butuh semua di atas)
; === END FILE PERAN 2 ===

; [FIX BUG #1] Double include dihapus dari sini — usart_rx.S & buzzer_core.S
; sudah di-include di .section .text di bawah. Duplikat ini menyebabkan assembler error.

.global main

; Interrupt Vectors
.section .vectors
    jmp main
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
; [FIX BUG #4] Semua include Peran 2 di-uncomment — file sudah lengkap dan siap digabung
; Urutan WAJIB dipertahankan (setiap file bergantung pada file sebelumnya)
#include "lcd_i2c.S"        // 1. TWI primitives
#include "lcd_driver.S"     // 2. LCD driver (butuh TWI)
#include "lookup_table.S"   // 3. Data tabel di Flash
#include "bcd_ascii.S"      // 4. Konverter angka
#include "mapping.S"        // 5. Logika mapping (butuh tabel)
#include "display.S"        // 6. Update display (butuh semua di atas)

#include "usart_rx.S"
#include "buzzer_core.S"

main:
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
    
    ; [FIX BUG #4] LCD_INIT di-uncomment — wajib dipanggil sekali di RESET
    RCALL LCD_INIT
    RCALL DISPLAY_STARTUP   ; tampilkan splash screen (opsional)

    ; Enable Global Interrupts
    sei

MAIN_LOOP:
    ; Check if flag data baru R22 == 0x01
    cpi r22, 0x01
    brne MAIN_LOOP
    
    ; Jika data baru ada, reset flag
    clr r22
    
    ; [FIX BUG #4] UPDATE_DISPLAY di-uncomment — dipanggil tiap data baru siap
    RCALL UPDATE_DISPLAY

    rjmp MAIN_LOOP


; --- ISR for INT0 (Mode / String Index) ---
EXT_INT0:
    push r16
    in r16, SREG
    push r16
    ; [FIX BUG #3] Simpan R17, ZH, ZL sebelum panggil BUZZER_UPDATE_FREQ
    ; BUZZER_UPDATE_FREQ memodifikasi ketiga register ini tanpa push/pop sendiri,
    ; sehingga akan merusak nilai milik kode yang sedang diinterupsi (mis. UPDATE_DISPLAY)
    push r17
    push zh
    push zl

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

    ; [FIX BUG #3] Pulihkan ZL, ZH, R17 dalam urutan LIFO
    pop zl
    pop zh
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti


; --- ISR for INT1 (Buzzer Toggle) ---
EXT_INT1:
    push r16
    in r16, SREG
    push r16
    ; [FIX BUG #3] Simpan R17, ZH, ZL — BUZZER_TOGGLE memanggil BUZZER_UPDATE_FREQ
    ; yang memodifikasi R17, ZH, ZL tanpa menyelamatkannya sendiri
    push r17
    push zh
    push zl

    rcall BUZZER_TOGGLE

    ; [FIX BUG #3] Pulihkan ZL, ZH, R17 dalam urutan LIFO
    pop zl
    pop zh
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti
