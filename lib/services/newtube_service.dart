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
    Map<String, String>? httpHeaders,
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
      httpHeaders: httpHeaders,
    );
  }
}

class NewTubePlaylistItem {
  final String playlistId;
  final String title;
  final String author;
  final String videoCountText;
  final String thumbnailUrl;

  const NewTubePlaylistItem({
    required this.playlistId,
    required this.title,
    required this.author,
    required this.videoCountText,
    required this.thumbnailUrl,
  });
}

class NewTubeResolvedStream {
  final String url;
  final Map<String, String> headers;

  const NewTubeResolvedStream({
    required this.url,
    required this.headers,
  });
}

class NewTubeService {
  static final RegExp _videoIdRegex = RegExp(
    r'(?:v=|youtu\.be/|shorts/|embed/|live/)([a-zA-Z0-9_-]{11})',
  );

  static const Map<String, String> _webHeaders = {
    'Content-Type': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  static const Map<String, dynamic> _webClientContext = {
    'client': {
      'clientName': 'WEB',
      'clientVersion': '2.20250101.00.00',
      'hl': 'id',
      'gl': 'ID',
    },
  };

  /// Extracts an 11-character YouTube video ID from a URL or raw ID string.
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return _videoIdRegex.firstMatch(trimmed)?.group(1);
  }

  static Duration? _parseDurationText(String text) {
    final normalized = text.trim().replaceAll('.', ':');
    final parts = normalized
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
    Set<String> seenIds, {
    int maxItems = 25,
    String rendererKey = 'videoRenderer',
  }) {
    if (out.length >= maxItems) return;
    if (node is List) {
      for (final item in node) {
        _collectVideoRenderers(
          item,
          out,
          seenIds,
          maxItems: maxItems,
          rendererKey: rendererKey,
        );
        if (out.length >= maxItems) return;
      }
      return;
    }
    if (node is! Map) return;

    final vr = node[rendererKey];
    if (vr is Map) {
      final videoId = vr['videoId']?.toString() ?? '';
      if (videoId.length == 11 && seenIds.add(videoId)) {
        final title = _readRunsText(vr['title']);
        final author = _readRunsText(vr['ownerText']).isNotEmpty
            ? _readRunsText(vr['ownerText'])
            : (_readRunsText(vr['shortBylineText']).isNotEmpty
                ? _readRunsText(vr['shortBylineText'])
                : _readRunsText(vr['longBylineText']));
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
      _collectVideoRenderers(
        val,
        out,
        seenIds,
        maxItems: maxItems,
        rendererKey: rendererKey,
      );
      if (out.length >= maxItems) return;
    }
  }

  static void _collectPlaylistRenderers(
    dynamic node,
    List<NewTubePlaylistItem> out,
    Set<String> seenIds, {
    int maxItems = 15,
  }) {
    if (out.length >= maxItems) return;
    if (node is List) {
      for (final item in node) {
        _collectPlaylistRenderers(item, out, seenIds, maxItems: maxItems);
        if (out.length >= maxItems) return;
      }
      return;
    }
    if (node is! Map) return;

    // 1. Modern YouTube lockupViewModel
    final lockup = node['lockupViewModel'];
    if (lockup is Map) {
      final playlistId = lockup['contentId']?.toString() ?? '';
      final contentType = lockup['contentType']?.toString() ?? '';
      if (playlistId.length >= 10 &&
          (contentType.contains('PLAYLIST') ||
              playlistId.startsWith('PL') ||
              playlistId.startsWith('OLAK')) &&
          seenIds.add(playlistId)) {
        final meta = lockup['metadata']?['lockupMetadataViewModel'];
        final title = meta?['title']?['content']?.toString() ?? '';
        String author = 'YouTube Playlist';
        final rows = meta?['metadata']?['contentMetadataViewModel']?['metadataRows'];
        if (rows is List && rows.isNotEmpty) {
          final firstParts = rows.first?['metadataParts'];
          if (firstParts is List && firstParts.isNotEmpty) {
            final text = firstParts.first?['text']?['content']?.toString() ?? '';
            if (text.isNotEmpty) author = text;
          }
        }

        String countText = 'Playlist';
        String thumb = '';
        final cThumb = lockup['contentImage']?['collectionThumbnailViewModel']
            ?['primaryThumbnail']?['thumbnailViewModel'];
        if (cThumb is Map) {
          final sources = cThumb['image']?['sources'];
          if (sources is List && sources.isNotEmpty) {
            final last = sources.last;
            if (last is Map && last['url'] is String) {
              thumb = last['url'] as String;
            }
          }
          final overlays = cThumb['overlays'];
          if (overlays is List) {
            for (final ov in overlays) {
              final badges = ov?['thumbnailOverlayBadgeViewModel']?['thumbnailBadges'];
              if (badges is List && badges.isNotEmpty) {
                final badgeText =
                    badges.first?['thumbnailBadgeViewModel']?['text']?.toString() ?? '';
                if (badgeText.isNotEmpty) {
                  countText = badgeText;
                  break;
                }
              }
            }
          }
        }

        if (title.isNotEmpty) {
          out.add(
            NewTubePlaylistItem(
              playlistId: playlistId,
              title: title,
              author: author,
              videoCountText: countText,
              thumbnailUrl: thumb,
            ),
          );
        }
      }
      return;
    }

    // 2. Legacy playlistRenderer fallback
    final pr = node['playlistRenderer'];
    if (pr is Map) {
      final playlistId = pr['playlistId']?.toString() ?? '';
      if (playlistId.length >= 10 && seenIds.add(playlistId)) {
        final title = _readRunsText(pr['title']);
        final author = _readRunsText(pr['shortBylineText']);
        final count = pr['videoCount']?.toString() ?? '';
        String thumb = '';
        final thumbs = pr['thumbnails'];
        if (thumbs is List && thumbs.isNotEmpty) {
          final list = thumbs.first?['thumbnails'];
          if (list is List && list.isNotEmpty) {
            thumb = list.last?['url']?.toString() ?? '';
          }
        }
        if (title.isNotEmpty) {
          out.add(
            NewTubePlaylistItem(
              playlistId: playlistId,
              title: title,
              author: author.isEmpty ? 'YouTube Playlist' : author,
              videoCountText: count.isEmpty ? 'Playlist' : '$count video',
              thumbnailUrl: thumb,
            ),
          );
        }
      }
      return;
    }

    for (final val in node.values) {
      _collectPlaylistRenderers(val, out, seenIds, maxItems: maxItems);
      if (out.length >= maxItems) return;
    }
  }

  /// Searches YouTube videos via Innertube JSON API.
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
          headers: _webHeaders,
          body: jsonEncode({
            'context': _webClientContext,
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

  /// Searches YouTube playlists matching [query] (using Innertube Playlist filter).
  static Future<List<NewTubePlaylistItem>> searchPlaylists(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || extractVideoId(trimmed) != null) return const [];

    try {
      final response = await http
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
            headers: _webHeaders,
            body: jsonEncode({
              'context': _webClientContext,
              'query': trimmed,
              'params': 'EgIQAw==',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }

      final decoded = jsonDecode(response.body);
      final List<NewTubePlaylistItem> playlists = [];
      _collectPlaylistRenderers(decoded, playlists, <String>{});
      return playlists;
    } catch (_) {
      return const [];
    }
  }

  /// Fetches tracks inside a YouTube playlist via Innertube browse (`VL<id>`).
  static Future<List<NewTubeItem>> fetchPlaylistVideos(String playlistId) async {
    if (playlistId.trim().isEmpty) return const [];
    final browseId = playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';

    final response = await http
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'),
          headers: _webHeaders,
          body: jsonEncode({
            'context': _webClientContext,
            'browseId': browseId,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Playlist Browse HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final List<NewTubeItem> items = [];
    final Set<String> seenIds = <String>{};
    _collectPlaylistLockupVideos(decoded, items, seenIds, maxItems: 50);
    if (items.isEmpty) {
      _collectVideoRenderers(
        decoded,
        items,
        seenIds,
        maxItems: 50,
        rendererKey: 'playlistVideoRenderer',
      );
    }
    if (items.isEmpty) {
      _collectVideoRenderers(
        decoded,
        items,
        seenIds,
        maxItems: 50,
        rendererKey: 'playlistPanelVideoRenderer',
      );
    }
    if (items.isEmpty) {
      _collectVideoRenderers(
        decoded,
        items,
        seenIds,
        maxItems: 50,
        rendererKey: 'videoRenderer',
      );
    }
    return items;
  }

  static void _collectPlaylistLockupVideos(
    dynamic node,
    List<NewTubeItem> out,
    Set<String> seenIds, {
    int maxItems = 50,
  }) {
    if (out.length >= maxItems) return;
    if (node is List) {
      for (final item in node) {
        _collectPlaylistLockupVideos(item, out, seenIds, maxItems: maxItems);
        if (out.length >= maxItems) return;
      }
      return;
    }
    if (node is! Map) return;

    final lockup = node['lockupViewModel'];
    if (lockup is Map) {
      final videoId = lockup['contentId']?.toString() ?? '';
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId) &&
          seenIds.add(videoId)) {
        final meta = lockup['metadata']?['lockupMetadataViewModel'];
        final title = meta?['title']?['content']?.toString() ?? '';
        String author = 'YouTube';
        final rows = meta?['metadata']?['contentMetadataViewModel']?['metadataRows'];
        if (rows is List && rows.isNotEmpty) {
          final firstParts = rows.first?['metadataParts'];
          if (firstParts is List && firstParts.isNotEmpty) {
            final text = firstParts.first?['text']?['content']?.toString() ?? '';
            if (text.isNotEmpty) author = text;
          }
        }

        String thumb = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        String lenText = '';
        final tv = lockup['contentImage']?['thumbnailViewModel'];
        if (tv is Map) {
          final sources = tv['image']?['sources'];
          if (sources is List && sources.isNotEmpty) {
            final last = sources.last;
            if (last is Map && last['url'] is String) {
              thumb = last['url'] as String;
            }
          }
          final overlays = tv['overlays'];
          if (overlays is List) {
            for (final ov in overlays) {
              final badges =
                  ov?['thumbnailBottomOverlayViewModel']?['badges'];
              if (badges is List && badges.isNotEmpty) {
                final text =
                    badges.first?['thumbnailBadgeViewModel']?['text']?.toString() ??
                        '';
                if (text.isNotEmpty) {
                  lenText = text;
                  break;
                }
              }
            }
          }
        }

        if (title.isNotEmpty) {
          out.add(
            NewTubeItem(
              videoId: videoId,
              title: title,
              author: author,
              duration: lenText.isNotEmpty ? _parseDurationText(lenText) : null,
              durationLabel: lenText.replaceAll('.', ':'),
              thumbnailUrl: thumb,
            ),
          );
        }
      }
      return;
    }

    for (final val in node.values) {
      _collectPlaylistLockupVideos(val, out, seenIds, maxItems: maxItems);
      if (out.length >= maxItems) return;
    }
  }

  static Map<String, String> _headersForClient(YoutubeApiClient client) {
    final ua = client.headers['User-Agent']?.toString();
    if (ua != null && ua.isNotEmpty) {
      return {'User-Agent': ua};
    }
    final clientName =
        client.payload['context']?['client']?['clientName']?.toString() ?? '';
    if (clientName == 'IOS') {
      return const {
        'User-Agent':
            'com.google.ios.youtube/19.09.3 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)',
      };
    }
    return const {
      'User-Agent':
          'com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip',
    };
  }

  static Future<bool> _probePlayableUrl(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      req.headers.addAll(headers);
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

  static Future<NewTubeResolvedStream?> _resolvePlayableStream(
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

          final headers = _headersForClient(apiClient);
          final List<Uri> candidates = [];

          // Progressive muxed MP4 (e.g. itag 18) is the most reliable across
          // both ExoPlayer Audio (just_audio) and VideoPlayer on Android.
          if (manifest.muxed.isNotEmpty) {
            candidates.add(manifest.muxed.withHighestBitrate().url);
          }

          if (preferVideo) {
            if (manifest.hls.isNotEmpty) {
              candidates.add(manifest.hls.first.url);
            }
          }

          final mp4Audio = manifest.audioOnly
              .where((s) => s.container.name.toLowerCase() == 'mp4')
              .toList()
            ..sort((a, b) =>
                b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
          for (final s in mp4Audio) {
            candidates.add(s.url);
          }
          if (manifest.audioOnly.isNotEmpty) {
            candidates.add(manifest.audioOnly.withHighestBitrate().url);
          }

          for (final url in candidates) {
            if (await _probePlayableUrl(url, headers)) {
              return NewTubeResolvedStream(url: url.toString(), headers: headers);
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

  static Future<NewTubeResolvedStream?> resolveAudioStream(String videoId) =>
      _resolvePlayableStream(videoId, preferVideo: false);

  static Future<NewTubeResolvedStream?> resolveVideoStream(String videoId) =>
      _resolvePlayableStream(videoId, preferVideo: true);

  static Future<String?> resolveAudioStreamUrl(String videoId) async =>
      (await resolveAudioStream(videoId))?.url;

  static Future<String?> resolveVideoStreamUrl(String videoId) async =>
      (await resolveVideoStream(videoId))?.url;
}
