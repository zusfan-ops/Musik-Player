<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Panel — MediaCenter</title>
    <style>
        :root {
            --bg: #090b10;
            --sidebar: #0e1118;
            --surface: #141822;
            --surface-2: #1b202d;
            --border: #252b3b;
            --text: #f3f4f6;
            --muted: #9ca3af;
            --accent: #e50914;
            --green: #1db954;
        }
        * { box-sizing: border-box; }
        body {
            font-family: 'Inter', system-ui, -apple-system, sans-serif;
            background: var(--bg);
            color: var(--text);
            margin: 0;
            min-height: 100vh;
            display: flex;
        }
        .sidebar {
            width: 260px;
            flex-shrink: 0;
            background: var(--sidebar);
            border-right: 1px solid var(--border);
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            padding: 20px 14px;
            position: sticky;
            top: 0;
            height: 100vh;
        }
        .brand {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 6px 10px 18px;
            border-bottom: 1px solid var(--border);
            margin-bottom: 14px;
        }
        .brand-dot { width: 10px; height: 10px; background: var(--accent); border-radius: 2px; }
        .brand-title { font-weight: 800; font-size: 15px; letter-spacing: 0.02em; }
        .brand-sub { font-size: 11.5px; color: var(--muted); }
        .nav-list { display: flex; flex-direction: column; gap: 4px; }
        .nav-btn {
            width: 100%;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            background: transparent;
            color: var(--muted);
            border: 0;
            border-radius: 9px;
            padding: 10px 12px;
            font-size: 13.5px;
            font-weight: 600;
            cursor: pointer;
            text-align: left;
            transition: background 0.15s ease, color 0.15s ease;
        }
        .nav-btn:hover { background: var(--surface); color: var(--text); }
        .nav-btn.active { background: var(--surface-2); color: #fff; border: 1px solid var(--border); }
        .nav-badge {
            font-size: 11px;
            padding: 2px 7px;
            border-radius: 999px;
            background: var(--surface);
            border: 1px solid var(--border);
            color: var(--muted);
        }
        .sidebar-foot {
            border-top: 1px solid var(--border);
            padding-top: 14px;
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .side-link {
            display: block;
            text-decoration: none;
            color: var(--muted);
            font-size: 12.5px;
            padding: 6px 10px;
            border-radius: 8px;
        }
        .side-link:hover { background: var(--surface); color: #fff; }
        .main {
            flex: 1;
            min-width: 0;
            padding: 26px 32px;
        }
        .topbar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 16px;
            margin-bottom: 22px;
            flex-wrap: wrap;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 14px;
            margin-bottom: 22px;
        }
        .card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 14px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .card h2 { margin: 0 0 14px; font-size: 16px; }
        .stat-label { color: var(--muted); font-size: 12px; margin-bottom: 6px; }
        .stat-val { font-size: 26px; font-weight: 800; }
        table { width: 100%; border-collapse: collapse; font-size: 13px; }
        th, td { text-align: left; padding: 10px; border-bottom: 1px solid var(--border); vertical-align: middle; }
        th { color: var(--muted); font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; }
        input, select, textarea {
            background: var(--bg);
            color: #fff;
            border: 1px solid #30374a;
            border-radius: 8px;
            padding: 9px 11px;
            margin-bottom: 10px;
            width: 100%;
            font-size: 13.5px;
        }
        .form-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
        button.btn, .btn {
            background: var(--accent);
            color: #fff;
            border: 0;
            border-radius: 8px;
            padding: 9px 15px;
            font-weight: 700;
            font-size: 13px;
            cursor: pointer;
        }
        .btn-sec { background: #262c3d; color: #fff; border: 0; border-radius: 8px; padding: 7px 12px; font-weight: 600; font-size: 12.5px; cursor: pointer; }
        .status {
            background: rgba(29,185,84,.14);
            border: 1px solid var(--green);
            padding: 11px 14px;
            border-radius: 10px;
            margin-bottom: 18px;
            font-size: 13.5px;
        }
        .err-box {
            background: rgba(229,9,20,.14);
            border: 1px solid var(--accent);
            padding: 11px 14px;
            border-radius: 10px;
            margin-bottom: 18px;
            font-size: 13.5px;
        }
        .panel { display: none; }
        .panel.active { display: block; }
        .pill {
            display: inline-block;
            font-size: 11px;
            font-weight: 700;
            padding: 3px 8px;
            border-radius: 999px;
            background: var(--surface-2);
            border: 1px solid var(--border);
        }
        @media (max-width: 860px) {
            body { flex-direction: column; }
            .sidebar { width: 100%; height: auto; position: static; border-right: 0; border-bottom: 1px solid var(--border); }
            .nav-list { flex-direction: row; flex-wrap: wrap; }
            .nav-btn { width: auto; }
            .main { padding: 18px 16px; }
        }
    </style>
</head>
<body>
    <aside class="sidebar">
        <div>
            <div class="brand">
                <span class="brand-dot"></span>
                <div>
                    <div class="brand-title">MEDIACENTER</div>
                    <div class="brand-sub">{{ $user->name }} ({{ $user->role }})</div>
                </div>
            </div>

            <nav class="nav-list" aria-label="Menu Admin">
                <button class="nav-btn active" data-panel="overview">
                    <span>Ringkasan</span>
                </button>
                <button class="nav-btn" data-panel="analytics">
                    <span>Analisa Pengguna</span>
                </button>
                @if ($user->hasAdminRole(['content_admin']))
                <button class="nav-btn" data-panel="m3u">
                    <span>Sumber M3U</span>
                    <span class="nav-badge">{{ $m3uSources->count() }}</span>
                </button>
                <button class="nav-btn" data-panel="announcements">
                    <span>Pengumuman</span>
                    <span class="nav-badge">{{ $announcements->count() }}</span>
                </button>
                <button class="nav-btn" data-panel="releases">
                    <span>Rilis Aplikasi</span>
                    <span class="nav-badge">{{ $releases->count() }}</span>
                </button>
                @endif
                @if ($user->hasAdminRole(['analytics_admin']))
                <button class="nav-btn" data-panel="feedback">
                    <span>Laporan &amp; Feedback</span>
                    <span class="nav-badge">{{ $feedbacks->where('status', 'open')->count() }}</span>
                </button>
                @endif
                <button class="nav-btn" data-panel="audit">
                    <span>Log Audit &amp; Pengguna</span>
                </button>
            </nav>
        </div>

        <div class="sidebar-foot">
            <a href="{{ route('landing') }}" class="side-link">Halaman Utama (Landing)</a>
            <form method="POST" action="{{ route('admin.logout') }}">
                @csrf
                <button class="btn-sec" style="width:100%;" type="submit">Keluar</button>
            </form>
        </div>
    </aside>

    <main class="main">
        <div class="topbar">
            <div>
                <h1 style="margin:0;font-size:21px;">MediaCenter Admin Console</h1>
                <small style="color:var(--muted);">Kelola M3U, rilis aplikasi, pengumuman, laporan, dan analitik dalam satu panel.</small>
            </div>
        </div>

        @if (session('status'))
            <div class="status">{{ session('status') }}</div>
        @endif
        @if ($errors->any())
            <div class="err-box">{{ $errors->first() }}</div>
        @endif

        <!-- Panel: Overview -->
        <section id="panel-overview" class="panel active">
            <div class="grid">
                <div class="card"><div class="stat-label">Sumber M3U Aktif</div><div class="stat-val">{{ $m3uSources->where('is_active', true)->count() }}</div></div>
                <div class="card"><div class="stat-label">Total Event Analitik</div><div class="stat-val">{{ $analyticsSummary['total_events'] }}</div></div>
                <div class="card"><div class="stat-label">Perangkat Aktif (7 Hari)</div><div class="stat-val">{{ $analyticsSummary['active_installations_7d'] }}</div></div>
                <div class="card"><div class="stat-label">Pengumuman Aktif</div><div class="stat-val">{{ $announcements->where('is_active', true)->count() }}</div></div>
                <div class="card"><div class="stat-label">Laporan Terbuka</div><div class="stat-val">{{ $feedbacks->where('status', 'open')->count() }}</div></div>
            </div>

            <div class="card">
                <h2>Ringkasan Analitik Platform</h2>
                <table>
                    <thead><tr><th>Platform</th><th>Total Event</th></tr></thead>
                    <tbody>
                    @forelse ($analyticsSummary['by_platform'] as $row)
                        <tr><td>{{ $row->platform }}</td><td>{{ $row->total }}</td></tr>
                    @empty
                        <tr><td colspan="2" style="color:var(--muted);">Belum ada event analitik.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>

        <!-- Panel: Analisa Pengguna & Durasi -->
        <section id="panel-analytics" class="panel">
            @php
                $totalSec = (int) ($analyticsSummary['total_duration_seconds'] ?? 0);
                $avgSec = (int) ($analyticsSummary['avg_duration_seconds'] ?? 0);
                $fmtDur = function (int $sec): string {
                    if ($sec < 60) return $sec . ' dtk';
                    $m = intdiv($sec, 60);
                    $s = $sec % 60;
                    if ($m < 60) return $m . ' mnt ' . $s . ' dtk';
                    $h = intdiv($m, 60);
                    return $h . ' jam ' . ($m % 60) . ' mnt';
                };
            @endphp
            <div class="grid">
                <div class="card"><div class="stat-label">Pengguna Terdaftar</div><div class="stat-val">{{ $analyticsSummary['total_users'] }}</div></div>
                <div class="card"><div class="stat-label">Perangkat Tersinkron</div><div class="stat-val">{{ $analyticsSummary['total_devices'] }}</div></div>
                <div class="card"><div class="stat-label">Aktif (24 Jam)</div><div class="stat-val">{{ $analyticsSummary['active_installations_24h'] }}</div></div>
                <div class="card"><div class="stat-label">Aktif (7 Hari)</div><div class="stat-val">{{ $analyticsSummary['active_installations_7d'] }}</div></div>
                <div class="card"><div class="stat-label">Total Durasi Sesi/Putar</div><div class="stat-val">{{ $fmtDur($totalSec) }}</div></div>
                <div class="card"><div class="stat-label">Rata-rata Durasi</div><div class="stat-val">{{ $fmtDur($avgSec) }}</div></div>
                <div class="card"><div class="stat-label">Error (7 Hari)</div><div class="stat-val" style="color:var(--accent);">{{ $analyticsSummary['error_events_7d'] }}</div></div>
            </div>

            <div class="form-row">
                <div class="card">
                    <h2>Event Teratas</h2>
                    <table>
                        <thead><tr><th>Event</th><th>Jumlah</th></tr></thead>
                        <tbody>
                        @forelse ($analyticsSummary['top_events'] as $ev)
                            <tr><td>{{ $ev->event_name }}</td><td>{{ $ev->total }}</td></tr>
                        @empty
                            <tr><td colspan="2" style="color:var(--muted);">Belum ada data event.</td></tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>

                <div class="card">
                    <h2>Distribusi Versi Aplikasi</h2>
                    <table>
                        <thead><tr><th>Versi</th><th>Event</th></tr></thead>
                        <tbody>
                        @forelse ($analyticsSummary['by_version'] as $ver)
                            <tr><td>{{ $ver->app_version }}</td><td>{{ $ver->total }}</td></tr>
                        @empty
                            <tr><td colspan="2" style="color:var(--muted);">Belum ada data versi.</td></tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="form-row">
                <div class="card">
                    <h2>Aktif Harian (7 Hari Terakhir / DAU)</h2>
                    <table>
                        <thead><tr><th>Tanggal</th><th>Perangkat Aktif</th><th>Total Event</th></tr></thead>
                        <tbody>
                        @foreach ($analyticsSummary['daily_active_7d'] ?? [] as $day)
                            <tr>
                                <td>{{ $day['date'] }}</td>
                                <td>{{ $day['active_installations'] }}</td>
                                <td>{{ $day['total_events'] }}</td>
                            </tr>
                        @endforeach
                        </tbody>
                    </table>
                </div>

                <div class="card">
                    <h2>Pencarian Katalog Teratas</h2>
                    <table>
                        <thead><tr><th>Kata Kunci</th><th>Jumlah</th></tr></thead>
                        <tbody>
                        @forelse ($analyticsSummary['top_searches'] ?? [] as $term => $cnt)
                            <tr><td>{{ $term }}</td><td>{{ $cnt }}</td></tr>
                        @empty
                            <tr><td colspan="2" style="color:var(--muted);">Belum ada pencarian tercatat.</td></tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="form-row">
                <div class="card">
                    <h2>Playlist Katalog Teratas</h2>
                    <table>
                        <thead><tr><th>Playlist</th><th>Dibuka</th></tr></thead>
                        <tbody>
                        @forelse ($analyticsSummary['top_playlists'] ?? [] as $pname => $cnt)
                            <tr><td>{{ $pname }}</td><td>{{ $cnt }}</td></tr>
                        @empty
                            <tr><td colspan="2" style="color:var(--muted);">Belum ada data playlist.</td></tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>

                <div class="card">
                    <h2>Channel Paling Sering Dibuka</h2>
                    <table>
                        <thead><tr><th>Channel</th><th>Dibuka</th></tr></thead>
                        <tbody>
                        @forelse ($analyticsSummary['top_channels'] ?? [] as $cname => $cnt)
                            <tr><td>{{ $cname }}</td><td>{{ $cnt }}</td></tr>
                        @empty
                            <tr><td colspan="2" style="color:var(--muted);">Belum ada data channel.</td></tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="form-row">
                <div class="card">
                    <h2>Error Pemutar (Dikelompokkan)</h2>
                    <table>
                        <thead><tr><th>Kode Error</th><th>Jumlah</th></tr></thead>
                        <tbody>
                        @forelse ($analyticsSummary['grouped_player_errors'] ?? [] as $code => $cnt)
                            <tr><td><span class="pill">{{ $code }}</span></td><td>{{ $cnt }}</td></tr>
                        @empty
                            <tr><td colspan="2" style="color:var(--muted);">Tidak ada error pemutar tercatat.</td></tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>

                <div class="card">
                    <h2>Kegagalan Sinkronisasi</h2>
                    <table>
                        <thead><tr><th>Target</th><th>Jumlah</th></tr></thead>
                        <tbody>
                        @forelse ($analyticsSummary['sync_failures'] ?? [] as $target => $cnt)
                            <tr><td>{{ $target }}</td><td>{{ $cnt }}</td></tr>
                        @empty
                            <tr><td colspan="2" style="color:var(--muted);">Tidak ada kegagalan sinkronisasi.</td></tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>
            </div>

            @if ($user->hasAdminRole(['analytics_admin']))
            <div class="card" style="display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;">
                <div>
                    <h2 style="margin-bottom:4px;">Retensi Event Analitik ({{ $analyticsSummary['retention_days'] ?? 90 }} Hari)</h2>
                    <div style="font-size:12.5px;color:var(--muted);">Pembersihan otomatis berjalan setiap hari pukul 02:30. Anda juga dapat menjalankan pembersihan manual.</div>
                </div>
                <form method="POST" action="{{ route('admin.analytics.prune') }}">
                    @csrf
                    <button class="btn-sec" type="submit">Hapus Event Lama Sekarang</button>
                </form>
            </div>
            @endif
        </section>

        @if ($user->hasAdminRole(['content_admin']))
        <!-- Panel: Sumber M3U -->
        <section id="panel-m3u" class="panel">
            <div class="card">
                <h2>CMS Katalog M3U (Link URL atau Upload File .m3u/.m3u8)</h2>
                <form method="POST" action="{{ route('admin.m3u-sources.store') }}" enctype="multipart/form-data">
                    @csrf
                    <div class="form-row">
                        <input name="name" placeholder="Nama Playlist (mis. TV Lokal / CCTV Kota)" required>
                        <select name="category">
                            <option value="TV & CCTV">TV &amp; CCTV</option>
                            <option value="Radio">Radio</option>
                            <option value="Musik">Musik</option>
                            <option value="Favorit">Favorit</option>
                            <option value="Umum">Umum</option>
                        </select>
                        <select name="source_type" id="m3u-source-type">
                            <option value="url">Link URL (.m3u / .m3u8)</option>
                            <option value="file">Upload File (.m3u / .m3u8)</option>
                        </select>
                    </div>
                    <div class="form-row">
                        <input name="region" placeholder="Wilayah (mis. Jawa Tengah)">
                        <input name="city" placeholder="Kota (mis. Semarang)">
                        <input name="language" placeholder="Bahasa (mis. Indonesia)">
                        <select name="status">
                            <option value="published">Publish Langsung</option>
                            <option value="draft">Simpan sebagai Draft</option>
                            <option value="scheduled">Jadwalkan Publikasi</option>
                        </select>
                    </div>
                    <input type="datetime-local" name="scheduled_at" placeholder="Jadwal Publish (jika scheduled)">
                    <div id="m3u-url-wrap">
                        <input name="source_url" placeholder="https://example.com/playlist.m3u8">
                    </div>
                    <div id="m3u-file-wrap" style="display:none;">
                        <input type="file" name="m3u_file" accept=".m3u,.m3u8,.txt">
                    </div>
                    <button class="btn" type="submit">Simpan Sumber M3U</button>
                </form>
            </div>

            <div class="card">
                <h2>Daftar Katalog M3U Backend ({{ $m3uSources->count() }})</h2>
                <table>
                    <thead><tr><th>Nama &amp; Wilayah</th><th>Status CMS</th><th>Stream</th><th>Sumber</th><th>Versi / Aksi</th></tr></thead>
                    <tbody>
                    @forelse ($m3uSources as $src)
                        <tr>
                            <td>
                                <strong>{{ $src->name }}</strong>
                                <div style="font-size:11.5px;color:var(--muted);">
                                    {{ $src->category }}
                                    @if ($src->city || $src->region) &bull; {{ $src->city ?? $src->region }} @endif
                                    @if ($src->language) &bull; {{ $src->language }} @endif
                                </div>
                            </td>
                            <td>
                                <span class="pill">{{ strtoupper($src->status ?? 'published') }}</span>
                                <div style="font-size:11px;color:var(--muted);">{{ $src->is_active ? 'Aktif' : 'Nonaktif' }}</div>
                            </td>
                            <td>
                                <form method="POST" action="{{ route('admin.m3u-sources.stream-status', $src) }}" style="display:flex;gap:4px;align-items:center;">
                                    @csrf
                                    <select name="stream_status" style="margin:0;width:auto;padding:4px 6px;font-size:11.5px;">
                                        @foreach (['online', 'degraded', 'offline'] as $st)
                                            <option value="{{ $st }}" @selected(($src->stream_status ?? 'online') === $st)>{{ $st }}</option>
                                        @endforeach
                                    </select>
                                    <button class="btn-sec" type="submit" style="padding:4px 8px;font-size:11px;">Set</button>
                                </form>
                            </td>
                            <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">
                                {{ $src->source_type === 'url' ? $src->source_url : basename((string) $src->file_path) }}
                            </td>
                            <td>
                                @if (($src->status ?? 'published') !== 'published')
                                    <form style="display:inline" method="POST" action="{{ route('admin.m3u-sources.publish', $src) }}">@csrf<button class="btn-sec" type="submit">Publish</button></form>
                                @endif
                                <form style="display:inline" method="POST" action="{{ route('admin.m3u-sources.toggle', $src) }}">@csrf<button class="btn-sec" type="submit">Toggle</button></form>
                                @if ($src->versions->count() > 1)
                                    @php $prevVer = $src->versions->skip(1)->first(); @endphp
                                    @if ($prevVer)
                                        <form style="display:inline" method="POST" action="{{ route('admin.m3u-sources.rollback', [$src, $prevVer]) }}">@csrf<button class="btn-sec" type="submit">Rollback v{{ $prevVer->version_number }}</button></form>
                                    @endif
                                @endif
                                <form style="display:inline" method="POST" action="{{ route('admin.m3u-sources.delete', $src) }}">@csrf @method('DELETE')<button class="btn" type="submit">Hapus</button></form>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="5" style="color:var(--muted);">Belum ada sumber M3U di backend.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>

        <!-- Panel: Pengumuman -->
        <section id="panel-announcements" class="panel">
            <div class="card">
                <h2>Pengumuman &amp; Konten Jarak Jauh</h2>
                <form method="POST" action="{{ route('admin.announcements.store') }}">
                    @csrf
                    <div class="form-row">
                        <input name="title" placeholder="Judul pengumuman" required>
                        <select name="type"><option value="info">info</option><option value="maintenance">maintenance</option><option value="feature">feature</option><option value="warning">warning</option></select>
                    </div>
                    <textarea name="body" rows="2" placeholder="Isi pengumuman" required></textarea>
                    <button class="btn" type="submit">Tambah Pengumuman</button>
                </form>
            </div>
            <div class="card">
                <h2>Daftar Pengumuman</h2>
                <table>
                    <thead><tr><th>Judul</th><th>Tipe</th><th>Status</th><th>Aksi</th></tr></thead>
                    <tbody>
                    @foreach ($announcements as $a)
                        <tr>
                            <td>{{ $a->title }}</td><td>{{ $a->type }}</td><td>{{ $a->is_active ? 'Aktif' : 'Nonaktif' }}</td>
                            <td>
                                <form style="display:inline" method="POST" action="{{ route('admin.announcements.toggle', $a) }}">@csrf<button class="btn-sec" type="submit">Toggle</button></form>
                                <form style="display:inline" method="POST" action="{{ route('admin.announcements.delete', $a) }}">@csrf @method('DELETE')<button class="btn" type="submit">Hapus</button></form>
                            </td>
                        </tr>
                    @endforeach
                    </tbody>
                </table>
            </div>
        </section>

        <!-- Panel: Rilis Aplikasi -->
        <section id="panel-releases" class="panel">
            <div class="card">
                <h2>Metadata Rilis Aplikasi</h2>
                <form method="POST" action="{{ route('admin.releases.store') }}">
                    @csrf
                    <div class="form-row">
                        <input name="version" placeholder="Versi (mis. 1.12.2)" required>
                        <input name="build_number" type="number" placeholder="Build number" required>
                        <select name="platform"><option value="android">android</option><option value="android_tv">android_tv</option><option value="windows">windows</option></select>
                        <input name="abi" value="arm64-v8a" required>
                    </div>
                    <input name="download_url" placeholder="https://..." required>
                    <textarea name="release_notes" rows="2" placeholder="Catatan rilis"></textarea>
                    <button class="btn" type="submit">Simpan Rilis</button>
                </form>
            </div>
            <div class="card">
                <h2>Daftar Rilis ({{ $releases->count() }})</h2>
                <table>
                    <thead><tr><th>Versi</th><th>Build</th><th>Platform</th><th>ABI</th><th>URL</th></tr></thead>
                    <tbody>
                    @foreach ($releases as $rel)
                        <tr>
                            <td>{{ $rel->version }}</td><td>{{ $rel->build_number }}</td><td>{{ $rel->platform }}</td><td>{{ $rel->abi }}</td>
                            <td style="max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">{{ $rel->download_url }}</td>
                        </tr>
                    @endforeach
                    </tbody>
                </table>
            </div>
        </section>
        @endif

        @if ($user->hasAdminRole(['analytics_admin']))
        <!-- Panel: Feedback -->
        <section id="panel-feedback" class="panel">
            <div class="card">
                <h2>Laporan Masalah &amp; Feedback</h2>
                <table>
                    <thead><tr><th>Tiket</th><th>Kategori</th><th>Deskripsi</th><th>Versi</th><th>Status</th><th>Ubah</th></tr></thead>
                    <tbody>
                    @foreach ($feedbacks as $f)
                        <tr>
                            <td><strong>#{{ $f->id }}</strong></td>
                            <td>{{ $f->category }}</td>
                            <td>{{ $f->message }}</td>
                            <td>{{ $f->app_version }} ({{ $f->platform }})</td>
                            <td><span class="pill">{{ $f->status }}</span></td>
                            <td>
                                <form method="POST" action="{{ route('admin.feedback.status', $f) }}" style="display:flex;gap:6px;align-items:center;">
                                    @csrf
                                    <select name="status" style="margin:0;width:auto;">
                                        @foreach (['open','in_review','resolved','closed'] as $st)
                                            <option value="{{ $st }}" @selected($f->status === $st)>{{ $st }}</option>
                                        @endforeach
                                    </select>
                                    <button class="btn-sec" type="submit">Simpan</button>
                                </form>
                            </td>
                        </tr>
                    @endforeach
                    </tbody>
                </table>
            </div>
        </section>
        @endif

        <!-- Panel: Audit & Users -->
        <section id="panel-audit" class="panel">
            @if ($user->role === 'super_admin')
            <div class="card">
                <h2>Manajemen Pengguna</h2>
                <table>
                    <thead><tr><th>Nama</th><th>Email</th><th>Role</th><th>Status</th><th>Aksi</th></tr></thead>
                    <tbody>
                    @foreach ($users as $u)
                        <tr>
                            <td>{{ $u->name }}</td><td>{{ $u->email }}</td><td>{{ $u->role }}</td>
                            <td>{{ $u->is_active ? 'Aktif' : 'Nonaktif' }}</td>
                            <td>
                                @if ($u->id !== $user->id)
                                <form method="POST" action="{{ route('admin.users.toggle', $u) }}">@csrf<button class="btn-sec" type="submit">Toggle Aktif</button></form>
                                @endif
                            </td>
                        </tr>
                    @endforeach
                    </tbody>
                </table>
            </div>
            @endif

            <div class="card">
                <h2>Log Audit Admin Terbaru</h2>
                <table>
                    <thead><tr><th>Waktu</th><th>Admin</th><th>Aksi</th><th>Target</th></tr></thead>
                    <tbody>
                    @foreach ($auditLogs as $log)
                        <tr><td>{{ $log->created_at }}</td><td>{{ $log->adminUser?->email ?? '-' }}</td><td>{{ $log->action }}</td><td>{{ $log->target_type }}#{{ $log->target_id }}</td></tr>
                    @endforeach
                    </tbody>
                </table>
            </div>
        </section>
    </main>

    <script>
        (function () {
            const buttons = document.querySelectorAll('.nav-btn[data-panel]');
            const panels = document.querySelectorAll('.panel');
            function activate(key) {
                buttons.forEach((b) => b.classList.toggle('active', b.dataset.panel === key));
                panels.forEach((p) => p.classList.toggle('active', p.id === 'panel-' + key));
                try { sessionStorage.setItem('mc_admin_tab', key); } catch (_) {}
            }
            buttons.forEach((b) => b.addEventListener('click', () => activate(b.dataset.panel)));
            try {
                const saved = sessionStorage.getItem('mc_admin_tab');
                if (saved && document.getElementById('panel-' + saved)) {
                    activate(saved);
                }
            } catch (_) {}

            const srcSel = document.getElementById('m3u-source-type');
            const urlWrap = document.getElementById('m3u-url-wrap');
            const fileWrap = document.getElementById('m3u-file-wrap');
            if (srcSel && urlWrap && fileWrap) {
                const toggleInputs = () => {
                    const isFile = srcSel.value === 'file';
                    urlWrap.style.display = isFile ? 'none' : 'block';
                    fileWrap.style.display = isFile ? 'block' : 'none';
                };
                srcSel.addEventListener('change', toggleInputs);
                toggleInputs();
            }
        })();
    </script>
</body>
</html>
