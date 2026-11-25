import 'dart:io';

import 'package:path/path.dart' as p;

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

  /// Searches for a matching `.lrc` file alongside the local audio file.
  static Future<List<LyricLine>> loadLyricsForTrack(TrackItem track) async {
    if (!track.playsFromLocalFile) return const [];
    final audioPath = track.playableSource;
    if (audioPath.isEmpty) return const [];

    final dir = p.dirname(audioPath);
    final stem = p.basenameWithoutExtension(audioPath);
    final candidates = <String>[
      p.setExtension(audioPath, '.lrc'),
      p.setExtension(audioPath, '.LRC'),
      p.join(dir, 'Lyrics', '$stem.lrc'),
      p.join(dir, 'lyrics', '$stem.lrc'),
    ];

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
