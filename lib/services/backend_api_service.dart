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
    String? phone,
    String? address,
    bool activateStore = false,
    String? storeName,
    String? storeSlug,
    String? storeType,
    String? storeAddress,
    int? tablesCount,
  }) async {
    return _authenticate('/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (address != null && address.trim().isNotEmpty)
        'address': address.trim(),
      'activate_store': activateStore,
      if (activateStore) ...{
        if (storeName != null) 'store_name': storeName.trim(),
        if (storeSlug != null) 'store_slug': storeSlug.trim().toLowerCase(),
        if (storeType != null) 'store_type': storeType,
        if (storeAddress != null && storeAddress.trim().isNotEmpty)
          'store_address': storeAddress.trim(),
        if (tablesCount != null) 'tables_count': tablesCount,
      },
      'device_name': 'MediaCenter $_platformName',
      'platform': _platformName,
    });
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    return _authenticate('/auth/login', {
      'login': email.trim(),
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

  Future<String?> updateAccount({
    String? name,
    String? currentPassword,
    String? newPassword,
    http.Client? client,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return 'Silakan login terlebih dahulu.';

    final body = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) {
      body['name'] = name.trim();
    }
    if (newPassword != null && newPassword.isNotEmpty) {
      if (currentPassword == null || currentPassword.isEmpty) {
        return 'Kata sandi saat ini wajib diisi.';
      }
      if (newPassword.length < 8) {
        return 'Kata sandi baru minimal 8 karakter.';
      }
      body['current_password'] = currentPassword;
      body['new_password'] = newPassword;
    }
    if (body.isEmpty) return 'Tidak ada perubahan untuk disimpan.';

    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient
          .patch(
            Uri.parse('$baseUrl/me'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = decoded['data'] as Map<String, dynamic>?;
        final updatedName = data?['name'] as String?;
        if (updatedName != null && updatedName.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kUserNameKey, updatedName);
        }
        return null;
      }
      return decoded['message'] as String? ??
          'Gagal memperbarui akun (HTTP ${res.statusCode}).';
    } catch (e) {
      return 'Gagal menghubungi server: $e';
    } finally {
      if (client == null) activeClient.close();
    }
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

  Future<List<Map<String, dynamic>>> fetchDevices({http.Client? client}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return const [];
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient.get(
        Uri.parse('$baseUrl/me/devices'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = decoded['data'] as List<dynamic>? ?? const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    } finally {
      if (client == null) activeClient.close();
    }
  }

  Future<bool> revokeDevice(int deviceId, {http.Client? client}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient.delete(
        Uri.parse('$baseUrl/me/devices/$deviceId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      if (client == null) activeClient.close();
    }
  }

  Future<String?> exportAccountData({http.Client? client}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient.get(
        Uri.parse('$baseUrl/me/export'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return utf8.decode(res.bodyBytes);
    } catch (_) {
      return null;
    } finally {
      if (client == null) activeClient.close();
    }
  }

  Future<List<Map<String, dynamic>>> fetchWatchProgress({
    http.Client? client,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return const [];
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient.get(
        Uri.parse('$baseUrl/watch-progress'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = decoded['data'] as List<dynamic>? ?? const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    } finally {
      if (client == null) activeClient.close();
    }
  }

  Future<bool> pushWatchProgress({
    required String contentKey,
    required String title,
    required String contentType,
    required int positionSeconds,
    int durationSeconds = 0,
    String? streamUrl,
    http.Client? client,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient
          .put(
            Uri.parse('$baseUrl/watch-progress'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'items': [
                {
                  'content_key': contentKey,
                  'title': title,
                  'content_type': contentType,
                  'position_seconds': positionSeconds,
                  'duration_seconds': durationSeconds,
                  if (streamUrl != null &&
                      (streamUrl.startsWith('http://') ||
                          streamUrl.startsWith('https://')))
                    'stream_url': streamUrl,
                },
              ],
            }),
          )
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      if (client == null) activeClient.close();
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

  Future<({int playlistsAdded, int favoritesAdded})> pullFromCloud(
    MusicProvider music, {
    http.Client? client,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return (playlistsAdded: 0, favoritesAdded: 0);
    }
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient
          .get(
            Uri.parse('$baseUrl/sync'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return (playlistsAdded: 0, favoritesAdded: 0);
      }
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return await music.applyCloudSyncPayload(decoded);
    } catch (_) {
      return (playlistsAdded: 0, favoritesAdded: 0);
    } finally {
      if (client == null) activeClient.close();
    }
  }

  /// Pulls existing cloud data onto this device first, then pushes local additions.
  Future<String> syncBidirectional(MusicProvider music) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return 'Silakan masuk terlebih dahulu (opsional) untuk sinkronisasi.';
    }
    final pulled = await pullFromCloud(music);
    final pushMsg = await syncNow(music);
    if (pulled.playlistsAdded > 0 || pulled.favoritesAdded > 0) {
      return 'Sinkronisasi selesai (+${pulled.playlistsAdded} playlist, +${pulled.favoritesAdded} favorit dari cloud).';
    }
    return pushMsg;
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

  Future<List<Map<String, dynamic>>> fetchDiscoverStores({
    String? storeType,
    bool onlyOpen = false,
    double? lat,
    double? lng,
    http.Client? client,
  }) async {
    final activeClient = client ?? http.Client();
    try {
      final params = <String, String>{};
      if (storeType != null && storeType.isNotEmpty) {
        params['store_type'] = storeType;
      }
      if (onlyOpen) params['only_open'] = '1';
      if (lat != null && lng != null) {
        params['lat'] = lat.toString();
        params['lng'] = lng.toString();
      }
      final uri = Uri.parse('$baseUrl/stores/discover').replace(
        queryParameters: params.isEmpty ? null : params,
      );
      final res = await activeClient
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = decoded['data'] as List<dynamic>? ?? const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    } finally {
      if (client == null) activeClient.close();
    }
  }

  Future<Map<String, dynamic>?> fetchStoreDetail(
    String slug, {
    http.Client? client,
  }) async {
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient
          .get(
            Uri.parse('$baseUrl/stores/${Uri.encodeComponent(slug)}'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return decoded['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    } finally {
      if (client == null) activeClient.close();
    }
  }

  Future<void> trackStoreView(String slug, {int? productId}) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/stores/${Uri.encodeComponent(slug)}/track'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              if (productId != null) 'product_id': productId,
            }),
          )
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> fetchNativeAds({
    String placement = 'home_feed',
    http.Client? client,
  }) async {
    final activeClient = client ?? http.Client();
    try {
      final installId = await getOrCreateInstallationId();
      final uri = Uri.parse('$baseUrl/ads').replace(
        queryParameters: {
          'placement': placement,
          'platform': _platformName,
          'installation_id': installId,
        },
      );
      final res = await activeClient
          .get(
            uri,
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = decoded['data'] as List<dynamic>? ?? const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    } finally {
      if (client == null) activeClient.close();
    }
  }

  Future<void> trackAdClick(int adId) async {
    try {
      final installId = await getOrCreateInstallationId();
      await http
          .post(
            Uri.parse('$baseUrl/ads/$adId/click'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'platform': _platformName,
              'installation_id': installId,
            }),
          )
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> fetchMyStore() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/store/me'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return decoded['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> upsertMyStore({
    required String name,
    required String slug,
    required String storeType,
    String? description,
    String? address,
    double? latitude,
    double? longitude,
    String? whatsappNumber,
    int tablesCount = 0,
    String? googleMapsReviewUrl,
    String? openingHours,
    bool? isOpen,
    String? staffPin,
    bool clearStaffPin = false,
    List<Map<String, dynamic>>? products,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return 'Silakan login terlebih dahulu.';
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/store/me'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'name': name.trim(),
              'slug': slug.trim().toLowerCase(),
              'store_type': storeType,
              if (description != null) 'description': description.trim(),
              if (address != null) 'address': address.trim(),
              if (latitude != null) 'latitude': latitude,
              if (longitude != null) 'longitude': longitude,
              if (whatsappNumber != null)
                'whatsapp_number': whatsappNumber.trim(),
              'tables_count': tablesCount,
              if (googleMapsReviewUrl != null)
                'google_maps_review_url': googleMapsReviewUrl.trim().isEmpty
                    ? null
                    : googleMapsReviewUrl.trim(),
              if (openingHours != null)
                'opening_hours': openingHours.trim().isEmpty
                    ? null
                    : openingHours.trim(),
              if (isOpen != null) 'is_open': isOpen,
              if (staffPin != null && staffPin.trim().isNotEmpty)
                'staff_pin': staffPin.trim(),
              if (clearStaffPin) 'clear_staff_pin': true,
              if (products != null) 'products': products,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return decoded['message'] as String? ??
          'Gagal menyimpan toko (HTTP ${res.statusCode}).';
    } catch (e) {
      return 'Gagal menghubungi server: $e';
    }
  }

  Future<String?> uploadStoreQris(String filePath) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return 'Silakan login terlebih dahulu.';
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/store/me/qris'),
      );
      req.headers['Accept'] = 'application/json';
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('qris_file', filePath));
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return decoded['message'] as String? ?? 'Gagal upload QRIS.';
    } catch (e) {
      return 'Gagal upload QRIS: $e';
    }
  }

  Future<bool> verifyStaffPin(String pin) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/store/me/verify-pin'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'pin': pin}),
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return decoded['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> createStoreVoucher({
    required String code,
    required String discountType,
    required double discountValue,
    double minOrder = 0,
    int? maxUses,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return 'Silakan login terlebih dahulu.';
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/store/vouchers'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'code': code.trim().toUpperCase(),
              'discount_type': discountType,
              'discount_value': discountValue,
              'min_order': minOrder,
              if (maxUses != null) 'max_uses': maxUses,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return decoded['message'] as String? ?? 'Gagal membuat voucher.';
    } catch (e) {
      return 'Gagal membuat voucher: $e';
    }
  }

  Future<void> deleteStoreVoucher(int voucherId) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    try {
      await http
          .delete(
            Uri.parse('$baseUrl/store/vouchers/$voucherId'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<void> updateStoreNowPlaying(String? title, String? artist) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('$baseUrl/store/jukebox/now-playing'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'title': title, 'artist': artist}),
          )
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<void> updateJukeboxStatus(int requestId, String status) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    try {
      await http
          .patch(
            Uri.parse('$baseUrl/store/jukebox/$requestId'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'status': status}),
          )
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> syncStoreFinance(
    List<Map<String, dynamic>> entries,
  ) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/store/finance/sync'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'entries': entries}),
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = decoded['data'] as List<dynamic>? ?? const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return null;
    }
  }

  Future<String?> submitBoostAd({
    required String title,
    String? description,
    required String mediaType,
    String? mediaFilePath,
    String? mediaUrl,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return 'Silakan login terlebih dahulu.';
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/store/boost-ad'),
      );
      req.headers['Accept'] = 'application/json';
      req.headers['Authorization'] = 'Bearer $token';
      req.fields['title'] = title.trim();
      req.fields['media_type'] = mediaType;
      req.fields['placement'] = 'home_feed';
      if (description != null && description.trim().isNotEmpty) {
        req.fields['description'] = description.trim();
      }
      if (mediaFilePath != null && mediaFilePath.isNotEmpty) {
        req.files.add(
          await http.MultipartFile.fromPath('media_file', mediaFilePath),
        );
      } else if (mediaUrl != null && mediaUrl.trim().isNotEmpty) {
        req.fields['media_url'] = mediaUrl.trim();
      }
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return decoded['message'] as String? ?? 'Gagal mengajukan Boost Toko.';
    } catch (e) {
      return 'Gagal mengajukan Boost Toko: $e';
    }
  }

  Future<String?> updateStoreOrderStatus(int orderId, String status) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return 'Silakan login terlebih dahulu.';
    try {
      final res = await http
          .patch(
            Uri.parse('$baseUrl/store/orders/$orderId'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'status': status}),
          )
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      return 'Gagal memperbarui status pesanan.';
    } catch (e) {
      return 'Gagal menghubungi server: $e';
    }
  }

  Future<String?> bookCoffeeshopTable({
    required String slug,
    required String tableNumber,
    required int guestsCount,
    required DateTime bookingTime,
    required String customerWhatsapp,
    String? notes,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return 'Hanya user terdaftar yang dapat booking meja. Silakan login terlebih dahulu.';
    }
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/stores/${Uri.encodeComponent(slug)}/bookings'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'table_number': tableNumber,
              'guests_count': guestsCount,
              'booking_time': bookingTime.toIso8601String(),
              'customer_whatsapp': customerWhatsapp.trim(),
              if (notes != null && notes.trim().isNotEmpty)
                'notes': notes.trim(),
            }),
          )
          .timeout(_timeout);
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      return decoded['message'] as String? ?? 'Gagal booking meja.';
    } catch (e) {
      return 'Gagal menghubungi server: $e';
    }
  }

  Future<List<Map<String, dynamic>>> fetchFeedbackTickets({
    http.Client? client,
  }) async {
    final activeClient = client ?? http.Client();
    try {
      final installId = await getOrCreateInstallationId();
      final token = await getToken();
      final uri = Uri.parse('$baseUrl/feedback').replace(
        queryParameters: {'installation_id': installId},
      );
      final res = await activeClient
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = decoded['data'] as List<dynamic>? ?? const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    } finally {
      if (client == null) activeClient.close();
    }
  }

  Future<Map<String, dynamic>> submitFeedbackTicket({
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
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {
          'ok': true,
          'message': decoded['message'] ?? 'Laporan berhasil dikirim.',
          'data': decoded['data'],
        };
      }
      return {
        'ok': false,
        'message':
            decoded['message'] ?? 'Gagal mengirim laporan (HTTP ${res.statusCode}).',
      };
    } catch (e) {
      return {'ok': false, 'message': 'Tidak dapat terhubung ke server: $e'};
    }
  }

  Future<Map<String, dynamic>> replyFeedbackTicket({
    required int ticketId,
    required String message,
  }) async {
    try {
      final installId = await getOrCreateInstallationId();
      final token = await getToken();
      final res = await http
          .post(
            Uri.parse('$baseUrl/feedback/$ticketId/reply'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'installation_id': installId,
              'message': message.trim(),
            }),
          )
          .timeout(_timeout);
      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {
          'ok': true,
          'message': decoded['message'] ?? 'Balasan terkirim.',
          'data': decoded['data'],
        };
      }
      return {
        'ok': false,
        'message': decoded['message'] ?? 'Gagal mengirim balasan.',
      };
    } catch (e) {
      return {'ok': false, 'message': 'Tidak dapat terhubung ke server: $e'};
    }
  }

  static const String _kLastSeenAdminMsgIdKey =
      'mc_last_seen_admin_msg_id_v1';

  Future<int> fetchUnreadAdminRepliesCount() async {
    try {
      final tickets = await fetchFeedbackTickets();
      if (tickets.isEmpty) return 0;
      final prefs = await SharedPreferences.getInstance();
      final lastSeenId = prefs.getInt(_kLastSeenAdminMsgIdKey) ?? 0;

      int unread = 0;
      for (final t in tickets) {
        final msgs = (t['messages'] as List?)
                ?.whereType<Map>()
                .toList() ??
            const <Map>[];
        if (msgs.isEmpty) continue;
        final lastMsg = msgs.last;
        final msgId = (lastMsg['id'] as num?)?.toInt() ?? 0;
        if (lastMsg['sender_type'] == 'admin' && msgId > lastSeenId) {
          unread++;
        }
      }
      return unread;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markAdminRepliesAsSeen(
    List<Map<String, dynamic>> tickets,
  ) async {
    try {
      int maxId = 0;
      for (final t in tickets) {
        final msgs = (t['messages'] as List?)?.whereType<Map>() ?? const [];
        for (final m in msgs) {
          if (m['sender_type'] == 'admin') {
            final id = (m['id'] as num?)?.toInt() ?? 0;
            if (id > maxId) maxId = id;
          }
        }
      }
      if (maxId > 0) {
        final prefs = await SharedPreferences.getInstance();
        final prev = prefs.getInt(_kLastSeenAdminMsgIdKey) ?? 0;
        if (maxId > prev) {
          await prefs.setInt(_kLastSeenAdminMsgIdKey, maxId);
        }
      }
    } catch (_) {}
  }
}
