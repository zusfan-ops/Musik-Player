# M3U Musik & Hallsem Cinema (Flutter Android)

Aplikasi Android **Musik Player Offline, Multi-Playlist M3U (Audio & Video/IPTV), Direktori Musik, dan Hallsem Cinema** yang dibangun dengan Flutter, mengusung antarmuka gelap modern kombinasi **Netflix x Spotify** serta identitas visual [logo2.png](logo2.png).

---

## ✨ Fitur Utama

### 1. Pemutar Musik Offline & Pengelompokan Direktori
- Memindai otomatis folder musik perangkat Android (`/Music`, `/Download`, `/Audio`, `/Podcasts`, `/Ringtones`, serta SD Card) dan mendukung penambahan banyak direktori kustom (**+ Tambah Direktori**).
- Seluruh lagu otomatis dikelompokkan berdasarkan direktorinya masing-masing, lengkap dengan pencarian cepat di dalam folder dan fitur **Jadikan Playlist M3U Offline**.
- Mendukung format audio populer: `.mp3`, `.flac`, `.m4a`, `.wav`, `.aac`, `.ogg`, `.opus`, `.wma`, `.amr`.
- Kontrol pemutar Spotify-style: *Shuffle*, *Repeat* (`Off` / `All` / `One`), *Seekbar*, kecepatan putar (`0.75x`–`2.0x`), *Sleep Timer*, *Antrean Putar*, dan *Lagu Favorit*.

### 2. Multi-Playlist M3U (File Lokal & Alamat Link URL)
- Mendukung penambahan **lebih dari satu playlist `.m3u` / `.m3u8` sekaligus**.
- **Mode Offline Penuh**: File `.m3u` lokal di-cache otomatis, path lagu relatif/absolut dipetakan ke penyimpanan lokal, dan audio dari link HTTP/HTTPS dapat diunduh ke penyimpanan offline (*Simpan Offline*).
- **Deteksi Otomatis Video & Live TV IPTV**: Link/file video (`.m3u8`, `.mp4`, `.mkv`, `.ts`, tag `tvg-*`, resolusi `720p`/`1080p`/`HD`, serta header `#EXTVLCOPT`) otomatis dibuka di **M3U Video & Live TV Player** (*Portrait Split* dengan daftar pencarian channel di bawah video + *Fullscreen Landscape* dengan drawer channel & tombol *Fit/Zoom*).

### 3. Hallsem Cinema (Film & Serial Terintegrasi)
- Terintegrasi langsung dengan server **Hallsem Cinema** (`HallSem Media Center`) tanpa perlu konfigurasi manual.
- Dilengkapi tampilan katalog sinema bergaya Netflix (*Hero Billboard*, *Lanjutkan Menonton*, pencarian judul/genre, filter *Film / Episode / Video*), serta pemutar video layar penuh dengan *Direct Play* + fallback otomatis *HLS Universal*, tombol `-10s` / `+10s`, rasio layar, kecepatan putar, dan simpan progres tontonan.

### 4. Profil Pengguna, Avatar Kustom & Identitas Visual
- Menggunakan [logo2.png](logo2.png) sebagai **Logo Aplikasi**, **Android Adaptive Launcher Icon**, serta **Native & In-App Splash Screen**.
- Halaman **Profil & Setting** mendukung ubah nama/bio profil dan kustomisasi **Avatar** (8 Karakter Avatar Preset, Upload Foto dari galeri/file, atau Avatar akun Hallsem).

---

## 📖 Cara Input Playlist M3U di Aplikasi

Anda dapat memasukkan playlist M3U melalui **3 cara**:

### Cara 1: Input Alamat Link / URL M3U (Online & IPTV)
1. Buka tab **M3U** di bilah navigasi bawah (atau tekan ikon **`+ Playlist M3U`** di halaman Beranda).
2. Pilih tab **Alamat Link**.
3. Isi **Nama Playlist** *(opsional, misalnya: `TV Indonesia`)*.
4. Tempelkan satu atau beberapa link M3U (satu URL per baris jika lebih dari satu) pada kolom **Alamat Link M3U**, lalu tekan **Simpan Link M3U**.

**Contoh Link M3U TV Indonesia Siap Pakai:**
```text
https://iptv-org.github.io/iptv/countries/id.m3u
```

> **Tips:** Saat memutar channel dari link di atas (misalnya `tvOne HD (720p)`), aplikasi otomatis membuka **M3U Video & Live TV Player** lengkap dengan daftar pencarian channel di bawah layar.

### Cara 2: Impor File `.m3u` / `.m3u8` Lokal (Offline)
1. Buka tab **M3U** → tekan **Impor File M3U**.
2. Pilih satu atau beberapa file `.m3u` / `.m3u8` dari penyimpanan HP Anda sekaligus.
3. Playlist otomatis tersimpan di aplikasi dan siap diputar secara offline.

### Cara 3: Deteksi Otomatis dari Direktori Musik
1. Buka tab **Direktori** → tekan **Izin & Scan** atau **Tambah Direktori**.
2. Jika di dalam folder terdapat file `.m3u` / `.m3u8`, aplikasi akan menampilkan banner **"Ditemukan File M3U di Direktori"** — tekan **Impor Semua** untuk memasukkannya langsung ke daftar playlist.

---

## 🛠️ Cara Build Release APK

```bat
build_release.bat
```
Atau langsung via CLI:
```powershell
.\build_release.bat -BumpType patch
```
Output APK split per ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`), `latest.json`, dan catatan rilis otomatis dibuat di `public/release/<versi>/` dan `releases/v<versi>/`.

---

## 👨‍💻 Informasi Developer

- **Nama**: **Zusfan Mashuri**
- **Peran**: Marketing Strategist • IT Builder • Public Service Innovator
- **Digital Business Card**: https://zusfan.hallosemarang.com
- **Website**: https://www.hallosemarang.com
- **WhatsApp**: https://wa.me/628998813000
- **Repository**: https://github.com/zusfan-ops/Musik-Player
