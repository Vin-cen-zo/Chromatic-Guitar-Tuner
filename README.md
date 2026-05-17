# Digital Audio Tuner (Dual-Node)

## Introduction to the problem and the solution
Proyek ini menyelesaikan tantangan pendeteksian presisi dan penyetelan nada pada instrumen gitar. Solusi yang ditawarkan adalah sistem Digital Audio Tuner yang menggunakan arsitektur *Master-Slave* dengan dua unit mikrokontroler (ATmega328P). Pemisahan perangkat ini bertujuan untuk mendistribusikan beban komputasi: mikrokontroler Slave berfokus penuh pada akuisisi sinyal dan pemrosesan frekuensi secara langsung, sementara mikrokontroler Master menangani antarmuka pengguna (LCD, input tombol) dan feedback suara (Buzzer).

## Hardware design and implementation details
Sistem ini menggunakan topologi *Common Ground* antar node dan terdiri dari berbagai komponen yang terintegrasi untuk membaca sinyal analog dan menampilkan output digital.

**Daftar Komponen Utama:**
* **Unit Pemroses:** 2x IC ATmega328P (atau board Arduino Uno).
* **Sensor Suara:** 1x Modul Mikrofon GY-MAX4466 (Electret Microphone Amplifier).
* **Layar Antarmuka:** 1x Modul LCD 16x2 dengan I2C (PCF8574).
* **Aktuator Suara:** 1x Passive Buzzer 5V.
* **Input Pengguna:** 2x Tactile Push Button (Pull-up).

**Filter & Sirkuit Pengondisi:**
* **Low Pass Filter (LPF) Mikrofon:** 1x Resistor 4.7k $\Omega$ & 1x Kapasitor 100nF untuk memotong frekuensi tinggi (Cut-off $\approx 338 \text{ Hz}$).
* **Hardware Debounce:** Resistor 10k $\Omega$ dan Kapasitor 100nF pada setiap tombol.

**Alokasi Pin:**
* **Slave (Pemrosesan Sinyal):** Input mikrofon LPF di `PC0` (A0 - ADC). TX USART pada `PD1`.
* **Master (UI & Kontrol):** RX USART dari Slave di `PD0`. TWI/I2C untuk LCD pada `PC4` (SDA) dan `PC5` (SCL). Interrupt tombol di `PD2` (INT0) dan `PD3` (INT1). Buzzer output Timer1 di `PB1` (OCR1A).

## Software implementation details
Sistem diimplementasikan seluruhnya menggunakan bahasa assembly arsitektur AVR, terbagi dalam dua subsistem:

**1. Sisi Akuisisi Sinyal (Slave):**
Menggunakan ADC pada *Free-Running Mode*, algoritma *Zero-Crossing* diterapkan bersama *hysteresis* untuk mendeteksi fluktuasi sinyal tanpa mendeteksi *noise* palsu. Timer 1 (16-bit) menghitung durasi periode antar titik potong, lalu nilainya dikonversi menjadi unit frekuensi (Hz). Data biner 16-bit (2-byte) ini dikirim via USART.

**2. Sisi Antarmuka & Logika (Master):**
Data 16-bit diterima via interupsi USART (RXCIE). Menggunakan sub-rutin konversi biner ke BCD-ASCII, Master menampilkan nilai aktual tersebut ke LCD melalui protokol I2C. Master memiliki *Lookup Table* berisi nilai dari setiap nada (frekuensi Chromatic $E_2$ - $E_4$). Logika Mapping membandingkan frekuensi ADC dengan tabel, lalu memunculkan status (`TOO LOOSE`, `NICE`, `TOO TIGHT`). Selain itu, interupsi tombol akan memerintahkan Timer 1 (*CTC mode*) untuk membangkitkan frekuensi acuan nada ke passive buzzer via `OCR1A`.

## Test results and performance evaluation
Pengujian dilakukan dengan mengukur resolusi komputasi berbasis standar *Clock* 16 MHz dan *Prescaler* 8. Tuner mampu membedakan tingkat selisih pitch (resolusi frekuensi) dengan margin toleransi akurat. Kombinasi *RC Low Pass Filter* analog (hardware) dan *hysteresis* (algoritma digital software) berhasil menekan harmonik *noise*, memberikan nilai akhir dari *fundamental frequency* yang stabil untuk divisualisasikan, bahkan pada frekuensi terendah (seperti bas $E_2$ di 82.41 Hz).

## Conclusion and future work
Pemisahan domain logika pada dua MCU (arsitektur dual-node) efektif membebaskan hambatan pada komputasi *real-time*. Proses UI/LCD yang lambat secara bawaan (karena latensi I2C) kini terisolasi dari proses akuisisi *Zero-Crossing* ADC berkecepatan tinggi, sehingga tidak terjadi *data-loss*.

**Future Work:**
1. **Analisis Spektrum Fourier (FFT):** Mengganti kalkulasi periode/Zero-Crossing dengan pemrosesan FFT sederhana untuk menangani harmonik atau polifoni yang jauh lebih kompleks.
2. **Implementasi Single-Node Multiplexing:** Dengan manajemen *task scheduler* dan preemption interrupt secara advance, seluruh logika dapat dimampatkan pada satu unit eksekusi MCU saja untuk efisiensi biaya serta daya.
