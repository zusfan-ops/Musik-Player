<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Login — MediaCenter</title>
    <style>
        body { font-family: system-ui, sans-serif; background: #0f1117; color: #f3f4f6; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
        .card { background: #181c26; padding: 32px; border-radius: 16px; width: 360px; border: 1px solid #2b3245; }
        h1 { margin: 0 0 8px; font-size: 20px; }
        p { margin: 0 0 20px; color: #9ca3af; font-size: 13px; }
        label { display: block; font-size: 12px; font-weight: 700; margin-bottom: 6px; color: #d1d5db; }
        input { width: 100%; box-sizing: border-box; padding: 10px 12px; border-radius: 10px; border: 1px solid #374151; background: #0f1117; color: #fff; margin-bottom: 14px; }
        button { width: 100%; padding: 11px; border: 0; border-radius: 10px; background: #e50914; color: #fff; font-weight: 800; cursor: pointer; }
        .err { background: rgba(229,9,20,.15); border: 1px solid #e50914; padding: 10px; border-radius: 8px; margin-bottom: 14px; font-size: 12.5px; }
    </style>
</head>
<body>
<div class="card">
    <h1>MediaCenter Admin</h1>
    <p>Panel pengumuman, rilis, analitik &amp; dukungan</p>
    @if ($errors->any())
        <div class="err">{{ $errors->first() }}</div>
    @endif
    <form method="POST" action="{{ route('admin.login.submit') }}">
        @csrf
        <label>Email</label>
        <input type="email" name="email" value="{{ old('email') }}" required>
        <label>Kata Sandi</label>
        <input type="password" name="password" required>
        <label>Verifikasi Keamanan: Berapa hasil {{ $captchaQuestion ?? '1 + 1' }} ?</label>
        <input type="number" name="captcha" placeholder="Masukkan angka jawaban" required autocomplete="off">
        <button type="submit">Masuk</button>
    </form>
</div>
</body>
</html>
