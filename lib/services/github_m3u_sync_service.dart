import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'backend_api_service.dart';

class GithubM3uFileEntry {
  final String name;
  final String sha;
  final String downloadUrl;
  final String? category;

  const GithubM3uFileEntry({
    required this.name,
    required this.sha,
    required this.downloadUrl,
    this.category,
  });
}

/// Checks `https://github.com/zusfan-ops/Musik-Player/tree/main/m3u` via the
/// GitHub Contents API for new or updated `.m3u` / `.m3u8` files using Git blob SHAs.
class GithubM3uSyncService {
  static const String apiContentsUrl =
      'https://api.github.com/repos/zusfan-ops/Musik-Player/contents/m3u?ref=main';
  static const Duration _timeout = Duration(seconds: 12);

  static const Map<String, String> _headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'MediaCenter-M3U-Player',
  };

  static List<GithubM3uFileEntry> parseContentsResponse(String jsonBody) {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! List) {
      throw const FormatException('Respons GitHub Contents API tidak valid.');
    }
    final entries = <GithubM3uFileEntry>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type'] != 'file') continue;
      final name = (item['name'] as String? ?? '').trim();
      final sha = (item['sha'] as String? ?? '').trim();
      final downloadUrl = (item['download_url'] as String? ?? '').trim();
      final lower = name.toLowerCase();
      if (!(lower.endsWith('.m3u') || lower.endsWith('.m3u8'))) continue;
      if (sha.isEmpty || downloadUrl.isEmpty) continue;
      entries.add(
        GithubM3uFileEntry(
          name: name,
          sha: sha,
          downloadUrl: downloadUrl,
        ),
      );
    }
    return entries;
  }

  static List<GithubM3uFileEntry> diffChangedEntries({
    required List<GithubM3uFileEntry> remoteEntries,
    required Map<String, String> knownShas,
  }) {
    return remoteEntries
        .where((e) => knownShas[e.name] != e.sha)
        .toList();
  }

  static String formatPlaylistDisplayName(String fileName) {
    final rawBase = p.basenameWithoutExtension(fileName);
    return rawBase
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(
          (w) => w.toUpperCase() == 'CCTV'
              ? 'CCTV'
              : w[0].toUpperCase() + w.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  static Future<List<GithubM3uFileEntry>> fetchRemoteEntries({
    http.Client? client,
  }) async {
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient
          .get(Uri.parse(apiContentsUrl), headers: _headers)
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException(
          'Gagal memeriksa daftar M3U GitHub (HTTP ${res.statusCode}).',
        );
      }
      return parseContentsResponse(utf8.decode(res.bodyBytes));
    } finally {
      if (client == null) activeClient.close();
    }
  }

  static Future<Uint8List> downloadFileBytes(
    String downloadUrl, {
    http.Client? client,
  }) async {
    final activeClient = client ?? http.Client();
    try {
      final res = await activeClient
          .get(Uri.parse(downloadUrl), headers: const {
            'User-Agent': 'MediaCenter-M3U-Player',
          })
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException(
          'Gagal mengunduh file M3U GitHub (HTTP ${res.statusCode}).',
        );
      }
      return res.bodyBytes;
    } finally {
      if (client == null) activeClient.close();
    }
  }

  static List<GithubM3uFileEntry> parseBackendSourcesResponse(String jsonBody) {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons M3U backend tidak valid.');
    }
    final rawSources = decoded['sources'];
    if (rawSources is! List) return const [];
    final entries = <GithubM3uFileEntry>[];
    for (final item in rawSources) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String? ?? '').trim();
      final sha = (item['sha256'] as String? ?? '').trim();
      final downloadUrl = (item['download_url'] as String? ?? '').trim();
      final category = (item['category'] as String? ?? '').trim();
      if (name.isEmpty || sha.isEmpty || downloadUrl.isEmpty) continue;
      entries.add(
        GithubM3uFileEntry(
          name: name,
          sha: sha,
          downloadUrl: downloadUrl,
          category: category.isNotEmpty ? category : null,
        ),
      );
    }
    return entries;
  }

  /// Fetches active M3U sources from the MediaCenter backend.
  /// Returns `null` when backend is unreachable so GitHub sync continues unaffected.
  static Future<List<GithubM3uFileEntry>?> fetchBackendEntries({
    String? baseUrl,
    http.Client? client,
  }) async {
    final activeClient = client ?? http.Client();
    final endpoint = '${baseUrl ?? BackendApiService.baseUrl}/m3u-sources';
    try {
      final res = await activeClient
          .get(Uri.parse(endpoint), headers: const {
            'Accept': 'application/json',
            'User-Agent': 'MediaCenter-M3U-Player',
          })
          .timeout(const Duration(seconds: 6));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return parseBackendSourcesResponse(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    } finally {
      if (client == null) activeClient.close();
    }
  }
}
