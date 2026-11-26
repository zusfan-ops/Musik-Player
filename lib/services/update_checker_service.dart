import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/update_dialog.dart';

class AppRelease {
  final String version;
  final String apkUrl;
  final String? apkName;
  final int? apkSizeBytes;
  final String? notes;
  final String? htmlUrl;

  const AppRelease({
    required this.version,
    required this.apkUrl,
    this.apkName,
    this.apkSizeBytes,
    this.notes,
    this.htmlUrl,
  });

  String get versionClean =>
      (version.startsWith('v') || version.startsWith('V'))
          ? version.substring(1)
          : version;
}

class UpdateCheckerService {
  UpdateCheckerService._();
  static final UpdateCheckerService instance = UpdateCheckerService._();

  static const String githubRepoOwner = 'zusfan-ops';
  static const String githubRepoName = 'Musik-Player';
  static const String githubLatestApiUrl =
      'https://api.github.com/repos/$githubRepoOwner/$githubRepoName/releases/latest';
  static const String rawLatestJsonUrl =
      'https://raw.githubusercontent.com/$githubRepoOwner/$githubRepoName/main/public/release/latest.json';
  static const String rawRepoBaseUrl =
      'https://raw.githubusercontent.com/$githubRepoOwner/$githubRepoName/main/public';

  static const String _kDismissedVerKey = 'ota_dismissed_version_v1';
  static const String _kDismissedAtKey = 'ota_dismissed_at_v1';
  static const MethodChannel _platformChannel =
      MethodChannel('com.musikm3u.player/media_store');

  final ValueNotifier<AppRelease?> availableUpdateNotifier =
      ValueNotifier<AppRelease?>(null);

  String _cachedVersion = '1.3.0';
  String _cachedBuildNumber = '';
  DateTime? _lastCheckedAt;
  bool _isChecking = false;
  bool _hasPromptedThisSession = false;

  String get currentVersion => _cachedVersion;
  String get currentBuildNumber => _cachedBuildNumber;
  String get fullVersionString => _cachedBuildNumber.isNotEmpty
      ? 'v$_cachedVersion+$_cachedBuildNumber'
      : 'v$_cachedVersion';

  Future<String> getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        _cachedVersion = info.version;
        _cachedBuildNumber = info.buildNumber;
      }
    } catch (_) {}
    return _cachedVersion;
  }

  /// Compares semantic versions (`X.Y.Z` or `vX.Y.Z+build`).
  static bool isNewerVersion(String latestVersion, String currentVersion) {
    try {
      final cleanNew = latestVersion.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final cleanCur = currentVersion.trim().replaceFirst(RegExp(r'^[vV]'), '');

      final newSem = cleanNew.split('+').first.split('-').first.trim();
      final curSem = cleanCur.split('+').first.split('-').first.trim();

      final newParts = newSem
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
      final curParts = curSem
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();

      while (newParts.length < 3) {
        newParts.add(0);
      }
      while (curParts.length < 3) {
        curParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (newParts[i] > curParts[i]) return true;
        if (newParts[i] < curParts[i]) return false;
      }

      final buildNew = cleanNew.contains('+')
          ? int.tryParse(
              cleanNew.split('+').last.replaceAll(RegExp(r'[^0-9]'), ''),
            )
          : null;
      final buildCur = cleanCur.contains('+')
          ? int.tryParse(
              cleanCur.split('+').last.replaceAll(RegExp(r'[^0-9]'), ''),
            )
          : null;
      if (buildNew != null && buildCur != null) {
        return buildNew > buildCur;
      }
    } catch (_) {}
    return false;
  }

  Future<List<String>> _getDeviceAbis() async {
    if (!Platform.isAndroid) return const ['arm64-v8a'];
    try {
      final abis = await _platformChannel
          .invokeListMethod<String>('getSupportedAbis')
          .timeout(const Duration(seconds: 2));
      if (abis != null && abis.isNotEmpty) return abis;
    } catch (_) {}
    return const ['arm64-v8a', 'armeabi-v7a'];
  }

  /// Selects the best matching APK asset from GitHub Releases for the device CPU architecture.
  static Map<String, dynamic>? selectBestApkAsset(
    List<dynamic> assets,
    List<String> deviceAbis,
  ) {
    final apkAssets = assets.whereType<Map<String, dynamic>>().where((a) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      final url = (a['browser_download_url'] as String? ?? '').toLowerCase();
      return name.endsWith('.apk') &&
          (url.startsWith('https://') || url.startsWith('http://'));
    }).toList();

    if (apkAssets.isEmpty) return null;

    for (final abi in deviceAbis) {
      final lowerAbi = abi.toLowerCase();
      for (final asset in apkAssets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.contains(lowerAbi)) return asset;
      }
    }

    for (final asset in apkAssets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.contains('universal')) return asset;
    }

    return apkAssets.first;
  }

  /// Selects the best matching Windows installer (.exe) asset from GitHub Releases.
  static Map<String, dynamic>? selectBestWindowsAsset(List<dynamic> assets) {
    final exeAssets = assets.whereType<Map<String, dynamic>>().where((a) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      final url = (a['browser_download_url'] as String? ?? '').toLowerCase();
      return name.endsWith('.exe') &&
          (url.startsWith('https://') || url.startsWith('http://'));
    }).toList();

    if (exeAssets.isEmpty) return null;

    for (final keyword in const ['setup', 'installer', 'mediacenter', 'x64', 'windows']) {
      for (final asset in exeAssets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.contains(keyword)) return asset;
      }
    }

    return exeAssets.first;
  }

  /// Checks GitHub Releases API (`zusfan-ops/Musik-Player`) with `latest.json` fallback.
  Future<AppRelease?> checkLatestRelease({bool force = false}) async {
    await getAppVersion();

    if (!force && _lastCheckedAt != null) {
      if (DateTime.now().difference(_lastCheckedAt!).inMinutes < 5) {
        return availableUpdateNotifier.value;
      }
    }

    if (_isChecking) return availableUpdateNotifier.value;
    _isChecking = true;

    try {
      final isWindows = !kIsWeb && Platform.isWindows;
      final userAgent =
          isWindows ? 'MediaCenter-Windows' : 'M3UMusikPlayer-Android';
      final abis = await _getDeviceAbis();
      final currentFullVer = _cachedBuildNumber.isNotEmpty
          ? '$_cachedVersion+$_cachedBuildNumber'
          : _cachedVersion;

      // 1. Primary: GitHub Releases API
      try {
        final res = await http.get(
          Uri.parse(githubLatestApiUrl),
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': userAgent,
          },
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final data =
              jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          final tag = (data['tag_name'] ?? data['name'] ?? '').toString().trim();
          final assets = data['assets'] as List<dynamic>? ?? const [];
          final selectedAsset = isWindows
              ? selectBestWindowsAsset(assets)
              : selectBestApkAsset(assets, abis);

          if (tag.isNotEmpty &&
              selectedAsset != null &&
              isNewerVersion(tag, currentFullVer)) {
            final release = AppRelease(
              version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
              apkUrl: selectedAsset['browser_download_url'] as String,
              apkName: selectedAsset['name'] as String?,
              apkSizeBytes: (selectedAsset['size'] as num?)?.toInt(),
              notes: (data['body'] as String?)?.trim(),
              htmlUrl: data['html_url'] as String?,
            );
            availableUpdateNotifier.value = release;
            _lastCheckedAt = DateTime.now();
            return release;
          }
          if (tag.isNotEmpty && !isNewerVersion(tag, currentFullVer)) {
            availableUpdateNotifier.value = null;
            _lastCheckedAt = DateTime.now();
            return null;
          }
        }
      } catch (_) {}

      // 2. Fallback: raw `public/release/latest.json` from repo
      try {
        final latestRes = await http.get(
          Uri.parse(rawLatestJsonUrl),
          headers: {
            'Accept': 'application/json',
            'User-Agent': userAgent,
          },
        ).timeout(const Duration(seconds: 8));

        if (latestRes.statusCode == 200) {
          final data = jsonDecode(utf8.decode(latestRes.bodyBytes))
              as Map<String, dynamic>;
          final latestVer = (data['version'] ?? '').toString().trim();
          final dl = isWindows
              ? (data['windows_download_url'] ?? '').toString().trim()
              : (data['download_url'] ?? '').toString().trim();
          final buildNo = data['build_number'];
          final latestFullVer =
              buildNo != null ? '$latestVer+$buildNo' : latestVer;

          if (latestVer.isNotEmpty &&
              dl.isNotEmpty &&
              isNewerVersion(latestFullVer, currentFullVer)) {
            String resolvedApkUrl = dl.startsWith('http')
                ? dl
                : '$rawRepoBaseUrl${dl.startsWith('/') ? dl : '/$dl'}';

            // Try matching user's ABI filename if download_url points to arm64-v8a
            if (!isWindows &&
                abis.isNotEmpty &&
                resolvedApkUrl.contains('arm64-v8a')) {
              final primaryAbi = abis.first;
              if (primaryAbi == 'armeabi-v7a' || primaryAbi == 'x86_64') {
                resolvedApkUrl =
                    resolvedApkUrl.replaceAll('arm64-v8a', primaryAbi);
              }
            }

            final cleanUri = Uri.tryParse(resolvedApkUrl);
            final derivedApkName =
                (cleanUri != null && cleanUri.pathSegments.isNotEmpty)
                    ? cleanUri.pathSegments.last
                    : resolvedApkNameFromUrl(resolvedApkUrl);

            final release = AppRelease(
              version: latestVer,
              apkUrl: resolvedApkUrl,
              apkName: derivedApkName,
              notes: (data['changelog'] as String?)?.trim(),
            );
            availableUpdateNotifier.value = release;
            _lastCheckedAt = DateTime.now();
            return release;
          }
        }
      } catch (_) {}

      _lastCheckedAt = DateTime.now();
    } finally {
      _isChecking = false;
    }
    return availableUpdateNotifier.value;
  }

  static String resolvedApkNameFromUrl(String url) {
    final clean = url.split('?').first.split('#').first;
    final last = clean.split('/').last;
    return last.isNotEmpty ? last : 'M3UMusik-update.apk';
  }

  Future<void> dismissRelease(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDismissedVerKey, version);
      await prefs.setInt(
        _kDismissedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<bool> _isDismissedRecently(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ver = prefs.getString(_kDismissedVerKey);
      final ts = prefs.getInt(_kDismissedAtKey);
      if (ver == version && ts != null) {
        final dismissedAt = DateTime.fromMillisecondsSinceEpoch(ts);
        return DateTime.now().difference(dismissedAt).inHours < 24;
      }
    } catch (_) {}
    return false;
  }

  /// Checks for updates and shows the in-app OTA UpdateDialog when a newer release exists.
  Future<void> checkAndShowUpdateDialog(
    BuildContext context, {
    bool isManualCheck = false,
  }) async {
    if (kIsWeb && !isManualCheck) return;
    if (!isManualCheck && _hasPromptedThisSession) return;

    if (isManualCheck) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Memeriksa pembaruan di GitHub Releases...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }

    final release = await checkLatestRelease(force: isManualCheck);
    if (!context.mounted) return;

    if (release != null) {
      if (!isManualCheck && await _isDismissedRecently(release.version)) {
        return;
      }
      if (!context.mounted) return;
      _hasPromptedThisSession = true;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => UpdateDialog(
          release: release,
          currentVersion: currentVersion,
        ),
      );
    } else if (isManualCheck) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aplikasi sudah versi terbaru (v$currentVersion).'),
        ),
      );
    }
  }
}
