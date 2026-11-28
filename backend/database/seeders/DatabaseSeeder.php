<?php

namespace Database\Seeders;

use App\Models\Announcement;
use App\Models\AppRelease;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /**
     * Seeds only safe public sample announcements and release metadata.
     * Never creates default admin accounts with hardcoded passwords.
     */
    public function run(): void
    {
        Announcement::firstOrCreate(
            ['title' => 'Selamat Datang di MediaCenter'],
            [
                'body' => 'Aplikasi tetap berfungsi penuh secara offline tanpa akun. Login bersifat opsional untuk sinkronisasi playlist & favorit lintas perangkat.',
                'type' => 'info',
                'is_active' => true,
                'sort_order' => 1,
            ]
        );

        AppRelease::firstOrCreate(
            ['version' => '1.12.1', 'platform' => 'android', 'abi' => 'arm64-v8a'],
            [
                'build_number' => 37,
                'download_url' => 'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.12.1/M3UMusik-v1.12.1-arm64-v8a.apk',
                'release_notes' => 'Pembaruan rilis v1.12.1 (Android Mobile, Android TV & Windows).',
                'is_active' => true,
                'published_at' => now(),
            ]
        );

        AppRelease::firstOrCreate(
            ['version' => '1.12.1', 'platform' => 'android_tv', 'abi' => 'arm64-v8a'],
            [
                'build_number' => 37,
                'download_url' => 'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.12.1/MediaCenter-TV-v1.12.1-arm64-v8a.apk',
                'release_notes' => 'Edisi Android TV Apple TV-style UI + libmpv.',
                'is_active' => true,
                'published_at' => now(),
            ]
        );

        AppRelease::firstOrCreate(
            ['version' => '1.12.1', 'platform' => 'windows', 'abi' => 'x64'],
            [
                'build_number' => 37,
                'download_url' => 'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.12.1/MediaCenter-Setup-v1.12.1-x64.exe',
                'release_notes' => 'Installer Windows Desktop 64-bit.',
                'is_active' => true,
                'published_at' => now(),
            ]
        );
    }
}
