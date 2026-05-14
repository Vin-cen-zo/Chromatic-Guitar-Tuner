# Dokumen Perancangan Sistem: Digital Audio Tuner (Dual-Node)

## 1. Spesifikasi Perangkat Keras
Sistem ini menggunakan arsitektur *Master-Slave* dengan dua unit mikrokontroler untuk memisahkan beban komputasi pemrosesan sinyal dan antarmuka pengguna.

### Daftar Komponen Utama
*   **Unit Pemroses:** 2x IC ATmega328P (atau board Arduino Uno R3).
*   **Sensor Suara:** 1x Modul Mikrofon GY-MAX4466 (Electret Microphone Amplifier).
*   **Layar Antarmuka:** 1x Modul LCD 16x2 dengan Modul I2C PCF8574.
*   **Aktuator Suara:** 1x Passive Buzzer 5V.
*   **Input Pengguna:** 2x Tactile Push Button (6x6mm, 4-pin).

### Komponen Pasif (Filter & Debounce)
*   **Low Pass Filter (LPF) Mikrofon:** 1x Resistor 4.7k Ohm dan 1x Kapasitor Keramik 100nF (Target frekuensi cut-off $\approx 338 \text{ Hz}$).
*   **Hardware Debounce Tombol:** 2x Resistor 10k Ohm (Pull-up) dan 2x Kapasitor Keramik 100nF.

---

## 2. Peta Alokasi Pin & Parameter Komunikasi

### Alokasi Pin Mikrokontroler
| Komponen | Mikrokontroler | Pin AVR | Keterangan Fungsi |
| :--- | :--- | :--- | :--- |
| **Mikrofon (Output LPF)** | Arduino Slave | `PC0` (A0) | Input analog untuk ADC (*Free-Running Mode*). |
| **USART TX** | Arduino Slave | `PD1` (TX) | Mengirim data frekuensi ke Master. |
| **USART RX** | Arduino Master | `PD0` (RX) | Menerima data frekuensi dari Slave. |
| **LCD I2C (SDA)** | Arduino Master | `PC4` (A4) | Jalur data I2C untuk LCD. |
| **LCD I2C (SCL)** | Arduino Master | `PC5` (A5) | Jalur clock I2C untuk LCD. |
| **Tombol Mode/Senar** | Arduino Master | `PD2` (D2) | `INT0` (External Interrupt 0). |
| **Tombol Buzzer** | Arduino Master | `PD3` (D3) | `INT1` (External Interrupt 1). |
| **Passive Buzzer** | Arduino Master | `PB1` (D9) | Output `OCR1A` (Timer 1, CTC Mode). |

### Spesifikasi Protokol & Kelistrikan
*   **USART:** Asynchronous, 9600 bps, 8 Data bits, No Parity, 1 Stop bit.
*   **I2C LCD:** Alamat modul umumnya berada di `0x27` (atau `0x3F`).
*   **Topologi Daya (CRITICAL):** Pin Ground (GND) dari Arduino Slave, Arduino Master, Modul Mikrofon, dan LCD **wajib saling terhubung** (Common Ground) agar transmisi data biner via USART tidak mengalami distorsi.

---

## 3. Alur Kerja Sistem (System Workflow)

### Fase 1: Akuisisi Sinyal (Arduino Slave)
1. Modul mikrofon menangkap gelombang suara.
2. Sinyal dilewatkan melalui *RC Low Pass Filter* perangkat keras untuk memotong harmonik frekuensi tinggi (di atas 338 Hz).
3. ADC berjalan secara terus-menerus (*Free-Running Mode*) membaca fluktuasi tegangan.
4. Algoritma *Zero-Crossing* mendeteksi titik potong gelombang untuk mencari satu periode utuh.
5. Timer 1 (16-bit) menghitung durasi waktu dari periode tersebut.
6. Durasi dikonversi menjadi frekuensi (Hz) dalam format biner 16-bit (2 byte).
7. Data 2 byte dikirim ke Arduino Master secara asinkron satu arah (Simplex USART).

### Fase 2: Pemrosesan Data & Antarmuka (Arduino Master)
1. Interupsi USART (RXCIE) menerima paket 2 byte dari Slave dan menyimpannya di register memori.
2. Logika *Mapping* membandingkan nilai Hz aktual dengan *Lookup Table* Chromatic (rentang E2 hingga E4).
3. Berdasarkan selisih toleransi, sistem menentukan status pesan (`TOO LOOSE`, `NICE`, `TOO TIGHT`).
4. Data biner dikonversi menjadi format ASCII dan dikirim ke layar (I2C).
5. Jika tombol Buzzer ditekan, Timer 1 pada Master mengambil nilai konfigurasi dari *Lookup Table* dan menghasilkan sinyal *toggle* otomatis (CTC Mode) ke *Passive Buzzer*.

---

## 4. Pembagian Tugas Spesifik (Job Description)

### Peran 1: Pengembang Pemroses Sinyal (Full Slave)
*   **Fokus Modul:** ADC, Timer 1 (Normal Mode), USART (Transmitter).
*   **Detail Implementasi:**
    *   Menerapkan *hysteresis* pada pembacaan ADC untuk menghindari perhitungan *noise* frekuensi palsu.
    *   Menulis sub-rutin pembagian biner 16-bit/32-bit di Assembly untuk mengonversi nilai *ticks* Timer menjadi angka Hertz.
    *   Mengemas data 16-bit menjadi *High Byte* dan *Low Byte*, lalu mengirimkannya via register `UDR0`.

### Peran 2: Pengembang Antarmuka & Logika Pemetaan (LCD & Mapping Master)
*   **Fokus Modul:** TWI/I2C, Manajemen Memori (SRAM/Flash).
*   **Detail Implementasi:**
    *   Membangun *Lookup Table* komprehensif di memori Flash (*Program Memory*) yang memetakan rentang Hz ke karakter String (misal: 82 Hz -> "E2").
    *   Menyusun rutinitas konversi BCD (Binary-Coded Decimal) ke ASCII agar angka Hz biner dari Slave bisa dicetak sebagai teks di layar.
    *   Membangun logika kondisional untuk *Status Message*:
        *   Jika Aktual < (Target - Toleransi), cetak `TOO LOOSE`.
        *   Jika Aktual masuk rentang toleransi, cetak `NICE`.
        *   Jika Aktual > (Target + Toleransi), cetak `TOO TIGHT`.

### Peran 3: Pengembang Kontrol Sistem & Aktuator (Core Master)
*   **Fokus Modul:** USART (Receiver), EXTI (External Interrupt), Timer 1 (CTC Mode).
*   **Detail Implementasi:**
    *   Menerima dan menggabungkan *High Byte* dan *Low Byte* dari USART ke dalam register 16-bit (contoh: pasangan register `R25:R24`).
    *   Mengatur interupsi eksternal (`INT0` dan `INT1`) untuk pergantian senar dan *toggle buzzer*, memanfaatkan sirkuit *hardware debounce* untuk memastikan tidak ada pemicuan ganda.
    *   Membangun *Lookup Table* khusus aktuator berisi nilai register `OCR1A` yang sudah dikalkulasi manual untuk membunyikan setiap nada referensi pada *buzzer*.

---

## 5. Tabel Frekuensi Chromatic ($E_2$ - $E_4$)

Data ini dihitung berdasarkan standar nada $A_4 = 440 \text{ Hz}$ dengan spesifikasi teknis mikrokontroler ATmega328P berjalan di *Clock Speed* 16 MHz dan *Prescaler* 8.

| Nada | Frekuensi (Hz) | USART Data (Hex) | Buzzer OCR1A (Hex) |
| :--- | :--- | :--- | :--- |
| **$E_2$** | 82.41 | `0x0052` | `0x2F65` |
| **$F_2$** | 87.31 | `0x0057` | `0x2CB3` |
| **$F\#_2 / Gb_2$** | 92.50 | `0x005C` | `0x2A2F` |
| **$G_2$** | 98.00 | `0x0062` | `0x27D7` |
| **$G\#_2 / Ab_2$** | 103.83 | `0x0067` | `0x259F` |
| **$A_2$** | 110.00 | `0x006E` | `0x2381` |
| **$A\#_2 / Bb_2$** | 116.54 | `0x0074` | `0x217E` |
| **$B_2$** | 123.47 | `0x007B` | `0x1F7A` |
| **$C_3$** | 130.81 | `0x0082` | `0x1DBB` |
| **$C\#_3 / Db_3$** | 138.59 | `0x008A` | `0x1C11` |
| **$D_3$** | 146.83 | `0x0092` | `0x1A9B` |
| **$D\#_3 / Eb_3$** | 155.56 | `0x009B` | `0x1910` |
| **$E_3$** | 164.81 | `0x00A4` | `0x17B2` |
| **$F_3$** | 174.61 | `0x00AE` | `0x1659` |
| **$F\#_3 / Gb_3$** | 185.00 | `0x00B9` | `0x1517` |
| **$G_3$** | 196.00 | `0x00C4` | `0x13ED` |
| **$G\#_3 / Ab_3$** | 207.65 | `0x00CF` | `0x12CF` |
| **$A_3$** | 220.00 | `0x00DC` | `0x11C0` |
| **$A\#_3 / Bb_3$** | 233.08 | `0x00E9` | `0x10BE` |
| **$B_3$** | 246.94 | `0x00F6` | `0x0FD1` |
| **$C_4$** | 261.63 | `0x0105` | `0x0EDD` |
| **$C\#_4 / Db_4$** | 277.18 | `0x0115` | `0x0E08` |
| **$D_4$** | 293.66 | `0x0125` | `0x0D4D` |
| **$D\#_4 / Eb_4$** | 311.13 | `0x0137` | `0x0C88` |
| **$E_4$** | 329.63 | `0x0149` | `0x0BD9` |

### Panduan Penggunaan Data
*   **USART Data (Hex):** Ini adalah nilai yang dikirim oleh Arduino Slave ke Master. Gunakan sub-rutin *Binary-to-ASCII* di sisi Master untuk mengubah angka hex ini menjadi teks angka desimal yang bisa dibaca manusia di layar LCD.
*   **Buzzer OCR1A (Hex):** Gunakan nilai ini untuk mengisi register `OCR1AH` dan `OCR1AL` pada Arduino Master. Nilai ini akan secara otomatis menghasilkan frekuensi nada referensi yang sangat akurat tanpa membebani CPU.

---

**Cara Merangkai Low Pass Filter (Target ~350 Hz):**
1.  Sambungkan pin **OUT** modul mikrofon ke salah satu kaki Resistor 4.7k Ohm.
2.  Kaki Resistor yang satunya lagi disambungkan ke pin **ADC** mikrokontroler.
3.  Pada titik pertemuan antara Resistor dan pin ADC, pasangkan Kapasitor 100nF yang terhubung ke jalur **Ground (GND)**.

**Cara Merangkai Hardware Debounce (Untuk setiap tombol):**
1.  Hubungkan satu sisi tombol ke **Ground (GND)**.
2.  Hubungkan sisi tombol yang lain ke pin **Interupsi** mikrokontroler (misal: Pin D2 / `INT0`).
3.  Pasang **Resistor 10k Ohm** dari pin Interupsi tersebut ke jalur **VCC (5V)** (Berfungsi sebagai *Pull-up* agar pin selalu HIGH saat tidak ditekan).
4.  Pasang **Kapasitor 100nF** secara paralel dengan tombol (Satu kaki di pin Interupsi, kaki lainnya di jalur Ground).