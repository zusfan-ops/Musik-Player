import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/music_provider.dart';
import '../services/backend_api_service.dart';
import '../services/config_backup_service.dart';
import '../theme/app_theme.dart';

/// Optional Cloud Account, Cross-Device Sync, Announcements, Analytics Opt-In,
/// and Privacy Controls for ProfileSettingsScreen (strictly guest-first).
class BackendCloudSection extends StatefulWidget {
  const BackendCloudSection({super.key});

  @override
  State<BackendCloudSection> createState() => _BackendCloudSectionState();
}

class _BackendCloudSectionState extends State<BackendCloudSection> {
  final _api = BackendApiService.instance;
  bool _isLoggedIn = false;
  String? _email;
  String? _name;
  bool _analyticsOptIn = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadState());
  }

  Future<void> _loadState() async {
    final acc = await _api.getAccountState();
    final optIn = await _api.isAnalyticsOptedIn();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = acc.isLoggedIn;
      _email = acc.email;
      _name = acc.name;
      _analyticsOptIn = optIn;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportLocalBackup() async {
    final music = context.read<MusicProvider>();
    final jsonStr = music.exportBackupJson();
    try {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = 'mediacenter-backup-$stamp.json';
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final savedUri = await FilePicker.saveFile(
          dialogTitle: 'Simpan Backup Konfigurasi MediaCenter',
          fileName: fileName,
          bytes: Uint8List.fromList(utf8.encode(jsonStr)),
        );
        if (savedUri == null) return;
        _snack('Backup tersimpan ke $fileName.');
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File(p.join(tempDir.path, fileName));
        await file.writeAsString(jsonStr);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: 'Backup Konfigurasi MediaCenter',
          ),
        );
      }
    } catch (e) {
      _snack('Gagal mengekspor backup: $e');
    }
  }

  Future<void> _importLocalBackupWithPreview() async {
    final music = context.read<MusicProvider>();
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked.isEmpty) return;
      final pickedFile = picked.first;
      if (pickedFile.path == null || pickedFile.path!.isEmpty) {
        _snack('File backup tidak dapat dibaca.');
        return;
      }
      final rawJson = await File(pickedFile.path!).readAsString();

      final preview = ConfigBackupService.parseAndPreview(rawJson);
      if (!mounted) return;

      final exportedText = preview.exportedAt != null
          ? preview.exportedAt!.toLocal().toString().split('.').first
          : 'Tidak diketahui';

      final mode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pratinjau Pemulihan Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dibuat: $exportedText',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text('• Playlist URL: ${preview.urlPlaylistCount}'),
              Text('• Metadata Playlist Lokal: ${preview.localPlaylistCount}'),
              Text('• Lagu Favorit: ${preview.favoriteCount}'),
              Text('• Playlist YouTube: ${preview.youtubePlaylistCount}'),
              Text('• Pengaturan Kompatibel: ${preview.settingsCount}'),
              const SizedBox(height: 12),
              const Text(
                'Pilih "Gabungkan" untuk menambah tanpa menimpa data yang sudah ada, atau "Ganti Semua" untuk memulihkan penuh.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('Gabungkan'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Ganti Semua'),
            ),
          ],
        ),
      );

      if (mode == null) return;
      final res = await music.restoreBackup(
        preview,
        replaceExisting: mode == 'replace',
      );
      _snack(
        'Backup dipulihkan: ${res.addedPlaylists} playlist, ${res.restoredFavorites} favorit.',
      );
    } catch (e) {
      _snack('File backup tidak valid: $e');
    }
  }

  Future<void> _showAuthDialog({bool isRegister = false}) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool registerMode = isRegister;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(registerMode ? 'Daftar Akun (Opsional)' : 'Masuk Akun Cloud'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Login bersifat opsional untuk sinkronisasi metadata playlist & favorit. Aplikasi tetap berjalan penuh secara offline.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (registerMode) ...[
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Kata Sandi (min. 8 karakter)'),
              ),
              TextButton(
                onPressed: () => setDlg(() => registerMode = !registerMode),
                child: Text(
                  registerMode
                      ? 'Sudah punya akun? Masuk'
                      : 'Belum punya akun? Daftar',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final err = registerMode
                    ? await _api.register(
                        name: nameCtrl.text,
                        email: emailCtrl.text,
                        password: passCtrl.text,
                      )
                    : await _api.login(
                        email: emailCtrl.text,
                        password: passCtrl.text,
                      );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await _loadState();
                if (err == null && mounted) {
                  final syncMsg = await _api.syncBidirectional(
                    context.read<MusicProvider>(),
                  );
                  _snack('Berhasil terhubung! $syncMsg');
                } else {
                  _snack(err ?? 'Berhasil terhubung ke akun cloud!');
                }
              },
              child: Text(registerMode ? 'Daftar' : 'Masuk'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditAccountDialog() async {
    final nameCtrl = TextEditingController(text: _name ?? '');
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Akun & Ganti Kata Sandi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Tampilan'),
              ),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 6),
              const Text(
                'Isi kolom di bawah hanya jika ingin mengganti kata sandi:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: currentPassCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Kata Sandi Saat Ini'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Kata Sandi Baru (min. 8 karakter)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Konfirmasi Kata Sandi Baru',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newPassCtrl.text.isNotEmpty &&
                  newPassCtrl.text != confirmPassCtrl.text) {
                _snack('Konfirmasi kata sandi baru tidak cocok.');
                return;
              }
              final err = await _api.updateAccount(
                name: nameCtrl.text,
                currentPassword: currentPassCtrl.text,
                newPassword: newPassCtrl.text,
              );
              if (err == null) {
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadState();
                _snack('Profil akun berhasil diperbarui.');
              } else {
                _snack(err);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    currentPassCtrl.dispose();
    newPassCtrl.dispose();
    confirmPassCtrl.dispose();
  }

  Future<void> _showFeedbackDialog({
    String initialCategory = 'complaint',
    String dialogTitle = 'Ajukan Keluhan / Masalah',
    String hintText = 'Jelaskan keluhan, bug, atau kendala yang Anda alami...',
  }) async {
    final msgCtrl = TextEditingController();
    String category = initialCategory;
    bool diagnosticsConsent = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                items: const [
                  DropdownMenuItem(
                    value: 'feature',
                    child: Text('Pengajuan Fitur Baru'),
                  ),
                  DropdownMenuItem(
                    value: 'complaint',
                    child: Text('Keluhan Layanan'),
                  ),
                  DropdownMenuItem(value: 'bug', child: Text('Bug / Error')),
                  DropdownMenuItem(
                    value: 'playback',
                    child: Text('Masalah Pemutaran'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Lainnya')),
                ],
                onChanged: (v) => setDlg(() => category = v ?? initialCategory),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: msgCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: hintText,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: diagnosticsConsent,
                onChanged: (v) => setDlg(() => diagnosticsConsent = v ?? false),
                title: const Text(
                  'Sertakan info platform dasar (tanpa daftar musik/path)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                if (msgCtrl.text.trim().length < 5) {
                  _snack('Pesan minimal 5 karakter.');
                  return;
                }
                final text = msgCtrl.text;
                Navigator.pop(ctx);
                final res = await _api.submitFeedback(
                  category: category,
                  message: text,
                  diagnosticsConsent: diagnosticsConsent,
                );
                _snack(res);
              },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
    msgCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final music = context.read<MusicProvider>();
    return Material(
      color: AppColors.card(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: AppColors.isDark(context)
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync_rounded, color: AppColors.spotifyGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isLoggedIn
                            ? 'Akun Cloud: ${_name ?? _email ?? "Aktif"}'
                            : 'Mode Guest (Offline-First)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.text(context),
                        ),
                      ),
                      Text(
                        _isLoggedIn
                            ? (_email ?? 'Sinkronisasi opt-in aktif')
                            : 'Musik lokal & M3U tetap berjalan penuh tanpa akun',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.subtext(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!_isLoggedIn)
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _showAuthDialog(),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Masuk / Daftar (Opsional)'),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final msg = await _api.syncBidirectional(music);
                            if (mounted) setState(() => _busy = false);
                            _snack(msg);
                          },
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Sinkronkan Sekarang'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _showEditAccountDialog,
                    icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                    label: const Text('Edit Akun & Sandi'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            await _api.logout();
                            await _loadState();
                            _snack('Keluar ke mode Guest.');
                          },
                    child: const Text('Keluar'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final err = await _api.deleteAccount();
                            await _loadState();
                            _snack(err ?? 'Akun & data cloud telah dihapus.');
                          },
                    child: const Text(
                      'Hapus Akun',
                      style: TextStyle(color: AppColors.netflixRed),
                    ),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: () async {
                    final list = await _api.fetchAnnouncements();
                    if (!context.mounted) return;
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Pengumuman'),
                        content: SizedBox(
                          width: 360,
                          child: list.isEmpty
                              ? const Text('Belum ada pengumuman terbaru atau perangkat offline.')
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: list
                                      .map(
                                        (a) => ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                          subtitle: Text(a.body),
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Tutup'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.campaign_rounded, size: 18),
                  label: const Text('Pengumuman'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showFeedbackDialog(
                    initialCategory: 'feature',
                    dialogTitle: 'Ajukan Fitur Baru',
                    hintText: 'Jelaskan fitur baru yang Anda inginkan...',
                  ),
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                  label: const Text('Ajukan Fitur'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showFeedbackDialog(
                    initialCategory: 'complaint',
                    dialogTitle: 'Ajukan Keluhan / Masalah',
                    hintText: 'Jelaskan keluhan atau kendala yang Anda alami...',
                  ),
                  icon: const Icon(Icons.report_problem_outlined, size: 18),
                  label: const Text('Ajukan Keluhan'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportLocalBackup,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Ekspor Backup (.json)'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importLocalBackupWithPreview,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('Impor & Pratinjau Backup'),
                ),
              ],
            ),
            const Divider(height: 22),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _analyticsOptIn,
              onChanged: (v) async {
                await _api.setAnalyticsOptIn(v);
                if (mounted) setState(() => _analyticsOptIn = v);
                _snack(v
                    ? 'Analitik anonim diaktifkan (tanpa data file/URL pribadi).'
                    : 'Analitik dimatikan.');
              },
              title: Text(
                'Analitik Penggunaan Anonim (Opt-In)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text(context),
                ),
              ),
              subtitle: Text(
                'Hanya event agregat. Tidak pernah mengirim path lokal, judul lagu, atau URL playlist.',
                style: TextStyle(fontSize: 11.5, color: AppColors.subtext(context)),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton(
                  onPressed: () async {
                    final id = await _api.resetInstallationId();
                    _snack('ID analitik direset ($id).');
                  },
                  child: const Text('Reset identitas analitik'),
                ),
                TextButton(
                  onPressed: () async {
                    final msg = await _api.deleteDeviceAnalytics();
                    _snack(msg);
                  },
                  child: const Text('Hapus data analitik perangkat ini'),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Kebijakan Privasi Singkat'),
                      content: const Text(
                        '1. MediaCenter berjalan 100% offline & guest-first tanpa login.\n'
                        '2. Path file lokal dan isi media pribadi tidak pernah diunggah.\n'
                        '3. Token akun disimpan aman di Keystore/Credential Manager.\n'
                        '4. Analitik bersifat opt-in dengan ID acak yang bisa direset atau dihapus kapan saja.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Tutup'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Kebijakan Privasi'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
