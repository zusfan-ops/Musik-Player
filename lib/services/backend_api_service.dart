import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../theme/app_theme.dart';

class BackendAnnouncement {
  final int id;
  final String title;
  final String body;
  final String type;

  const BackendAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
  });

  factory BackendAnnouncement.fromJson(Map<String, dynamic> j) =>
      BackendAnnouncement(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        type: j['type'] as String? ?? 'info',
      );
}

/// Optional guest-first & offline-first client for `https://mediacenter.ordr.my.id/api/v1`.
/// All local music/M3U features continue working when offline or unauthenticated.
class BackendApiService {
  BackendApiService._();
  static final BackendApiService instance = BackendApiService._();

  static const String baseUrl = String.fromEnvironment(
    'MEDIACENTER_API_BASE_URL',
    defaultValue: 'https://mediacenter.ordr.my.id/api/v1',
  );
  static const Duration _timeout = Duration(seconds: 10);

  static const String _kSecureTokenKey = 'mc_sanctum_token_v1';
  static const String _kInstallIdKey = 'mc_installation_id_v1';
  static const String _kAnalyticsOptInKey = 'mc_analytics_opt_in_v1';
  static const String _kUserEmailKey = 'mc_user_email_v1';
  static const String _kUserNameKey = 'mc_user_name_v1';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  String? _cachedToken;

  String get _platformName {
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    try {
      _cachedToken = await _secure.read(key: _kSecureTokenKey);
    } catch (_) {
      _cachedToken = null;
    }
    return _cachedToken;
  }

  Future<void> _saveToken(String? token) async {
    _cachedToken = token;
    try {
      if (token == null || token.isEmpty) {
        await _secure.delete(key: _kSecureTokenKey);
      } else {
        await _secure.write(key: _kSecureTokenKey, value: token);
      }
    } catch (_) {}
  }

  Future<({String? email, String? name, bool isLoggedIn})> getAccountState() async {
    final token = await getToken();
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_kUserEmailKey);
    final name = prefs.getString(_kUserNameKey);
    return (
      email: email,
      name: name,
      isLoggedIn: token != null && token.isNotEmpty,
    );
  }

  Future<String> getOrCreateInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kInstallIdKey);
    if (existing != null && existing.length >= 8) return existing;
    final generated = _generateRandomInstallId();
    await prefs.setString(_kInstallIdKey, generated);
    return generated;
  }

  Future<String> resetInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    final next = _generateRandomInstallId();
    await prefs.setString(_kInstallIdKey, next);
    return next;
  }

  String _generateRandomInstallId() {
    final rng = Random.secure();
    final hex = List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'inst-$hex';
  }

  Future<bool> isAnalyticsOptedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAnalyticsOptInKey) ?? false;
  }

  Future<void> setAnalyticsOptIn(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAnalyticsOptInKey, enabled);
  }

  Future<String?> register({
    required String name,
    required String email,
    required String password,
  }) async {
    return _authenticate('/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'device_name': 'MediaCenter $_platformName',
      'platform': _platformName,
    });
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    return _authenticate('/auth/login', {
      'email': email.trim(),
      'password': password,
      'device_name': 'MediaCenter $_platformName',
      'platform': _platformName,
    });
  }

  Future<String?> _authenticate(String path, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final token = decoded['token'] as String?;
        final user = decoded['user'] as Map<String, dynamic>?;
        await _saveToken(token);
        final prefs = await SharedPreferences.getInstance();
        if (user?['email'] is String) {
          await prefs.setString(_kUserEmailKey, user!['email'] as String);
        }
        if (user?['name'] is String) {
          await prefs.setString(_kUserNameKey, user!['name'] as String);
        }
        return null;
      }
      return decoded['message'] as String? ?? 'Autentikasi gagal (HTTP ${res.statusCode}).';
    } catch (e) {
      return 'Server tidak terjangkau (mode offline tetap aktif): $e';
    }
  }

  Future<void> logout() async {
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(_timeout);
      } catch (_) {}
    }
    await _saveToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserEmailKey);
    await prefs.remove(_kUserNameKey);
  }

  Future<String?> deleteAccount() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return 'Belum login.';
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/me'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _saveToken(null);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kUserEmailKey);
        await prefs.remove(_kUserNameKey);
        return null;
      }
      return 'Gagal menghapus akun (HTTP ${res.statusCode}).';
    } catch (e) {
      return 'Gagal menghubungi server: $e';
    }
  }

  /// Builds a privacy-safe sync payload: NEVER includes local filesystem paths.
  static Map<String, dynamic> buildSafeSyncPayload({
    required List<M3uPlaylist> playlists,
    required List<TrackItem> favorites,
    required String themeMode,
    required bool shuffleEnabled,
    required String repeatMode,
  }) {
    final safePlaylists = playlists.take(100).map((pl) {
      final isUrl = pl.sourceType == M3uSourceType.url &&
          (pl.sourceLocation.startsWith('http://') ||
              pl.sourceLocation.startsWith('https://'));
      return {
        'client_uid': pl.id,
        'name': pl.name,
        'source_type': isUrl ? 'url' : 'metadata_only',
        if (isUrl) 'source_url': pl.sourceLocation,
        'is_enabled': pl.isEnabled,
        'items': pl.tracks.take(200).map((t) {
          final hasRemoteUrl = !t.isLocalFile &&
              (t.pathOrUrl.startsWith('http://') ||
                  t.pathOrUrl.startsWith('https://') ||
                  t.pathOrUrl.startsWith('rtsp://') ||
                  t.pathOrUrl.startsWith('wss://'));
          return {
            'client_uid': t.id,
            'title': t.title,
            'artist': t.artist,
            'album': t.album,
            if (t.groupTitle != null) 'group_title': t.groupTitle,
            if (t.durationSeconds != null && t.durationSeconds! >= 0)
              'duration_seconds': t.durationSeconds,
            if (hasRemoteUrl) 'stream_url': t.pathOrUrl,
            'is_video': t.isVideo,
          };
        }).toList(),
      };
    }).toList();

    final safeFavorites = favorites.take(500).map((t) {
      final hasRemoteUrl = !t.isLocalFile &&
          (t.pathOrUrl.startsWith('http://') ||
              t.pathOrUrl.startsWith('https://'));
      return {
        'client_uid': t.id,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        if (t.durationSeconds != null && t.durationSeconds! >= 0)
          'duration_seconds': t.durationSeconds,
        'source_type': hasRemoteUrl ? 'remote_url' : 'local_metadata',
        if (hasRemoteUrl) 'stream_url': t.pathOrUrl,
        'is_video': t.isVideo,
      };
    }).toList();

    return {
      'playlists': safePlaylists,
      'favorites': safeFavorites,
      'settings': {
        'theme_mode': themeMode,
        'shuffle_enabled': shuffleEnabled,
        'repeat_mode': repeatMode,
      },
    };
  }

  Future<String> syncNow(MusicProvider music) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return 'Silakan masuk terlebih dahulu (opsional) untuk sinkronisasi.';
    }
    try {
      final themeStr = AppThemeController.modeNotifier.value.name;
      final payload = buildSafeSyncPayload(
        playlists: music.playlists,
        favorites: music.favoriteTracks,
        themeMode: themeStr,
        shuffleEnabled: music.shuffleEnabled,
        repeatMode: music.repeatMode.name,
      );
      final res = await http
          .put(
            Uri.parse('$baseUrl/sync'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      if (res.statusCode == 200 || res.statusCode == 207) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final conflicts = decoded['conflicts'] as List<dynamic>? ?? const [];
        if (conflicts.isNotEmpty) {
          return 'Sinkronisasi selesai dengan ${conflicts.length} konflik revisi.';
        }
        return 'Sinkronisasi berhasil (revisi #${decoded['sync_revision'] ?? '-'}).';
      }
      return 'Gagal sinkronisasi (HTTP ${res.statusCode}).';
    } catch (e) {
      return 'Gagal terhubung ke server (mode offline tetap aman): $e';
    }
  }

  Future<List<BackendAnnouncement>> fetchAnnouncements() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/announcements'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final data = decoded['data'] as List<dynamic>? ?? const [];
        return data
            .whereType<Map<String, dynamic>>()
            .map(BackendAnnouncement.fromJson)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> sendAnalyticsEvent(
    String eventName, {
    Map<String, dynamic>? properties,
  }) async {
    if (!await isAnalyticsOptedIn()) return;
    try {
      final installId = await getOrCreateInstallationId();
      await http
          .post(
            Uri.parse('$baseUrl/analytics/events'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'installation_id': installId,
              'events': [
                {
                  'event': eventName,
                  'platform': _platformName,
                  if (properties != null) 'properties': properties,
                },
              ],
            }),
          )
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<String> deleteDeviceAnalytics() async {
    final installId = await getOrCreateInstallationId();
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/analytics/installation/$installId'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      await resetInstallationId();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return 'Data analitik perangkat berhasil dihapus & ID direset.';
      }
      return 'ID analitik direset lokal (server HTTP ${res.statusCode}).';
    } catch (_) {
      await resetInstallationId();
      return 'ID analitik lokal direset (server sedang tidak terjangkau).';
    }
  }

  Future<String> submitFeedback({
    required String category,
    required String message,
    bool diagnosticsConsent = false,
  }) async {
    try {
      final installId = await getOrCreateInstallationId();
      final token = await getToken();
      final res = await http
          .post(
            Uri.parse('$baseUrl/feedback'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'installation_id': installId,
              'category': category,
              'message': message.trim(),
              'platform': _platformName,
              'diagnostics_consent': diagnosticsConsent,
              if (diagnosticsConsent)
                'diagnostics': {'platform': _platformName},
            }),
          )
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return 'Terima kasih, laporan Anda telah terkirim.';
      }
      return 'Gagal mengirim laporan (HTTP ${res.statusCode}).';
    } catch (e) {
      return 'Tidak dapat terhubung ke server: $e';
    }
  }
}
