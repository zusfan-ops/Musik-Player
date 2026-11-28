import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class GithubM3uFileEntry {
  final String name;
  final String sha;
  final String downloadUrl;

  const GithubM3uFileEntry({
    required this.name,
    required this.sha,
    required this.downloadUrl,
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
    if (decoded is! List) return const [];
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
}
