import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/music_models.dart';

class NewTubeItem {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final String durationLabel;
  final String thumbnailUrl;

  const NewTubeItem({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    this.durationLabel = '',
    required this.thumbnailUrl,
  });

  String get formattedDuration {
    if (durationLabel.isNotEmpty) return durationLabel;
    final d = duration;
    if (d == null || d <= Duration.zero) return 'LIVE';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  TrackItem toTrackItem({
    required String streamUrl,
    bool asVideo = false,
  }) {
    return TrackItem(
      id: 'yt_$videoId',
      title: title,
      artist: author,
      album: 'NewTube • YouTube',
      sourceType: TrackSourceType.remoteStream,
      pathOrUrl: streamUrl,
      directoryPath: 'newtube://youtube',
      directoryName: 'NewTube • YouTube',
      artworkUrl: thumbnailUrl,
      durationSeconds: duration?.inSeconds,
      isVideo: asVideo,
      groupTitle: 'NewTube',
    );
  }
}

class NewTubeService {
  static final RegExp _videoIdRegex = RegExp(
    r'(?:v=|youtu\.be/|shorts/|embed/|live/)([a-zA-Z0-9_-]{11})',
  );

  /// Extracts a 11-character YouTube video ID from a URL or raw ID string.
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return _videoIdRegex.firstMatch(trimmed)?.group(1);
  }

  static Duration? _parseDurationText(String text) {
    final parts = text
        .trim()
        .split(':')
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toList();
    if (parts.length == 2) {
      return Duration(minutes: parts[0], seconds: parts[1]);
    }
    if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    return null;
  }

  static String _readRunsText(dynamic node) {
    if (node is! Map) return '';
    if (node['simpleText'] is String) return node['simpleText'] as String;
    if (node['runs'] is List) {
      return (node['runs'] as List)
          .whereType<Map>()
          .map((r) => r['text']?.toString() ?? '')
          .join()
          .trim();
    }
    return '';
  }

  static void _collectVideoRenderers(
    dynamic node,
    List<NewTubeItem> out,
    Set<String> seenIds,
  ) {
    if (out.length >= 25) return;
    if (node is List) {
      for (final item in node) {
        _collectVideoRenderers(item, out, seenIds);
        if (out.length >= 25) return;
      }
      return;
    }
    if (node is! Map) return;

    final vr = node['videoRenderer'];
    if (vr is Map) {
      final videoId = vr['videoId']?.toString() ?? '';
      if (videoId.length == 11 && seenIds.add(videoId)) {
        final title = _readRunsText(vr['title']);
        final author = _readRunsText(vr['ownerText']).isNotEmpty
            ? _readRunsText(vr['ownerText'])
            : _readRunsText(vr['longBylineText']);
        final lenText = _readRunsText(vr['lengthText']);
        String thumb = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        final thumbs = vr['thumbnail']?['thumbnails'];
        if (thumbs is List && thumbs.isNotEmpty) {
          final last = thumbs.last;
          if (last is Map && last['url'] is String) {
            thumb = last['url'] as String;
          }
        }
        if (title.isNotEmpty) {
          out.add(
            NewTubeItem(
              videoId: videoId,
              title: title,
              author: author.isEmpty ? 'YouTube' : author,
              duration: lenText.isNotEmpty ? _parseDurationText(lenText) : null,
              durationLabel: lenText,
              thumbnailUrl: thumb,
            ),
          );
        }
      }
      return;
    }

    for (final val in node.values) {
      _collectVideoRenderers(val, out, seenIds);
      if (out.length >= 25) return;
    }
  }

  /// Searches YouTube via Innertube JSON API (immune to HTML scraper breakage).
  static Future<List<NewTubeItem>> searchVideos(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final directId = extractVideoId(trimmed);
    if (directId != null) {
      final yt = YoutubeExplode();
      try {
        final v = await yt.videos.get(directId).timeout(const Duration(seconds: 12));
        return [
          NewTubeItem(
            videoId: v.id.value,
            title: v.title,
            author: v.author,
            duration: v.duration,
            thumbnailUrl: v.thumbnails.highResUrl.isNotEmpty
                ? v.thumbnails.highResUrl
                : 'https://i.ytimg.com/vi/$directId/hqdefault.jpg',
          ),
        ];
      } catch (_) {
        return [
          NewTubeItem(
            videoId: directId,
            title: 'YouTube Video ($directId)',
            author: 'YouTube',
            thumbnailUrl: 'https://i.ytimg.com/vi/$directId/hqdefault.jpg',
          ),
        ];
      } finally {
        yt.close();
      }
    }

    final response = await http
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
          headers: const {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': '2.20250101.00.00',
                'hl': 'id',
                'gl': 'ID',
              },
            },
            'query': trimmed,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('YouTube Search HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final List<NewTubeItem> items = [];
    _collectVideoRenderers(decoded, items, <String>{});
    return items;
  }

  static Future<bool> _probePlayableUrl(Uri uri) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      req.headers['Range'] = 'bytes=0-63';
      final res = await client.send(req).timeout(const Duration(seconds: 5));
      unawaited(res.stream.drain<void>().catchError((_) {}));
      return res.statusCode >= 200 && res.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static Future<String?> _resolvePlayableStream(
    String videoId, {
    required bool preferVideo,
  }) async {
    final yt = YoutubeExplode();
    try {
      final clients = [
        YoutubeApiClient.android,
        YoutubeApiClient.androidVr,
        YoutubeApiClient.ios,
        YoutubeApiClient.tv,
      ];

      for (final apiClient in clients) {
        try {
          final manifest = await yt.videos.streamsClient
              .getManifest(videoId, ytClients: [apiClient])
              .timeout(const Duration(seconds: 12));

          final List<Uri> candidates = [];
          if (preferVideo) {
            if (manifest.muxed.isNotEmpty) {
              candidates.add(manifest.muxed.withHighestBitrate().url);
            }
            if (manifest.hls.isNotEmpty) {
              candidates.add(manifest.hls.first.url);
            }
            if (manifest.audioOnly.isNotEmpty) {
              candidates.add(manifest.audioOnly.withHighestBitrate().url);
            }
          } else {
            if (manifest.audioOnly.isNotEmpty) {
              candidates.add(manifest.audioOnly.withHighestBitrate().url);
            }
            if (manifest.muxed.isNotEmpty) {
              candidates.add(manifest.muxed.withHighestBitrate().url);
            }
          }

          for (final url in candidates) {
            if (await _probePlayableUrl(url)) {
              return url.toString();
            }
          }
        } catch (_) {
          // Try next YoutubeApiClient
        }
      }
      return null;
    } finally {
      yt.close();
    }
  }

  static Future<String?> resolveAudioStreamUrl(String videoId) =>
      _resolvePlayableStream(videoId, preferVideo: false);

  static Future<String?> resolveVideoStreamUrl(String videoId) =>
      _resolvePlayableStream(videoId, preferVideo: true);
}
