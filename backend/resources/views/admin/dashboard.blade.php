<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Panel — MediaCenter</title>
    <style>
        body { font-family: system-ui, sans-serif; background: #0f1117; color: #f3f4f6; margin: 0; padding: 24px; }
        .top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; margin-bottom: 24px; }
        .card { background: #181c26; border: 1px solid #2b3245; border-radius: 14px; padding: 18px; margin-bottom: 20px; }
        h2 { margin-top: 0; font-size: 16px; }
        table { width: 100%; border-collapse: collapse; font-size: 13px; }
        th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #262c3d; }
        input, select, textarea { background: #0f1117; color: #fff; border: 1px solid #374151; border-radius: 8px; padding: 8px; margin-bottom: 8px; width: 100%; box-sizing: border-box; }
        button { background: #e50914; color: #fff; border: 0; border-radius: 8px; padding: 8px 14px; font-weight: 700; cursor: pointer; }
        .btn-sec { background: #262c3d; }
        .status { background: rgba(29,185,84,.16); border: 1px solid #1db954; padding: 10px 14px; border-radius: 10px; margin-bottom: 16px; }
    </style>
</head>
<body>
<div class="top">
    <div>
        <h1 style="margin:0;font-size:22px;">MediaCenter Admin Panel</h1>
        <small style="color:#9ca3af;">Masuk sebagai {{ $user->name }} ({{ $user->role }})</small>
    </div>
    <form method="POST" action="{{ route('admin.logout') }}">
        @csrf
        <button class="btn-sec" type="submit">Keluar</button>
    </form>
</div>

@if (session('status'))
    <div class="status">{{ session('status') }}</div>
@endif

<div class="grid">
    <div class="card"><div style="color:#9ca3af;font-size:12px;">Total Event Analitik</div><div style="font-size:26px;font-weight:800;">{{ $analyticsSummary['total_events'] }}</div></div>
    <div class="card"><div style="color:#9ca3af;font-size:12px;">Perangkat Aktif (7 Hari)</div><div style="font-size:26px;font-weight:800;">{{ $analyticsSummary['active_installations_7d'] }}</div></div>
    <div class="card"><div style="color:#9ca3af;font-size:12px;">Pengumuman Aktif</div><div style="font-size:26px;font-weight:800;">{{ $announcements->where('is_active', true)->count() }}</div></div>
    <div class="card"><div style="color:#9ca3af;font-size:12px;">Laporan Terbuka</div><div style="font-size:26px;font-weight:800;">{{ $feedbacks->where('status', 'open')->count() }}</div></div>
</div>

@if ($user->hasAdminRole(['content_admin']))
<div class="card">
    <h2>Pengumuman &amp; Konten Jarak Jauh</h2>
    <form method="POST" action="{{ route('admin.announcements.store') }}">
        @csrf
        <input name="title" placeholder="Judul pengumuman" required>
        <textarea name="body" rows="2" placeholder="Isi pengumuman" required></textarea>
        <select name="type"><option value="info">info</option><option value="maintenance">maintenance</option><option value="feature">feature</option><option value="warning">warning</option></select>
        <button type="submit">Tambah Pengumuman</button>
    </form>
    <table>
        <thead><tr><th>Judul</th><th>Tipe</th><th>Status</th><th>Aksi</th></tr></thead>
        <tbody>
        @foreach ($announcements as $a)
            <tr>
                <td>{{ $a->title }}</td><td>{{ $a->type }}</td><td>{{ $a->is_active ? 'Aktif' : 'Nonaktif' }}</td>
                <td>
                    <form style="display:inline" method="POST" action="{{ route('admin.announcements.toggle', $a) }}">@csrf<button class="btn-sec" type="submit">Toggle</button></form>
                    <form style="display:inline" method="POST" action="{{ route('admin.announcements.delete', $a) }}">@csrf @method('DELETE')<button type="submit">Hapus</button></form>
                </td>
            </tr>
        @endforeach
        </tbody>
    </table>
</div>

<div class="card">
    <h2>Metadata Rilis Aplikasi</h2>
    <form method="POST" action="{{ route('admin.releases.store') }}">
        @csrf
        <input name="version" placeholder="Versi (mis. 1.12.2)" required>
        <input name="build_number" type="number" placeholder="Build number" required>
        <select name="platform"><option value="android">android</option><option value="android_tv">android_tv</option><option value="windows">windows</option></select>
        <input name="abi" value="arm64-v8a" required>
        <input name="download_url" placeholder="https://..." required>
        <textarea name="release_notes" rows="2" placeholder="Catatan rilis"></textarea>
        <button type="submit">Simpan Rilis</button>
    </form>
    <table>
        <thead><tr><th>Versi</th><th>Platform</th><th>ABI</th><th>URL</th></tr></thead>
        <tbody>
        @foreach ($releases as $r)
            <tr><td>{{ $r->version }} (+{{ $r->build_number }})</td><td>{{ $r->platform }}</td><td>{{ $r->abi }}</td><td>{{ $r->download_url }}</td></tr>
        @endforeach
        </tbody>
    </table>
</div>
@endif

@if ($user->hasAdminRole(['analytics_admin']))
<div class="card">
    <h2>Laporan &amp; Feedback Pengguna</h2>
    <table>
        <thead><tr><th>Kategori</th><th>Pesan</th><th>Platform</th><th>Status</th><th>Ubah Status</th></tr></thead>
        <tbody>
        @foreach ($feedbacks as $fb)
            <tr>
                <td>{{ $fb->category }}</td>
                <td>{{ $fb->message }}</td>
                <td>{{ $fb->platform }} {{ $fb->app_version }}</td>
                <td>{{ $fb->status }}</td>
                <td>
                    <form method="POST" action="{{ route('admin.feedback.status', $fb) }}">@csrf
                        <select name="status">
                            @foreach (['open','in_review','resolved','closed'] as $st)
                                <option value="{{ $st }}" @selected($fb->status === $st)>{{ $st }}</option>
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
@endif

@if ($user->role === 'super_admin')
<div class="card">
    <h2>Manajemen Akun (Super Admin)</h2>
    <table>
        <thead><tr><th>Nama</th><th>Email</th><th>Role</th><th>Status</th><th>Aksi</th></tr></thead>
        <tbody>
        @foreach ($users as $u)
            <tr>
                <td>{{ $u->name }}</td><td>{{ $u->email }}</td><td>{{ $u->role }}</td><td>{{ $u->is_active ? 'Aktif' : 'Nonaktif' }}</td>
                <td><form method="POST" action="{{ route('admin.users.toggle', $u) }}">@csrf<button class="btn-sec" type="submit">Toggle Aktif</button></form></td>
            </tr>
        @endforeach
        </tbody>
    </table>
</div>
@endif

<div class="card">
    <h2>Audit Log Admin</h2>
    <table>
        <thead><tr><th>Waktu</th><th>Admin</th><th>Aksi</th><th>Target</th></tr></thead>
        <tbody>
        @foreach ($auditLogs as $log)
            <tr><td>{{ $log->created_at }}</td><td>{{ $log->adminUser?->email }}</td><td>{{ $log->action }}</td><td>{{ $log->target_type }}#{{ $log->target_id }}</td></tr>
        @endforeach
        </tbody>
    </table>
</div>
</body>
</html>
