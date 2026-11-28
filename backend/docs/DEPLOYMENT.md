# Panduan Instalasi, Deployment HTTPS, Backup & Keamanan Backend

## 1. Prasyarat Server
- PHP 8.2+ (`pdo_mysql`, `mbstring`, `openssl`, `curl`, `tokenizer`, `xml`)
- Composer 2.x
- MySQL 8.0+ / MariaDB 10.6+
- Nginx dengan sertifikat TLS/HTTPS (mis. Let's Encrypt) untuk `https://mediacenter.ordr.my.id`

## 2. Instalasi Awal
```bash
cd /var/www/mediacenter-backend
composer install --no-dev --optimize-autoloader
cp .env.example .env
php artisan key:generate
php artisan migrate --force
php artisan db:seed --force
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

### Membuat Akun Admin Pertama
Tidak ada akun admin bawaan dengan password hardcoded. Buat admin melalui CLI:
```bash
php artisan app:create-admin --email=admin@ordr.my.id --name="Super Admin" --role=super_admin
```
Panel admin dapat diakses di `https://mediacenter.ordr.my.id/admin`.

## 3. Mode SMTP / Tanpa Email
- **Dengan SMTP:** isi `MAIL_MAILER=smtp`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, dan `MAIL_FROM_ADDRESS` di `.env` agar verifikasi email & reset kata sandi terkirim.
- **Tanpa SMTP:** set `MAIL_MAILER=log`. Registrasi tetap berjalan normal tanpa memblokir pengguna.

## 4. Konfigurasi Nginx (HTTPS Wajib)
```nginx
server {
    listen 443 ssl http2;
    server_name mediacenter.ordr.my.id;

    ssl_certificate     /etc/letsencrypt/live/mediacenter.ordr.my.id/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mediacenter.ordr.my.id/privkey.pem;

    root /var/www/mediacenter-backend/public;
    index index.php;

    client_max_body_size 2M;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```

## 5. Retensi Analitik & Cron Job
Tambahkan cron job Laravel scheduler tiap menit:
```cron
* * * * * cd /var/www/mediacenter-backend && php artisan schedule:run >> /dev/null 2>&1
```
Untuk membersihkan event analitik secara manual:
```bash
php artisan analytics:prune
```

## 6. Backup & Restore MySQL
Backup harian:
```bash
mysqldump --single-transaction -u mediacenter -p mediacenter_db | gzip > /backups/mediacenter_$(date +%F).sql.gz
```
Restore:
```bash
gunzip < /backups/mediacenter_2026-11-28.sql.gz | mysql -u mediacenter -p mediacenter_db
```

## 7. Penyimpanan Token Aman di Klien Flutter
- Token Sanctum **tidak** disimpan di `SharedPreferences`.
- Klien Flutter menyimpan `auth_token` di `FlutterSecureStorage` (Android Keystore / Windows Credential Manager).
- ID instalasi analitik disimpan sebagai UUID acak yang dapat direset atau dihapus kapan saja oleh pengguna.
