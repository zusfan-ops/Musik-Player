<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ $store->name }} — MediaCenter Store</title>
    <style>
        :root { --bg:#07080d; --card:#12151f; --border:#232838; --text:#f4f4f5; --muted:#9ca3af; --accent:#e50914; --green:#1db954; }
        * { box-sizing: border-box; }
        body { font-family: system-ui, -apple-system, sans-serif; background: var(--bg); color: var(--text); margin: 0; padding: 20px 16px 60px; }
        .wrap { max-width: 780px; margin: 0 auto; }
        .hero { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 22px; margin-bottom: 18px; }
        .badge { display: inline-block; font-size: 11px; font-weight: 700; text-transform: uppercase; padding: 3px 9px; border-radius: 999px; background: rgba(229,9,20,0.16); color: #ff7a82; border: 1px solid rgba(229,9,20,0.35); }
        h1 { margin: 10px 0 6px; font-size: 24px; }
        .meta { color: var(--muted); font-size: 13.5px; line-height: 1.5; }
        .alert-ok { background: rgba(29,185,84,.16); border: 1px solid var(--green); padding: 12px 16px; border-radius: 12px; margin-bottom: 16px; font-weight: 600; }
        .alert-err { background: rgba(229,9,20,.16); border: 1px solid var(--accent); padding: 12px 16px; border-radius: 12px; margin-bottom: 16px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 12px; margin-bottom: 20px; }
        .prod { background: var(--card); border: 1px solid var(--border); border-radius: 14px; padding: 14px; display: flex; flex-direction: column; justify-content: space-between; gap: 10px; }
        .price { color: var(--green); font-weight: 800; font-size: 15px; }
        .qty-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
        input, select, textarea { width: 100%; background: var(--bg); color: #fff; border: 1px solid #30374a; border-radius: 10px; padding: 10px 12px; margin-bottom: 10px; font-size: 14px; }
        .qty-input { width: 74px; margin: 0; text-align: center; }
        .form-card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 20px; }
        button { width: 100%; background: var(--accent); color: #fff; border: 0; border-radius: 10px; padding: 13px; font-size: 15px; font-weight: 800; cursor: pointer; }
        a.map-link { color: #60a5fa; text-decoration: none; font-size: 13px; }
    </style>
</head>
<body>
<div class="wrap">
    <div class="hero">
        <span class="badge">{{ strtoupper($store->store_type) }}</span>
        <h1>{{ $store->name }}</h1>
        @if ($store->description)
            <p class="meta">{{ $store->description }}</p>
        @endif
        @if ($store->address)
            <div class="meta">Alamat: {{ $store->address }}</div>
        @endif
        @if ($store->latitude && $store->longitude)
            <div style="margin-top:6px;">
                <a class="map-link" target="_blank" rel="noopener noreferrer" href="https://maps.google.com/?q={{ $store->latitude }},{{ $store->longitude }}">Buka Lokasi GPS di Google Maps</a>
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
        <h2 style="font-size:17px;margin-bottom:10px;">Menu &amp; Produk ({{ $store->products->count() }})</h2>
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
            <h2 style="font-size:17px;margin:0 0 12px;">Verifikasi Pemesan &amp; Kirim ke Antrean POS</h2>
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
            <textarea name="notes" rows="2" placeholder="Catatan pesanan (opsional)">{{ old('notes') }}</textarea>
            <button type="submit">Kirim Pesanan ke Kasir (POS)</button>
        </div>
        @endif
    </form>
</div>
</body>
</html>
