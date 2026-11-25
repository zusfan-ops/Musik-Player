# M3U Musik & Jellyfin Cinema Player (Flutter Android)

Aplikasi Android **Musik Player Offline, Multi-Playlist M3U & Pemutar Film Jellyfin** dengan desain antarmuka kombinasi **Netflix x Spotify** dan identitas visual [logo2.png](file:///d:/www/musik/logo2.png) untuk logo aplikasi, launcher icon, serta native splash screen.

## Fitur Utama
- **Identitas `logo2.png`**: Digunakan penuh pada logo aplikasi, Android adaptive launcher icon, serta native & in-app splash screen.
- **Pemutar Musik Offline & Online (`just_audio` + `audio_session`)**: Play/Pause, Next/Prev, Shuffle, Repeat (Off/All/One), Seekbar, Kecepatan Putar (`0.75x`–`2.0x`), Sleep Timer, Antrean Aktif, dan Favorit.
- **Akses & Pengelompokan Berdasarkan Direktori**: Scan otomatis folder musik Android (`Music`, `Download`, `Audio`, `Podcasts`, SD Card) maupun tambah banyak folder kustom (`+ Tambah Direktori`), lengkap dengan deteksi otomatis file `.m3u`/`.m3u8`.
- **Multi-Playlist M3U (File Lokal & Alamat Link)**:
  - Impor **satu atau banyak file `.m3u` / `.m3u8`** sekaligus dari penyimpanan lokal untuk mode offline penuh.
  - Tambah **satu atau banyak alamat link URL M3U** (`http://` / `https://`) sekaligus, lengkap dengan sinkronisasi ulang dan fitur **Simpan Audio ke Offline**.
- **Halaman Profil, Avatar & Integrasi Film Jellyfin**:
  - **Atur Profil & Avatar**: Ubah nama/bio profil, pilih dari **8 Karakter Preset Avatar**, unggah **Foto Avatar Kustom** dari galeri/file, atau gunakan **Avatar Akun Jellyfin**.
  - **Input API Code Jellyfin & Putar Film (`video_player`)**: Masukkan Server URL & API Code Jellyfin (tersimpan terenkripsi di Android Keystore via `flutter_secure_storage`) untuk memuat katalog film & memutar film langsung dengan pemutar video layar penuh (*Direct Play* & *HLS Universal Stream* fallback, kontrol kecepatan, rasio layar, dan simpan progres tontonan).

## Cara Build Release (Seperti Project `rif`)
Jalankan menu interaktif:
```bat
build_release.bat
```
Atau langsung via CLI:
```powershell
.\build_release.bat -BumpType none
```
Hasil build otomatis tersimpan di:
- `public/release/<versi>/` (beserta `latest.json`, `release_notes.txt`, dan `index.php`)
- `releases/v<versi>/`
