import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/jellyfin_profile_models.dart';

class JellyfinConnectionResult {
  final String normalizedServerUrl;
  final String serverName;
  final String serverVersion;
  final List<JellyfinUserSummary> users;

  const JellyfinConnectionResult({
    required this.normalizedServerUrl,
    required this.serverName,
    required this.serverVersion,
    required this.users,
  });
}

class JellyfinService {
  static const Duration _timeout = Duration(seconds: 20);
  static const String defaultDeviceId = 'm3u-musik-android-client';

  /// Validates and normalizes a Jellyfin base URL (e.g. `http://192.168.1.10:8096` or `https://media.example.com/jellyfin`).
  static String normalizeServerUrl(String rawUrl) {
    String trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Alamat Server Jellyfin tidak boleh kosong.');
    }
    if (!trimmed.contains('://')) {
      trimmed = 'http://$trimmed';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Format URL Server Jellyfin tidak valid (contoh: http://192.168.1.10:8096).',
      );
    }
    return uri.toString();
  }

  static String validateApiKey(String rawKey) {
    final cleaned = rawKey.trim();
    if (cleaned.isEmpty) {
      throw const FormatException('API Code Jellyfin tidak boleh kosong.');
    }
    if (cleaned.length < 8 || cleaned.contains(RegExp(r'\s'))) {
      throw const FormatException(
        'API Code Jellyfin tidak valid (pastikan tanpa spasi).',
      );
    }
    return cleaned;
  }

  /// Standard Jellyfin 10.8–10.11+ authorization headers (`Authorization: MediaBrowser ...` + legacy `X-Emby-Token`).
  static Map<String, String> buildAuthHeaders(
    String apiKey, {
    String deviceId = defaultDeviceId,
  }) {
    final safeToken = apiKey.replaceAll('"', '');
    final mediaBrowserAuth =
        'MediaBrowser Client="M3U Musik Cinema", Device="Android", DeviceId="$deviceId", Version="1.2.2", Token="$safeToken"';
    return {
      'Accept': 'application/json',
      'Authorization': mediaBrowserAuth,
      'X-Emby-Token': safeToken,
      'X-Emby-Authorization': mediaBrowserAuth,
    };
  }

  /// Scrubs any accidental token appearance from error strings before displaying in UI.
  static String sanitizeErrorMessage(Object error, String? apiKey) {
    String msg = error.toString();
    if (apiKey != null && apiKey.isNotEmpty) {
      msg = msg.replaceAll(apiKey, '***');
    }
    msg = msg.replaceAll(
      RegExp(r'api_key=[^&\s]+', caseSensitive: false),
      'api_key=***',
    );
    return msg;
  }

  /// Verifies Server URL + API Code against `/System/Info` and discovers available Jellyfin users.
  static Future<JellyfinConnectionResult> testAndDiscoverServer({
    required String rawServerUrl,
    required String rawApiKey,
  }) async {
    final baseUrl = normalizeServerUrl(rawServerUrl);
    final apiKey = validateApiKey(rawApiKey);
    final headers = buildAuthHeaders(apiKey);

    final infoUri = Uri.parse('$baseUrl/System/Info');
    final infoRes = await http.get(infoUri, headers: headers).timeout(_timeout);

    if (infoRes.statusCode == 401 || infoRes.statusCode == 403) {
      throw const HttpException(
        'API Code Jellyfin ditolak (401/403). Periksa kembali API Key di Dashboard Jellyfin -> API Keys.',
      );
    }
    if (infoRes.statusCode < 200 || infoRes.statusCode >= 300) {
      throw HttpException(
        'Server Jellyfin merespons HTTP ${infoRes.statusCode}. Pastikan URL Server benar.',
      );
    }

    final infoJson =
        jsonDecode(utf8.decode(infoRes.bodyBytes)) as Map<String, dynamic>;
    final serverName = infoJson['ServerName'] as String? ?? 'Jellyfin Server';
    final version = infoJson['Version'] as String? ?? '';

    final List<JellyfinUserSummary> users = [];
    try {
      final usersRes = await http
          .get(Uri.parse('$baseUrl/Users'), headers: headers)
          .timeout(_timeout);
      if (usersRes.statusCode >= 200 && usersRes.statusCode < 300) {
        final rawList =
            jsonDecode(utf8.decode(usersRes.bodyBytes)) as List<dynamic>;
        for (final item in rawList.whereType<Map<String, dynamic>>()) {
          final id = item['Id'] as String? ?? '';
          if (id.isEmpty) continue;
          users.add(
            JellyfinUserSummary(
              id: id,
              name: item['Name'] as String? ?? 'User',
              hasPrimaryImage: item['PrimaryImageTag'] != null,
            ),
          );
        }
      } else {
        final meRes = await http
            .get(Uri.parse('$baseUrl/Users/Me'), headers: headers)
            .timeout(_timeout);
        if (meRes.statusCode >= 200 && meRes.statusCode < 300) {
          final meJson =
              jsonDecode(utf8.decode(meRes.bodyBytes)) as Map<String, dynamic>;
          final id = meJson['Id'] as String? ?? '';
          if (id.isNotEmpty) {
            users.add(
              JellyfinUserSummary(
                id: id,
                name: meJson['Name'] as String? ?? 'User',
                hasPrimaryImage: meJson['PrimaryImageTag'] != null,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Server-level /Items still works even if /Users is restricted
    }

    return JellyfinConnectionResult(
      normalizedServerUrl: baseUrl,
      serverName: serverName,
      serverVersion: version,
      users: users,
    );
  }

  /// Fetches Movies, Videos, and Episodes from Jellyfin.
  static Future<List<JellyfinMovieItem>> fetchMoviesAndVideos({
    required String serverUrl,
    required String apiKey,
    String? userId,
    String searchQuery = '',
    String includeTypes = 'Movie,Video,Episode',
    int limit = 100,
  }) async {
    final headers = buildAuthHeaders(apiKey);
    final queryParams = <String, String>{
      'Recursive': 'true',
      'IncludeItemTypes': includeTypes,
      'SortBy': 'DateCreated,SortName',
      'SortOrder': 'Descending',
      'Fields':
          'Overview,Genres,ProductionYear,CommunityRating,OfficialRating,RunTimeTicks,MediaSources',
      'Limit': '$limit',
      if (searchQuery.trim().isNotEmpty) 'SearchTerm': searchQuery.trim(),
    };

    final safeUser = (userId != null && userId.isNotEmpty)
        ? Uri.encodeComponent(userId)
        : null;
    final basePath = safeUser != null
        ? '$serverUrl/Users/$safeUser/Items'
        : '$serverUrl/Items';
    final uri = Uri.parse(basePath).replace(queryParameters: queryParams);

    final res = await http.get(uri, headers: headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'Gagal memuat daftar film Jellyfin (HTTP ${res.statusCode}).',
      );
    }

    final decoded =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final rawItems = decoded['Items'] as List<dynamic>? ?? const [];

    return rawItems
        .whereType<Map<String, dynamic>>()
        .map(JellyfinMovieItem.fromApiJson)
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  static String buildPrimaryImageUrl(String serverUrl, String itemId) {
    final safeId = Uri.encodeComponent(itemId);
    return '$serverUrl/Items/$safeId/Images/Primary?maxWidth=420&quality=85';
  }

  static String buildBackdropImageUrl(String serverUrl, String itemId) {
    final safeId = Uri.encodeComponent(itemId);
    return '$serverUrl/Items/$safeId/Images/Backdrop/0?maxWidth=960&quality=80';
  }

  static String buildUserAvatarUrl(String serverUrl, String userId) {
    final safeId = Uri.encodeComponent(userId);
    return '$serverUrl/Users/$safeId/Images/Primary?maxWidth=256&quality=85';
  }

  /// Direct static stream URL (uses `X-Emby-Token` HTTP header so API key is kept out of URLs).
  static Uri buildDirectStreamUri({
    required String serverUrl,
    required String itemId,
    String? mediaSourceId,
  }) {
    final safeId = Uri.encodeComponent(itemId);
    final params = <String, String>{
      'static': 'true',
      if (mediaSourceId != null && mediaSourceId.isNotEmpty)
        'MediaSourceId': mediaSourceId,
    };
    return Uri.parse('$serverUrl/Videos/$safeId/stream')
        .replace(queryParameters: params);
  }

  /// Universal HLS transcoded stream URL (H.264 + AAC) with required MediaSourceId & DeviceId.
  static Uri buildHlsStreamUri({
    required String serverUrl,
    required String itemId,
    String? mediaSourceId,
    required String playSessionId,
    String deviceId = defaultDeviceId,
  }) {
    final safeId = Uri.encodeComponent(itemId);
    final resolvedMediaSourceId =
        (mediaSourceId != null && mediaSourceId.isNotEmpty)
            ? mediaSourceId
            : itemId;
    final params = <String, String>{
      'MediaSourceId': resolvedMediaSourceId,
      'DeviceId': deviceId,
      'PlaySessionId': playSessionId,
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      'VideoBitrate': '7680000',
      'AudioBitrate': '320000',
      'MaxStreamingBitrate': '8000000',
      'SegmentContainer': 'ts',
      'TranscodingMaxAudioChannels': '2',
      'MinSegments': '1',
    };
    return Uri.parse('$serverUrl/Videos/$safeId/master.m3u8')
        .replace(queryParameters: params);
  }

  /// Stops active Jellyfin server-side ffmpeg transcoding when exiting HLS playback.
  static Future<void> stopActiveEncoding({
    required String serverUrl,
    required String apiKey,
    required String playSessionId,
    String deviceId = defaultDeviceId,
  }) async {
    if (serverUrl.isEmpty || apiKey.isEmpty || playSessionId.isEmpty) return;
    try {
      final uri = Uri.parse('$serverUrl/Videos/ActiveEncodings').replace(
        queryParameters: {
          'DeviceId': deviceId,
          'PlaySessionId': playSessionId,
        },
      );
      await http
          .delete(uri, headers: buildAuthHeaders(apiKey, deviceId: deviceId))
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Best-effort server cleanup
    }
  }
}
