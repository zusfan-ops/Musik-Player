<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ $store->name }} — MediaCenter Store</title>
    <style>
        :root { --bg:#07080d; --card:#12151f; --border:#232838; --text:#f4f4f5; --muted:#9ca3af; --accent:#e50914; --green:#1db954; --amber:#f59e0b; --blue:#38bdf8; }
        * { box-sizing: border-box; }
        body { font-family: system-ui, -apple-system, sans-serif; background: var(--bg); color: var(--text); margin: 0; padding: 20px 16px 60px; }
        .wrap { max-width: 820px; margin: 0 auto; }
        .hero, .form-card, .section-card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 20px; margin-bottom: 18px; }
        .badge { display: inline-block; font-size: 11px; font-weight: 700; text-transform: uppercase; padding: 3px 9px; border-radius: 999px; background: rgba(229,9,20,0.16); color: #ff7a82; border: 1px solid rgba(229,9,20,0.35); }
        .badge-open { background: rgba(29,185,84,.16); color: #4ade80; border: 1px solid rgba(29,185,84,.4); }
        .badge-closed { background: rgba(239,68,68,.16); color: #f87171; border: 1px solid rgba(239,68,68,.4); }
        h1 { margin: 10px 0 6px; font-size: 24px; }
        h2 { font-size: 17px; margin: 0 0 12px; }
        .meta { color: var(--muted); font-size: 13.5px; line-height: 1.5; }
        .alert-ok { background: rgba(29,185,84,.16); border: 1px solid var(--green); padding: 12px 16px; border-radius: 12px; margin-bottom: 16px; font-weight: 600; }
        .alert-err { background: rgba(229,9,20,.16); border: 1px solid var(--accent); padding: 12px 16px; border-radius: 12px; margin-bottom: 16px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 12px; margin-bottom: 20px; }
        .prod { background: var(--card); border: 1px solid var(--border); border-radius: 14px; padding: 14px; display: flex; flex-direction: column; justify-content: space-between; gap: 10px; }
        .price { color: var(--green); font-weight: 800; font-size: 15px; }
        .qty-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
        input, select, textarea { width: 100%; background: var(--bg); color: #fff; border: 1px solid #30374a; border-radius: 10px; padding: 10px 12px; margin-bottom: 10px; font-size: 14px; }
        .qty-input { width: 74px; margin: 0; text-align: center; }
        button { width: 100%; background: var(--accent); color: #fff; border: 0; border-radius: 10px; padding: 13px; font-size: 15px; font-weight: 800; cursor: pointer; }
        .btn-sec { background: #1e293b; border: 1px solid #334155; }
        a.map-link { color: var(--blue); text-decoration: none; font-size: 13px; }
        .two-col { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; }
        .qr-box { background: #fff; padding: 10px; border-radius: 12px; display: inline-block; }
        .voucher-pill { display: inline-block; font-size: 12px; padding: 4px 10px; border-radius: 999px; background: rgba(245,158,11,.15); color: #fbbf24; border: 1px solid rgba(245,158,11,.35); margin: 0 6px 8px 0; }
        .review-item { border-top: 1px solid var(--border); padding: 10px 0; }
        .review-item:first-child { border-top: 0; padding-top: 0; }
    </style>
</head>
<body>
<div class="wrap">
    <div class="hero">
        <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center;">
            <span class="badge">{{ strtoupper($store->store_type) }}</span>
            <span class="badge {{ $store->is_open ? 'badge-open' : 'badge-closed' }}">{{ $store->is_open ? 'BUKA' : 'TUTUP' }}</span>
            @if ($store->rating_count > 0)
                <span class="badge" style="background:rgba(245,158,11,.16);color:#fbbf24;border-color:rgba(245,158,11,.35);">
                    ★ {{ number_format($store->rating_avg, 1) }} ({{ $store->rating_count }} ulasan)
                </span>
            @endif
        </div>
        <h1>{{ $store->name }}</h1>
        @if ($store->description)
            <p class="meta">{{ $store->description }}</p>
        @endif
        @if ($store->address)
            <div class="meta">Alamat: {{ $store->address }}</div>
        @endif
        @if ($store->opening_hours)
            <div class="meta">Jam Operasional: {{ $store->opening_hours }}</div>
        @endif
        @if ($store->latitude && $store->longitude)
            <div style="margin-top:6px;">
                <a class="map-link" target="_blank" rel="noopener noreferrer" href="https://maps.google.com/?q={{ $store->latitude }},{{ $store->longitude }}">Buka Lokasi GPS di Google Maps</a>
            </div>
        @endif
        @if ($store->now_playing_title)
            <div style="margin-top:10px;padding:8px 12px;border-radius:10px;background:rgba(56,189,248,.12);border:1px solid rgba(56,189,248,.3);font-size:13px;">
                🎵 <strong>Sedang Diputar di Toko:</strong> {{ $store->now_playing_title }}
                @if ($store->now_playing_artist) &mdash; {{ $store->now_playing_artist }} @endif
            </div>
        @endif
    </div>

    @if (session('order_success'))
        <div class="alert-ok">{{ session('order_success') }}</div>
    @endif
    @if ($errors->any())
        <div class="alert-err">{{ $errors->first() }}</div>
    @endif

    <form method="POST" action="{{ url('/' . $store->slug . '/order') }}">
        @csrf
        <h2>Menu &amp; Produk ({{ $store->products->count() }})</h2>

        @if ($store->vouchers->isNotEmpty())
            <div style="margin-bottom:12px;">
                <div class="meta" style="margin-bottom:6px;">Voucher Promo Tersedia:</div>
                @foreach ($store->vouchers as $v)
                    <span class="voucher-pill">
                        <strong>{{ $v->code }}</strong> &bull;
                        {{ $v->discount_type === 'percent' ? $v->discount_value . '%' : 'Rp ' . number_format($v->discount_value, 0, ',', '.') }}
                    </span>
                @endforeach
            </div>
        @endif

        <div class="grid">
            @forelse ($store->products as $p)
                <div class="prod">
                    <div>
                        <div style="font-size:11px;color:var(--muted);">{{ $p->category }}</div>
                        <div style="font-weight:700;font-size:15px;margin:2px 0;">{{ $p->name }}</div>
                        <div class="price">Rp {{ number_format($p->price, 0, ',', '.') }} / {{ $p->unit }}</div>
                    </div>
                    <div class="qty-row">
                        <span style="font-size:12px;color:var(--muted);">Jumlah</span>
                        <input class="qty-input" type="number" min="0" max="100" name="quantities[{{ $p->id }}]" value="{{ old('quantities.' . $p->id, 0) }}">
                    </div>
                </div>
            @empty
                <div class="prod">Belum ada produk tersedia.</div>
            @endforelse
        </div>

        @if ($store->products->isNotEmpty())
        <div class="form-card">
            <h2>Verifikasi Pemesan &amp; Kirim ke Antrean POS</h2>
            <input name="customer_name" placeholder="Nama Lengkap Anda" value="{{ old('customer_name') }}" required>
            <input name="customer_whatsapp" placeholder="Nomor WhatsApp Aktif (mis. 08123456789)" value="{{ old('customer_whatsapp') }}" required>
            @if ($store->store_type === 'coffeeshop' || $store->tables_count > 0)
                <select name="table_number">
                    <option value="">-- Pilih Nomor Meja / Takeaway --</option>
                    @for ($m = 1; $m <= max(1, (int) $store->tables_count); $m++)
                        <option value="Meja {{ $m }}" @selected($selectedTable === (string) $m || old('table_number') === "Meja $m")>Meja {{ $m }}</option>
                    @endfor
                </select>
            @endif
            <input name="voucher_code" placeholder="Kode Voucher Promo (opsional)" value="{{ old('voucher_code') }}">
            <textarea name="notes" rows="2" placeholder="Catatan pesanan (opsional)">{{ old('notes') }}</textarea>

            @if ($store->qris_image_url)
                <div style="margin:10px 0 14px;padding:12px;border:1px solid var(--border);border-radius:12px;text-align:center;background:#0b0d14;">
                    <div style="font-size:13px;font-weight:700;margin-bottom:8px;">Pembayaran QRIS Toko</div>
                    <img src="{{ $store->qris_image_url }}" alt="QRIS {{ $store->name }}" style="max-width:220px;width:100%;border-radius:8px;background:#fff;padding:6px;">
                </div>
            @endif

            <button type="submit">Kirim Pesanan ke Kasir (POS)</button>
        </div>
        @endif
    </form>

    <div class="two-col">
        <!-- Cafe Jukebox: Request Lagu -->
        <div class="section-card">
            <h2>🎵 Cafe Jukebox — Request Lagu</h2>
            <p class="meta" style="margin-bottom:12px;">Ingin lagu favorit Anda diputar di toko? Kirim request ke pemutar musik kasir.</p>
            <form method="POST" action="{{ url('/' . $store->slug . '/jukebox') }}">
                @csrf
                <input name="requester_name" placeholder="Nama Anda" required>
                <input name="table_number" placeholder="Nomor Meja (opsional)" value="{{ $selectedTable ? 'Meja ' . $selectedTable : '' }}">
                <input name="song_title" placeholder="Judul Lagu yang Diminta" required>
                <input name="artist_name" placeholder="Nama Penyanyi / Band (opsional)">
                <button type="submit" class="btn-sec">Kirim Request Lagu</button>
            </form>
        </div>

        <!-- Google Maps Rating QR Code -->
        @if ($store->google_maps_review_url)
        <div class="section-card" style="text-align:center;">
            <h2>⭐ Beri Rating di Google Maps</h2>
            <p class="meta" style="margin-bottom:12px;">Scan QR Code di bawah ini atau klik tombol untuk memberi ulasan di Google Maps.</p>
            <div class="qr-box">
                <img src="https://api.qrserver.com/v1/create-qr-code/?size=180x180&data={{ urlencode($store->google_maps_review_url) }}" alt="QR Rating Google Maps {{ $store->name }}" width="180" height="180">
            </div>
            <div style="margin-top:12px;">
                <a class="map-link" href="{{ $store->google_maps_review_url }}" target="_blank" rel="noopener noreferrer" style="display:inline-block;padding:10px 16px;background:#1e293b;border-radius:8px;font-weight:700;">Buka Google Maps Review</a>
            </div>
        </div>
        @endif
    </div>

    <!-- Verified Reviews -->
    <div class="section-card">
        <h2>Ulasan Pelanggan ({{ $store->rating_count }})</h2>
        <form method="POST" action="{{ url('/' . $store->slug . '/review') }}" style="margin-bottom:16px;">
            @csrf
            <div class="two-col">
                <input name="reviewer_name" placeholder="Nama Anda" required>
                <input name="reviewer_whatsapp" placeholder="No. WhatsApp (untuk badge Terverifikasi)">
            </div>
            <select name="rating" required>
                <option value="5">★★★★★ (5 - Sangat Puas)</option>
                <option value="4">★★★★☆ (4 - Puas)</option>
                <option value="3">★★★☆☆ (3 - Cukup)</option>
                <option value="2">★★☆☆☆ (2 - Kurang)</option>
                <option value="1">★☆☆☆☆ (1 - Buruk)</option>
            </select>
            <textarea name="comment" rows="2" placeholder="Tulis ulasan Anda tentang toko ini..."></textarea>
            <button type="submit" class="btn-sec">Kirim Ulasan</button>
        </form>

        @forelse ($store->reviews as $rev)
            <div class="review-item">
                <div style="display:flex;justify-content:space-between;align-items:center;">
                    <strong>{{ $rev->reviewer_name }}</strong>
                    <span style="color:#fbbf24;font-size:13px;">{{ str_repeat('★', $rev->rating) }}</span>
                </div>
                @if ($rev->is_verified_order)
                    <div style="font-size:11px;color:#4ade80;">✓ Pelanggan Terverifikasi</div>
                @endif
                @if ($rev->comment)
                    <div class="meta" style="margin-top:4px;">{{ $rev->comment }}</div>
                @endif
            </div>
        @empty
            <p class="meta">Belum ada ulasan. Jadilah yang pertama mengulas!</p>
        @endforelse
    </div>
</div>
</body>
</html>
