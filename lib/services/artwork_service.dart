import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/music_models.dart';

/// Automatically searches and caches high-resolution album/track artwork locally
/// for offline music directories and streams.
class ArtworkService {
  static final Map<String, String> _memoryCache = {};
  static final Set<String> _inFlightIds = {};
  static final Set<String> _notFoundIds = {};
  static bool _diskWarmed = false;

  static String? getCachedLocalPath(String trackId) {
    final path = _memoryCache[trackId];
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
    return null;
  }

  static Future<Directory> _getArtworkDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'MediaCenterArtwork'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> warmCacheFromDisk() async {
    if (_diskWarmed) return;
    _diskWarmed = true;
    try {
      final dir = await _getArtworkDir();
      final indexFile = File(p.join(dir.path, 'artwork_index.json'));
      if (!await indexFile.exists()) return;
      final raw = await indexFile.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final path = entry.value?.toString() ?? '';
          if (path.isNotEmpty && File(path).existsSync()) {
            _memoryCache[entry.key] = path;
          }
        }
      }
    } catch (_) {}
  }

  static Future<void> _persistIndex() async {
    try {
      final dir = await _getArtworkDir();
      final indexFile = File(p.join(dir.path, 'artwork_index.json'));
      await indexFile.writeAsString(jsonEncode(_memoryCache));
    } catch (_) {}
  }

  static String _cleanTerm(String raw) {
    return raw
        .replaceAll(RegExp(r'\[[a-zA-Z0-9_-]{11}\]'), '')
        .replaceAll(
          RegExp(
            r'\((official|lyric|lyrics|audio|video|mv|hd|4k|remastered)[^)]*\)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\[(official|lyric|lyrics|audio|video|mv|hd|4k|remastered)[^\]]*\]',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'^\d{1,3}[\s._-]+'), '')
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _buildSearchQuery(TrackItem track) {
    final title = _cleanTerm(track.title);
    final rawArtist = _cleanTerm(track.artist);
    final lowerArtist = rawArtist.toLowerCase();
    final hasRealArtist = rawArtist.isNotEmpty &&
        !lowerArtist.contains('unknown') &&
        !lowerArtist.contains('musik lokal') &&
        !lowerArtist.contains('artist') &&
        !lowerArtist.contains('youtube');
    if (hasRealArtist) {
      return '$rawArtist $title'.trim();
    }
    final dirName = _cleanTerm(track.directoryName);
    final lowerDir = dirName.toLowerCase();
    if (dirName.isNotEmpty &&
        lowerDir != 'music' &&
        lowerDir != 'musik' &&
        lowerDir != 'download' &&
        lowerDir != 'downloads' &&
        lowerDir != 'lagu offline') {
      return '$dirName $title'.trim();
    }
    return title;
  }

  static Future<String?> _findArtworkUrlOnline(String query) async {
    if (query.isEmpty) return null;
    final client = http.Client();
    try {
      // 1. iTunes Search API (fast, free, high-res 600x600 album art)
      final itunesUri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'entity': 'song',
        'limit': '1',
      });
      final res =
          await client.get(itunesUri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final results = decoded is Map ? decoded['results'] : null;
        if (results is List && results.isNotEmpty) {
          final first = results.first;
          if (first is Map) {
            final url100 = first['artworkUrl100']?.toString() ?? '';
            if (url100.isNotEmpty) {
              return url100.replaceAll('100x100bb', '600x600bb');
            }
          }
        }
      }

      // 2. Fallback: Deezer Search API
      final deezerUri = Uri.https('api.deezer.com', '/search', {
        'q': query,
        'limit': '1',
      });
      final dRes =
          await client.get(deezerUri).timeout(const Duration(seconds: 6));
      if (dRes.statusCode == 200) {
        final decoded = jsonDecode(dRes.body);
        final data = decoded is Map ? decoded['data'] : null;
        if (data is List && data.isNotEmpty) {
          final first = data.first;
          final album = first is Map ? first['album'] : null;
          if (album is Map) {
            final cover = (album['cover_big'] ?? album['cover_medium'])
                    ?.toString() ??
                '';
            if (cover.isNotEmpty) return cover;
          }
        }
      }
    } catch (_) {
      // Network unavailable or blocked
    } finally {
      client.close();
    }
    return null;
  }

  /// Searches online for [track]'s artwork and caches it locally in `MediaCenterArtwork/`.
  static Future<String?> fetchAndCacheArtworkForTrack(TrackItem track) async {
    await warmCacheFromDisk();

    if (track.hasLocalArtwork) return track.artworkUrl;
    final cached = getCachedLocalPath(track.id);
    if (cached != null) return cached;
    if (_notFoundIds.contains(track.id) || _inFlightIds.contains(track.id)) {
      return null;
    }

    _inFlightIds.add(track.id);
    try {
      final query = _buildSearchQuery(track);
      final imageUrl = await _findArtworkUrlOnline(query);
      if (imageUrl == null || imageUrl.isEmpty) {
        _notFoundIds.add(track.id);
        return null;
      }

      final dir = await _getArtworkDir();
      final safeId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFile = File(p.join(dir.path, '$safeId.jpg'));
      final res = await http
          .get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          res.bodyBytes.length > 512) {
        await targetFile.writeAsBytes(res.bodyBytes, flush: true);
        _memoryCache[track.id] = targetFile.path;
        return targetFile.path;
      }
      _notFoundIds.add(track.id);
      return null;
    } catch (_) {
      return null;
    } finally {
      _inFlightIds.remove(track.id);
    }
  }

  /// Fetches and caches artwork in small concurrent batches for tracks missing artwork.
  static Future<Map<String, String>> enrichTracksBatch(
    List<TrackItem> tracks, {
    int maxFetch = 24,
  }) async {
    await warmCacheFromDisk();
    final Map<String, String> updated = {};
    final List<TrackItem> candidates = [];

    for (final t in tracks) {
      if (t.isVideo) continue;
      if (t.hasLocalArtwork || t.hasValidNetworkArtwork) continue;
      final cached = getCachedLocalPath(t.id);
      if (cached != null) {
        updated[t.id] = cached;
      } else if (!_notFoundIds.contains(t.id) &&
          !_inFlightIds.contains(t.id)) {
        candidates.add(t);
      }
    }

    final toFetch = candidates.take(maxFetch).toList();
    const int concurrency = 4;
    for (int i = 0; i < toFetch.length; i += concurrency) {
      final slice = toFetch.skip(i).take(concurrency);
      await Future.wait(
        slice.map((t) async {
          final path = await fetchAndCacheArtworkForTrack(t);
          if (path != null) {
            updated[t.id] = path;
          }
        }),
      );
    }

    if (toFetch.isNotEmpty) {
      await _persistIndex();
    }
    return updated;
  }
}
