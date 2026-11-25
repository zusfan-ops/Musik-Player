import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/music_models.dart';

class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });
}

class LyricsService {
  static final RegExp _tagRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

  /// Parses `.lrc` content into chronologically sorted [LyricLine] items.
  static List<LyricLine> parseLrc(String content) {
    final List<LyricLine> lines = [];
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final matches = _tagRegex.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;

      final text = rawLine.replaceAll(_tagRegex, '').trim();
      if (text.isEmpty) continue;

      for (final m in matches) {
        final min = int.tryParse(m.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
        final fracRaw = m.group(3) ?? '0';
        int millis = 0;
        if (fracRaw.length == 1) {
          millis = (int.tryParse(fracRaw) ?? 0) * 100;
        } else if (fracRaw.length == 2) {
          millis = (int.tryParse(fracRaw) ?? 0) * 10;
        } else if (fracRaw.isNotEmpty) {
          millis = int.tryParse(fracRaw.substring(0, 3)) ?? 0;
        }
        lines.add(
          LyricLine(
            timestamp: Duration(minutes: min, seconds: sec, milliseconds: millis),
            text: text,
          ),
        );
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  /// Searches for a matching `.lrc` file alongside the local audio file or in app cache.
  static Future<List<LyricLine>> loadLyricsForTrack(TrackItem track) async {
    final List<String> candidates = [];

    if (track.playsFromLocalFile) {
      final audioPath = track.playableSource;
      if (audioPath.isNotEmpty) {
        final dir = p.dirname(audioPath);
        final stem = p.basenameWithoutExtension(audioPath);
        candidates.addAll([
          p.setExtension(audioPath, '.lrc'),
          p.setExtension(audioPath, '.LRC'),
          p.join(dir, 'Lyrics', '$stem.lrc'),
          p.join(dir, 'lyrics', '$stem.lrc'),
        ]);
      }
    }

    try {
      final cacheFile = await _cachedLrcFileForTrack(track);
      candidates.add(cacheFile.path);
    } catch (_) {}

    for (final path in candidates) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final raw = await file.readAsString();
          final parsed = parseLrc(raw);
          if (parsed.isNotEmpty) return parsed;
        }
      } catch (_) {
        // Ignore unreadable candidate and try next
      }
    }
    return const [];
  }

  static Future<File> _cachedLrcFileForTrack(TrackItem track) async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'MediaCenterLyrics'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File(p.join(dir.path, '$safeId.lrc'));
  }

  static String _cleanQueryPart(String raw) {
    return raw
        .replaceAll(RegExp(r'\[[a-zA-Z0-9_-]{11}\]'), '')
        .replaceAll(
          RegExp(
            r'\((official|lyric|lyrics|audio|video|mv|hd|4k)[^)]*\)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\[(official|lyric|lyrics|audio|video|mv|hd|4k)[^\]]*\]',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Auto-fetches synced LRC lyrics online via LRCLIB and caches `.lrc` locally.
  static Future<List<LyricLine>> fetchAndCacheOnlineLyrics(
    TrackItem track,
  ) async {
    final cleanTitle = _cleanQueryPart(track.title);
    final cleanArtist = _cleanQueryPart(track.artist);
    if (cleanTitle.isEmpty) return const [];

    final client = http.Client();
    try {
      String? syncedLrc;

      // 1. Try exact track+artist endpoint
      if (cleanArtist.isNotEmpty &&
          !cleanArtist.toLowerCase().contains('unknown') &&
          !cleanArtist.toLowerCase().contains('youtube')) {
        final getUri = Uri.https('lrclib.net', '/api/get', {
          'track_name': cleanTitle,
          'artist_name': cleanArtist,
          if (track.durationSeconds != null && track.durationSeconds! > 0)
            'duration': track.durationSeconds.toString(),
        });
        final res = await client.get(getUri).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map && decoded['syncedLyrics'] is String) {
            final candidate = (decoded['syncedLyrics'] as String).trim();
            if (candidate.isNotEmpty) syncedLrc = candidate;
          }
        }
      }

      // 2. Fallback to search endpoint
      if (syncedLrc == null) {
        final query = cleanArtist.isNotEmpty &&
                !cleanArtist.toLowerCase().contains('unknown')
            ? '$cleanArtist $cleanTitle'
            : cleanTitle;
        final searchUri = Uri.https('lrclib.net', '/api/search', {'q': query});
        final res =
            await client.get(searchUri).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map && item['syncedLyrics'] is String) {
                final candidate = (item['syncedLyrics'] as String).trim();
                if (candidate.isNotEmpty) {
                  syncedLrc = candidate;
                  break;
                }
              }
            }
          }
        }
      }

      if (syncedLrc == null || syncedLrc.isEmpty) return const [];
      final parsed = parseLrc(syncedLrc);
      if (parsed.isEmpty) return const [];

      try {
        final cacheFile = await _cachedLrcFileForTrack(track);
        await cacheFile.writeAsString(syncedLrc);
      } catch (_) {}

      return parsed;
    } catch (_) {
      return const [];
    } finally {
      client.close();
    }
  }

  /// Returns the active lyric index for [position], or -1 if before the first timestamp.
  static int activeLineIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    int low = 0;
    int high = lines.length - 1;
    int ans = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].timestamp <= position) {
        ans = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return ans;
  }
}
