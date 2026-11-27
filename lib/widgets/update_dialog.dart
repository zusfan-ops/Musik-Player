import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';

class UpdateDialog extends StatefulWidget {
  final AppRelease release;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  bool _cancelRequested = false;
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  http.Client? _httpClient;

  @override
  void dispose() {
    _cancelRequested = true;
    _httpClient?.close();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1.0) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _cancelRequested = false;
      _progress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = widget.release.apkSizeBytes ?? 0;
      _errorMessage = null;
    });

    File? partFile;
    http.Client? client;
    try {
      client = http.Client();
      _httpClient = client;

      final uri = Uri.parse(widget.release.apkUrl);
      if (!(uri.scheme == 'https' || uri.scheme == 'http')) {
        throw const FormatException('URL pembaruan tidak valid.');
      }

      final isWindows = Platform.isWindows;
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] =
            isWindows ? 'MediaCenter-Windows' : 'M3UMusikPlayer-Android';

      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 400) {
        throw HttpException('Server merespons HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? (widget.release.apkSizeBytes ?? 0);
      if (total > 0) {
        _totalBytes = total;
      }

      Directory? dir;
      if (!isWindows) {
        try {
          final extDirs = await getExternalCacheDirectories();
          if (extDirs != null && extDirs.isNotEmpty) {
            dir = extDirs.first;
          }
        } catch (_) {}
      }
      dir ??= await getTemporaryDirectory();

      final cleanVer = widget.release.versionClean
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
      final expectedExt = isWindows ? '.exe' : '.apk';
      final fallbackName = isWindows
          ? 'MediaCenter-Setup-v$cleanVer-x64.exe'
          : 'M3UMusik-v$cleanVer.apk';
      final rawName = widget.release.apkName;
      String fileName = fallbackName;
      if (rawName != null && rawName.trim().isNotEmpty) {
        final baseOnly = p.basename(rawName.split('?').first.split('#').first);
        final sanitized =
            baseOnly.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
        if (sanitized.isNotEmpty &&
            !sanitized.startsWith('.') &&
            !sanitized.contains('..') &&
            sanitized.toLowerCase().endsWith(expectedExt)) {
          fileName = sanitized;
        }
      }
      final filePath = p.join(dir.path, fileName);
      partFile = File('$filePath.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }

      final sink = partFile.openWrite();
      int received = 0;

      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 30))) {
          if (_cancelRequested) {
            throw Exception('Unduhan dibatalkan.');
          }
          sink.add(chunk);
          received += chunk.length;

          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              if (_totalBytes > 0) {
                _progress = (received / _totalBytes).clamp(0.0, 1.0);
              }
            });
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (received == 0) {
        throw const FileSystemException('File installer kosong (0 byte).');
      }

      final finalFile = File(filePath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(filePath);

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _progress = 1.0;
        });
        await _installUpdate(filePath);
      }
    } catch (e) {
      if (partFile != null) {
        try {
          if (await partFile.exists()) await partFile.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = _cancelRequested ? null : 'Gagal mengunduh: $e';
        });
      }
    } finally {
      if (_httpClient == client) {
        _httpClient = null;
      }
      client?.close();
    }
  }

  void _cancelDownload() {
    _cancelRequested = true;
    _httpClient?.close();
    setState(() {
      _isDownloading = false;
      _progress = 0.0;
      _downloadedBytes = 0;
    });
  }

  Future<void> _installUpdate(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw const FileSystemException('File installer tidak ditemukan.');
      }

      if (Platform.isWindows) {
        await Process.start(
          filePath,
          const ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
          mode: ProcessStartMode.detached,
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        exit(0);
      }

      final result = await OpenFile.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.type == ResultType.permissionDenied
                  ? 'Harap aktifkan izin "Instal aplikasi tidak dikenal" untuk MediaCenter di Pengaturan Android.'
                  : 'Installer: ${result.message}',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka installer: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.release;

    return PopScope(
      canPop: !_isDownloading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isDownloading) {
          _cancelDownload();
        }
      },
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AppLogo(size: 48, borderRadius: 12),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pembaruan Aplikasi Tersedia',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'v${widget.currentVersion}  ->  v${rel.versionClean}',
                          style: const TextStyle(
                            color: AppColors.spotifyGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (rel.notes != null && rel.notes!.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      rel.notes!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              else
                const Text(
                  'Versi baru tersedia di GitHub Releases. Unduh dan pasang langsung dari dalam aplikasi.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppColors.netflixRed,
                    fontSize: 12,
                  ),
                ),
              ],

              if (_isDownloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _totalBytes > 0 ? _progress : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.spotifyGreen,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _totalBytes > 0
                      ? 'Mengunduh ${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)} (${(_progress * 100).round()}%)'
                      : 'Mengunduh ${_formatBytes(_downloadedBytes)}...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],

              const SizedBox(height: 18),
              if (_isDownloading)
                OutlinedButton(
                  onPressed: _cancelDownload,
                  child: const Text('Batalkan Unduhan'),
                )
              else
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        UpdateCheckerService.instance.dismissRelease(rel.version);
                        Navigator.pop(context);
                      },
                      child: const Text('Nanti'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.spotifyGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _startDownload,
                        icon: const Icon(Icons.system_update_rounded, size: 20),
                        label: Text(
                          rel.apkSizeBytes != null
                              ? 'Update (${_formatBytes(rel.apkSizeBytes!)})'
                              : 'Unduh & Pasang',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
