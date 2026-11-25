import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/music_models.dart';

class NewTubeItem {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;

  const NewTubeItem({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
  });

  String get formattedDuration {
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
  static Future<List<NewTubeItem>> searchVideos(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final yt = YoutubeExplode();
    try {
      final results = await yt.search
          .search(trimmed)
          .timeout(const Duration(seconds: 15));
      return results
          .take(25)
          .map(
            (v) => NewTubeItem(
              videoId: v.id.value,
              title: v.title,
              author: v.author,
              duration: v.duration,
              thumbnailUrl: v.thumbnails.highResUrl.isNotEmpty
                  ? v.thumbnails.highResUrl
                  : v.thumbnails.mediumResUrl,
            ),
          )
          .toList();
    } finally {
      yt.close();
    }
  }

  static Future<String?> resolveAudioStreamUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 15));
      if (manifest.audioOnly.isNotEmpty) {
        return manifest.audioOnly.withHighestBitrate().url.toString();
      }
      if (manifest.muxed.isNotEmpty) {
        return manifest.muxed.withHighestBitrate().url.toString();
      }
      return null;
    } finally {
      yt.close();
    }
  }

  static Future<String?> resolveVideoStreamUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 15));
      if (manifest.muxed.isNotEmpty) {
        return manifest.muxed.withHighestBitrate().url.toString();
      }
      if (manifest.audioOnly.isNotEmpty) {
        return manifest.audioOnly.withHighestBitrate().url.toString();
      }
      return null;
    } finally {
      yt.close();
    }
  }
}
