<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MediaCenter — Unduh untuk Windows, Android &amp; Android TV</title>
    <meta name="description" content="MediaCenter {{ $release['tag'] }} untuk Windows, Android Mobile, dan Android TV. Live TV IPTV, CCTV Kota, Jellyfin Cinema, YouTube, dan Musik.">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #000000;
            --surface: #0e0e0e;
            --surface-2: #161616;
            --border: #242424;
            --border-hover: #3a3a3a;
            --text: #ffffff;
            --text-muted: #9a9a9e;
            --text-dim: #636366;
            --accent: #e50914;
            --accent-hover: #c80812;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }
        html { scroll-behavior: smooth; background: var(--bg); color: var(--text); }
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.55;
            -webkit-font-smoothing: antialiased;
        }
        .mono { font-family: 'JetBrains Mono', ui-monospace, SFMono-Regular, monospace; }

        .wrap {
            max-width: 1160px;
            margin: 0 auto;
            padding: 0 24px;
        }

        /* Header: Apple TV / Netflix minimalist bar */
        header {
            position: sticky;
            top: 0;
            z-index: 40;
            background: rgba(0, 0, 0, 0.88);
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border-bottom: 1px solid var(--border);
        }
        .header-inner {
            display: flex;
            align-items: center;
            justify-content: space-between;
            height: 64px;
            gap: 24px;
        }
        .logo {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            text-decoration: none;
            color: var(--text);
            font-weight: 800;
            font-size: 15px;
            letter-spacing: 0.04em;
            text-transform: uppercase;
        }
        .logo-dot {
            width: 10px;
            height: 10px;
            background: var(--accent);
            display: inline-block;
        }
        nav {
            display: flex;
            align-items: center;
            gap: 28px;
        }
        nav a {
            color: var(--text-muted);
            text-decoration: none;
            font-size: 13.5px;
            font-weight: 500;
            transition: color 0.15s ease;
        }
        nav a:hover { color: var(--text); }
        .header-btn {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: var(--text);
            color: #000000;
            text-decoration: none;
            font-size: 13px;
            font-weight: 700;
            padding: 9px 18px;
            border-radius: 999px;
            transition: opacity 0.15s ease;
        }
        .header-btn:hover { opacity: 0.88; }

        /* Hero: Left-aligned editorial layout */
        .hero {
            padding: 76px 0 72px;
            border-bottom: 1px solid var(--border);
        }
        .hero-grid {
            display: grid;
            grid-template-columns: 1.15fr 0.85fr;
            gap: 48px;
            align-items: center;
        }
        .release-meta {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            font-size: 12.5px;
            font-weight: 600;
            color: var(--text-muted);
            margin-bottom: 20px;
            letter-spacing: 0.02em;
        }
        .release-tag {
            color: var(--text);
            background: var(--surface-2);
            border: 1px solid var(--border);
            padding: 3px 10px;
            border-radius: 4px;
        }
        .hero h1 {
            font-size: clamp(2.4rem, 4.8vw, 3.85rem);
            font-weight: 800;
            letter-spacing: -0.035em;
            line-height: 1.06;
            color: var(--text);
            margin-bottom: 20px;
        }
        .hero p {
            font-size: 17px;
            color: var(--text-muted);
            max-width: 520px;
            margin-bottom: 32px;
        }
        .hero-actions {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 14px;
        }
        .btn-primary {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            background: var(--accent);
            color: #ffffff;
            text-decoration: none;
            font-size: 14.5px;
            font-weight: 700;
            padding: 14px 26px;
            border-radius: 6px;
            transition: background 0.15s ease;
        }
        .btn-primary:hover { background: var(--accent-hover); }
        .btn-secondary {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: transparent;
            color: var(--text);
            border: 1px solid var(--border-hover);
            text-decoration: none;
            font-size: 14.5px;
            font-weight: 600;
            padding: 13px 22px;
            border-radius: 6px;
            transition: border-color 0.15s ease, background 0.15s ease;
        }
        .btn-secondary:hover {
            border-color: var(--text);
            background: var(--surface);
        }

        /* Right Hero: Clean Platform Spec List (Apple / Spotify style) */
        .spec-panel {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 10px;
            overflow: hidden;
        }
        .spec-head {
            padding: 14px 20px;
            border-bottom: 1px solid var(--border);
            display: flex;
            align-items: center;
            justify-content: space-between;
            font-size: 12px;
            color: var(--text-muted);
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }
        .spec-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
            padding: 16px 20px;
            border-bottom: 1px solid var(--border);
            text-decoration: none;
            color: inherit;
            transition: background 0.15s ease;
        }
        .spec-row:last-child { border-bottom: 0; }
        .spec-row:hover { background: var(--surface-2); }
        .spec-title { font-size: 14.5px; font-weight: 700; color: var(--text); }
        .spec-sub { font-size: 12.5px; color: var(--text-muted); margin-top: 2px; }
        .spec-action {
            font-size: 12px;
            font-weight: 700;
            color: var(--text);
            padding: 6px 12px;
            border: 1px solid var(--border-hover);
            border-radius: 999px;
            white-space: nowrap;
        }

        /* Section */
        .section {
            padding: 72px 0;
            border-bottom: 1px solid var(--border);
        }
        .section-title {
            font-size: clamp(1.65rem, 3vw, 2.25rem);
            font-weight: 800;
            letter-spacing: -0.03em;
            margin-bottom: 10px;
        }
        .section-desc {
            font-size: 15px;
            color: var(--text-muted);
            max-width: 600px;
            margin-bottom: 36px;
        }

        /* Download Center */
        .tabs {
            display: inline-flex;
            flex-wrap: wrap;
            gap: 4px;
            padding: 4px;
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 8px;
            margin-bottom: 24px;
        }
        .tab-btn {
            border: 0;
            background: transparent;
            color: var(--text-muted);
            font-family: inherit;
            font-size: 13.5px;
            font-weight: 600;
            padding: 10px 18px;
            border-radius: 6px;
            cursor: pointer;
            transition: all 0.15s ease;
        }
        .tab-btn:hover { color: var(--text); }
        .tab-btn.active {
            background: var(--text);
            color: #000000;
        }

        .panel { display: none; }
        .panel.active { display: block; }

        .asset-list {
            border: 1px solid var(--border);
            border-radius: 10px;
            overflow: hidden;
            background: var(--surface);
        }
        .asset-item {
            display: grid;
            grid-template-columns: 1.5fr 1fr auto;
            align-items: center;
            gap: 20px;
            padding: 20px 24px;
            border-bottom: 1px solid var(--border);
        }
        .asset-item:last-child { border-bottom: 0; }
        .asset-name-row {
            display: flex;
            align-items: center;
            gap: 10px;
            flex-wrap: wrap;
            margin-bottom: 4px;
        }
        .asset-arch {
            font-size: 16px;
            font-weight: 700;
            color: var(--text);
        }
        .badge-rec {
            font-size: 11px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.04em;
            padding: 2px 8px;
            border-radius: 4px;
            background: var(--accent);
            color: #ffffff;
        }
        .badge-std {
            font-size: 11px;
            font-weight: 600;
            padding: 2px 8px;
            border-radius: 4px;
            background: var(--surface-2);
            border: 1px solid var(--border);
            color: var(--text-muted);
        }
        .asset-desc { font-size: 13.5px; color: var(--text-muted); }
        .asset-file {
            font-size: 12.5px;
            color: var(--text-muted);
            word-break: break-all;
        }
        .asset-size {
            font-size: 12px;
            color: var(--text-dim);
            margin-top: 4px;
        }
        .dl-link {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            padding: 11px 20px;
            border-radius: 6px;
            text-decoration: none;
            font-size: 13.5px;
            font-weight: 700;
            white-space: nowrap;
            background: var(--surface-2);
            color: var(--text);
            border: 1px solid var(--border-hover);
            transition: all 0.15s ease;
        }
        .dl-link:hover {
            background: var(--text);
            color: #000000;
            border-color: var(--text);
        }
        .asset-item.recommended .dl-link {
            background: var(--text);
            color: #000000;
            border-color: var(--text);
        }
        .asset-item.recommended .dl-link:hover {
            opacity: 0.88;
        }

        /* Editorial Capability Rows (No icon boxes) */
        .cap-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 1px;
            background: var(--border);
            border: 1px solid var(--border);
            border-radius: 10px;
            overflow: hidden;
        }
        .cap-cell {
            background: var(--surface);
            padding: 28px;
        }
        .cap-num {
            font-size: 12px;
            font-weight: 600;
            color: var(--text-dim);
            margin-bottom: 10px;
        }
        .cap-cell h3 {
            font-size: 18px;
            font-weight: 700;
            margin-bottom: 8px;
        }
        .cap-cell p {
            font-size: 14px;
            color: var(--text-muted);
        }

        /* Guide */
        .guide-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 20px;
        }
        .guide-card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 10px;
            padding: 24px;
        }
        .guide-card h3 {
            font-size: 15.5px;
            font-weight: 700;
            margin-bottom: 14px;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--border);
        }
        .guide-card ol {
            padding-left: 18px;
            display: grid;
            gap: 10px;
            font-size: 13.5px;
            color: var(--text-muted);
        }
        .guide-card strong { color: var(--text); font-weight: 600; }
        .adb-box {
            margin-top: 14px;
            padding: 12px;
            background: #000000;
            border: 1px solid var(--border);
            border-radius: 6px;
            font-size: 12px;
            color: #d4d4d8;
            overflow-x: auto;
            line-height: 1.65;
        }

        /* Footer */
        footer {
            padding: 36px 0 48px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex-wrap: wrap;
            gap: 16px;
            font-size: 13px;
            color: var(--text-dim);
        }
        .footer-links {
            display: flex;
            align-items: center;
            gap: 22px;
            flex-wrap: wrap;
        }
        .footer-links a {
            color: var(--text-muted);
            text-decoration: none;
        }
        .footer-links a:hover { color: var(--text); }

        @media (max-width: 900px) {
            .hero-grid { grid-template-columns: 1fr; gap: 36px; }
            .asset-item { grid-template-columns: 1fr; gap: 12px; }
            .guide-grid { grid-template-columns: 1fr; }
        }
        @media (max-width: 640px) {
            nav { display: none; }
            .cap-grid { grid-template-columns: 1fr; }
            .hero { padding: 48px 0; }
            .section { padding: 52px 0; }
        }
    </style>
</head>
<body>
    <header>
        <div class="wrap header-inner">
            <a href="#top" class="logo">
                <span class="logo-dot"></span>
                <span>MediaCenter</span>
            </a>

            <nav>
                <a href="#download">Installer</a>
                <a href="#fitur">Kemampuan</a>
                <a href="#panduan">Panduan</a>
                <a href="{{ $githubReleasesUrl }}" target="_blank" rel="noopener noreferrer">GitHub Releases</a>
            </nav>

            <a href="#download" class="header-btn">Unduh {{ $release['tag'] }}</a>
        </div>
    </header>

    <main id="top" class="wrap">
        @php
            $pickPrimary = function (array $items) use ($release): array {
                foreach ($items as $item) {
                    if (!empty($item['recommended'])) {
                        return $item;
                    }
                }

                return $items[0] ?? [
                    'name' => $release['name'],
                    'url' => $release['html_url'],
                    'size' => '',
                ];
            };

            $primaryWin = $pickPrimary($release['groups']['windows'] ?? []);
            $primaryMobile = $pickPrimary($release['groups']['android_mobile'] ?? []);
            $primaryTv = $pickPrimary($release['groups']['android_tv'] ?? []);
        @endphp

        <!-- Hero -->
        <section class="hero">
            <div class="hero-grid">
                <div>
                    <div class="release-meta">
                        <span class="release-tag mono">{{ $release['tag'] }}</span>
                        <span>Diperbarui {{ $release['published_date'] }}</span>
                    </div>

                    <h1>Televisi, Film, CCTV, Musik &amp; Produktivitas dalam Satu Aplikasi.</h1>
                    <p>
                        Aplikasi terpadu untuk Windows, Android, dan Android TV. Nikmati Live TV IPTV auto-sync, CCTV kota real-time, Jellyfin Cinema, YouTube Background Play &amp; PiP, pemutar musik offline, hingga modul POS &amp; Keuangan.
                    </p>

                    <div class="hero-actions">
                        <a id="smart-hero-cta" href="{{ $primaryWin['url'] }}" class="btn-primary" rel="noopener noreferrer">
                            <span id="smart-hero-label">Unduh MediaCenter {{ $release['tag'] }}</span>
                        </a>
                        <a href="{{ $release['html_url'] }}" target="_blank" rel="noopener noreferrer" class="btn-secondary">
                            <span>Pilih Varian Lainnya</span>
                        </a>
                    </div>
                </div>

                <div class="spec-panel">
                    <div class="spec-head">
                        <span>Unduh Langsung dari GitHub Releases</span>
                        <span class="mono">{{ $release['tag'] }}</span>
                    </div>
                    <a href="{{ $primaryWin['url'] }}" class="spec-row" rel="noopener noreferrer">
                        <div>
                            <div class="spec-title">Windows Desktop</div>
                            <div class="spec-sub mono">{{ $primaryWin['name'] }}</div>
                        </div>
                        <span class="spec-action mono">x64 &bull; {{ $primaryWin['size'] }}</span>
                    </a>
                    <a href="{{ $primaryMobile['url'] }}" class="spec-row" rel="noopener noreferrer">
                        <div>
                            <div class="spec-title">Android Mobile &amp; Tablet</div>
                            <div class="spec-sub mono">{{ $primaryMobile['name'] }}</div>
                        </div>
                        <span class="spec-action mono">APK &bull; {{ $primaryMobile['size'] }}</span>
                    </a>
                    <a href="{{ $primaryTv['url'] }}" class="spec-row" rel="noopener noreferrer">
                        <div>
                            <div class="spec-title">Android TV &amp; Google TV</div>
                            <div class="spec-sub mono">{{ $primaryTv['name'] }}</div>
                        </div>
                        <span class="spec-action mono">TV &bull; {{ $primaryTv['size'] }}</span>
                    </a>
                </div>
            </div>
        </section>

        <!-- Download Center -->
        <section id="download" class="section">
            <h2 class="section-title">Unduh Installer {{ $release['name'] }}</h2>
            <p class="section-desc">
                Semua berkas diunduh langsung dari repositori resmi
                <a href="{{ $release['html_url'] }}" target="_blank" rel="noopener noreferrer" style="color:#fff; text-decoration:underline;">GitHub Releases ({{ $release['tag'] }})</a>.
            </p>

            <div class="tabs" role="tablist" aria-label="Pilih Platform">
                <button class="tab-btn active" data-tab="windows" role="tab" aria-selected="true">Windows (.exe)</button>
                <button class="tab-btn" data-tab="android_mobile" role="tab" aria-selected="false">Android Mobile (.apk)</button>
                <button class="tab-btn" data-tab="android_tv" role="tab" aria-selected="false">Android TV (.apk)</button>
            </div>

            @foreach (['windows', 'android_mobile', 'android_tv'] as $platformKey)
                <div id="panel-{{ $platformKey }}" class="panel {{ $platformKey === 'windows' ? 'active' : '' }}" role="tabpanel">
                    <div class="asset-list">
                        @foreach ($release['groups'][$platformKey] as $asset)
                            <div class="asset-item {{ $asset['recommended'] ? 'recommended' : '' }}">
                                <div>
                                    <div class="asset-name-row">
                                        <span class="asset-arch">{{ $asset['arch'] }}</span>
                                        <span class="{{ $asset['recommended'] ? 'badge-rec' : 'badge-std' }}">{{ $asset['badge'] }}</span>
                                    </div>
                                    <p class="asset-desc">{{ $asset['description'] }}</p>
                                </div>

                                <div>
                                    <div class="asset-file mono">{{ $asset['name'] }}</div>
                                    <div class="asset-size mono">Ukuran: {{ $asset['size'] }}</div>
                                </div>

                                <a href="{{ $asset['url'] }}" class="dl-link" rel="noopener noreferrer">
                                    <span>Unduh</span>
                                    <span class="mono" style="font-size:12px;">({{ $asset['size'] }})</span>
                                </a>
                            </div>
                        @endforeach
                    </div>
                </div>
            @endforeach
        </section>

        <!-- Capabilities -->
        <section id="fitur" class="section">
            <h2 class="section-title">Semua Fitur dalam Satu Ekosistem</h2>
            <p class="section-desc">Dari hiburan layar lebar hingga manajemen usaha harian — dirancang ringan, konsisten dalam mode gelap, dan bebas iklan.</p>

            <div class="cap-grid">
                <div class="cap-cell">
                    <div class="cap-num mono">01 / TV STREAMING &amp; IPTV</div>
                    <h3>Live TV &amp; Auto-Sync M3U GitHub</h3>
                    <p>Tonton saluran TV Indonesia &amp; internasional dengan pemutar split portrait maupun fullscreen landscape. Daftar channel M3U otomatis tersinkronisasi dari GitHub lengkap dengan notifikasi pembaruan di aplikasi.</p>
                </div>
                <div class="cap-cell">
                    <div class="cap-num mono">02 / CCTV KOTA REAL-TIME</div>
                    <h3>Pantau Kamera Lalu Lintas Daerah</h3>
                    <p>Akses live stream CCTV per kota (Jakarta, Jogja, Semarang, Bima, Mataram, Magetan) langsung dari tab TV &amp; CCTV tanpa konfigurasi manual.</p>
                </div>
                <div class="cap-cell">
                    <div class="cap-num mono">03 / FILM &amp; HALLSEM CINEMA</div>
                    <h3>Streaming Film &amp; Serial Jellyfin</h3>
                    <p>Terintegrasi dengan server Jellyfin / Hallsem Cinema lengkap dengan daftar Lanjutkan Menonton, pencarian judul &amp; genre, Direct Play + fallback HLS, kontrol kecepatan putar, serta rasio layar.</p>
                </div>
                <div class="cap-cell">
                    <div class="cap-num mono">04 / YOUTUBE &amp; BACKGROUND PLAY</div>
                    <h3>YouTube Shorts, PiP &amp; Putar di Latar Belakang</h3>
                    <p>Putar video YouTube dan Shorts dengan dukungan <strong>Background Play</strong> agar audio tetap berjalan saat layar mati atau berpindah aplikasi, serta mode <strong>Picture-in-Picture (PiP)</strong>.</p>
                </div>
                <div class="cap-cell">
                    <div class="cap-num mono">05 / MUSIK OFFLINE &amp; M3U AUDIO</div>
                    <h3>Pemindai Direktori &amp; Audio Hi-Fi</h3>
                    <p>Pindai folder musik lokal otomatis (.mp3, .flac, .m4a, .wav, .opus, dll.) dengan kontrol Shuffle, Repeat, Sleep Timer, antrean putar, serta simpan audio M3U untuk diputar offline.</p>
                </div>
                <div class="cap-cell">
                    <div class="cap-num mono">06 / POINT OF SALE (POS)</div>
                    <h3>Kasir &amp; Pencatatan Penjualan</h3>
                    <p>Modul POS terintegrasi di aplikasi Mobile &amp; Desktop untuk mengelola produk, keranjang transaksi, dan pencatatan penjualan harian secara cepat. <em>(Khusus Mobile &amp; Desktop).</em></p>
                </div>
                <div class="cap-cell">
                    <div class="cap-num mono">07 / FINANCE &amp; KEUANGAN</div>
                    <h3>Laporan Arus Kas Terpadu</h3>
                    <p>Pantau pemasukan, pengeluaran, dan ringkasan keuangan langsung dari dalam aplikasi tanpa perlu berpindah software akuntansi terpisah. <em>(Khusus Mobile &amp; Desktop).</em></p>
                </div>
                <div class="cap-cell">
                    <div class="cap-num mono">08 / ANDROID TV &amp; AUTO-UPDATE</div>
                    <h3>Edisi 10-Foot &amp; Pembaruan Otomatis</h3>
                    <p>Versi khusus Android TV / Google TV hadir dengan antarmuka ramah remote D-pad tanpa menu POS &amp; Keuangan. Seluruh versi (Windows, Android, Android TV) mendukung auto-update dari GitHub Releases.</p>
                </div>
            </div>
        </section>

        <!-- Installation Guide -->
        <section id="panduan" class="section" style="border-bottom:0;">
            <h2 class="section-title">Panduan Instalasi</h2>
            <p class="section-desc">Langkah singkat pemasangan sesuai perangkat yang Anda gunakan.</p>

            <div class="guide-grid">
                <div class="guide-card">
                    <h3>Windows Desktop</h3>
                    <ol>
                        <li>Unduh berkas <strong>MediaCenter-Setup-*.exe</strong> pada tab Windows.</li>
                        <li>Jalankan installer. Jika muncul peringatan Windows SmartScreen, klik <strong>More info</strong> lalu <strong>Run anyway</strong>.</li>
                        <li>Ikuti wizard hingga selesai dan buka aplikasi dari Start Menu.</li>
                    </ol>
                </div>

                <div class="guide-card">
                    <h3>Android HP &amp; Tablet</h3>
                    <ol>
                        <li>Pilih varian <strong>arm64-v8a</strong> untuk mayoritas perangkat modern, atau <strong>armeabi-v7a</strong> untuk perangkat 32-bit.</li>
                        <li>Buka file APK dari File Manager dan aktifkan izin <strong>Allow from this source</strong>.</li>
                        <li>Ketuk <strong>Install</strong> hingga proses selesai.</li>
                    </ol>
                </div>

                <div class="guide-card">
                    <h3>Android TV &amp; STB</h3>
                    <ol>
                        <li>Kirim <strong>MediaCenter-TV-*.apk</strong> ke TV melalui flashdisk atau aplikasi <em>Send Files to TV</em>, lalu pasang setelah mengaktifkan <em>Unknown Sources</em>.</li>
                        <li>Atau pasang langsung dari PC melalui ADB:</li>
                    </ol>
                    <pre class="adb-box mono">adb connect &lt;IP_TV&gt;:5555
adb install -r MediaCenter-TV-{{ $release['tag'] }}-arm64-v8a.apk</pre>
                </div>
            </div>
        </section>

        <footer>
            <div>
                <strong style="color:#fff;">MediaCenter</strong> &mdash; Rilis {{ $release['tag'] }} ({{ $release['published_date'] }})
            </div>
            <div class="footer-links">
                <a href="{{ $githubReleasesUrl }}" target="_blank" rel="noopener noreferrer">GitHub Releases</a>
                <a href="/api/v1/app-config">API Config</a>
                <a href="{{ route('admin.dashboard') }}">Admin Console</a>
            </div>
        </footer>
    </main>

    <script>
        (function () {
            const buttons = document.querySelectorAll('.tab-btn');
            const panels = document.querySelectorAll('.panel');

            function activateTab(key) {
                buttons.forEach((btn) => {
                    const isActive = btn.dataset.tab === key;
                    btn.classList.toggle('active', isActive);
                    btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
                });
                panels.forEach((panel) => {
                    panel.classList.toggle('active', panel.id === 'panel-' + key);
                });
            }

            buttons.forEach((btn) => {
                btn.addEventListener('click', () => activateTab(btn.dataset.tab));
            });

            const releaseTag = @json($release['tag']);
            const downloadUrls = @json(['windows' => $primaryWin['url'], 'android_mobile' => $primaryMobile['url'], 'android_tv' => $primaryTv['url']]);
            const ua = navigator.userAgent.toLowerCase();
            const heroCta = document.getElementById('smart-hero-cta');
            const heroLabel = document.getElementById('smart-hero-label');
            if (/android.*tv|googletv|bravia|aft|shield/i.test(ua)) {
                activateTab('android_tv');
                if (heroCta) heroCta.setAttribute('href', downloadUrls.android_tv);
                if (heroLabel) heroLabel.textContent = 'Unduh untuk Android TV (' + releaseTag + ')';
            } else if (/android/i.test(ua)) {
                activateTab('android_mobile');
                if (heroCta) heroCta.setAttribute('href', downloadUrls.android_mobile);
                if (heroLabel) heroLabel.textContent = 'Unduh untuk Android (' + releaseTag + ')';
            } else if (/windows/i.test(ua)) {
                activateTab('windows');
                if (heroCta) heroCta.setAttribute('href', downloadUrls.windows);
                if (heroLabel) heroLabel.textContent = 'Unduh untuk Windows (' + releaseTag + ')';
            }
        })();
    </script>
</body>
</html>
