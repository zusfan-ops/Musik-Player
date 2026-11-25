import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/music_models.dart';

class LinkCheckResult {
  final int totalChecked;
  final int onlineCount;
  final Set<String> deadTrackIds;

  const LinkCheckResult({
    required this.totalChecked,
    required this.onlineCount,
    required this.deadTrackIds,
  });

  int get deadCount => deadTrackIds.length;
}

class LinkCheckerService {
  static Future<bool> isStreamUrlAlive(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 5),
    http.Client? client,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    final ownClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      try {
        final headRes = await httpClient.head(uri, headers: headers).timeout(timeout);
        if (headRes.statusCode >= 200 && headRes.statusCode < 400) {
          return true;
        }
        // Some IPTV servers reject HEAD (403/405/501) while GET stream works
        if (headRes.statusCode != 403 &&
            headRes.statusCode != 405 &&
            headRes.statusCode != 501) {
          return false;
        }
      } catch (_) {
        // Fall through to lightweight ranged GET probe
      }

      final req = http.Request('GET', uri);
      req.headers.addAll(headers);
      req.headers['Range'] = 'bytes=0-511';
      final streamed = await httpClient.send(req).timeout(timeout);
      // Close stream immediately without downloading full media
      unawaited(streamed.stream.drain<void>().catchError((_) {}));
      return streamed.statusCode >= 200 && streamed.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      if (ownClient) {
        httpClient.close();
      }
    }
  }

  static Future<LinkCheckResult> checkTracks(
    List<TrackItem> tracks, {
    void Function(int checked, int total)? onProgress,
    int concurrency = 6,
  }) async {
    final remoteTracks = tracks.where((t) => !t.isLocalFile).toList();
    if (remoteTracks.isEmpty) {
      return const LinkCheckResult(
        totalChecked: 0,
        onlineCount: 0,
        deadTrackIds: {},
      );
    }

    final Set<String> deadIds = {};
    int online = 0;
    int checked = 0;
    final client = http.Client();

    try {
      for (int i = 0; i < remoteTracks.length; i += concurrency) {
        final end = (i + concurrency < remoteTracks.length)
            ? i + concurrency
            : remoteTracks.length;
        final batch = remoteTracks.sublist(i, end);

        await Future.wait(
          batch.map((track) async {
            final alive = await isStreamUrlAlive(
              track.pathOrUrl,
              headers: track.httpHeaders ?? const {},
              client: client,
            );
            if (alive) {
              online++;
            } else {
              deadIds.add(track.id);
            }
            checked++;
            onProgress?.call(checked, remoteTracks.length);
          }),
        );
      }
    } finally {
      client.close();
    }

    return LinkCheckResult(
      totalChecked: remoteTracks.length,
      onlineCount: online,
      deadTrackIds: deadIds,
    );
  }
}
