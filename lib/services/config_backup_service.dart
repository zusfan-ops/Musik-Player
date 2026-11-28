import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/music_models.dart';
import 'newtube_service.dart';

class BackupPreview {
  final int schemaVersion;
  final DateTime? exportedAt;
  final int urlPlaylistCount;
  final int localPlaylistCount;
  final int favoriteCount;
  final int youtubePlaylistCount;
  final int settingsCount;
  final List<M3uPlaylist> playlists;
  final List<String> favoriteIds;
  final List<NewTubePlaylistItem> youtubePlaylists;
  final Map<String, dynamic> settings;

  const BackupPreview({
    required this.schemaVersion,
    required this.exportedAt,
    required this.urlPlaylistCount,
    required this.localPlaylistCount,
    required this.favoriteCount,
    required this.youtubePlaylistCount,
    required this.settingsCount,
    required this.playlists,
    required this.favoriteIds,
    required this.youtubePlaylists,
    required this.settings,
  });
}

/// Portable JSON backup & restore service (no account required).
/// Strips raw private local device paths when exporting local playlists.
class ConfigBackupService {
  static const int currentSchemaVersion = 1;

  static String buildBackupJson({
    required List<M3uPlaylist> playlists,
    required Set<String> favoriteIds,
    required List<NewTubePlaylistItem> youtubePlaylists,
    required Map<String, dynamic> settings,
  }) {
    final sanitizedPlaylists = playlists.map((pl) {
      if (pl.isUrlSource) {
        final cleanTracks = pl.tracks.map((t) {
          final tj = t.toJson();
          tj['offlineCachePath'] = null;
          tj['directoryPath'] = '';
          final art = tj['artworkUrl']?.toString() ?? '';
          if (art.isNotEmpty &&
              !art.startsWith('http://') &&
              !art.startsWith('https://')) {
            tj['artworkUrl'] = null;
          }
          return tj;
        }).toList();
        return {
          'id': pl.id,
          'name': pl.name,
          'category': pl.category,
          'sourceType': pl.sourceType.name,
          'sourceLocation': pl.sourceLocation,
          'cachedM3uPath': null,
          'tracks': cleanTracks,
          'updatedAt': pl.updatedAt.toIso8601String(),
          'isEnabled': pl.isEnabled,
        };
      }
      // Strip private raw local file paths while keeping portable metadata
      return {
        'id': pl.id,
        'name': pl.name,
        'category': pl.category,
        'sourceType': pl.sourceType.name,
        'sourceLocation': p.basename(pl.sourceLocation),
        'cachedM3uPath': null,
        'tracks': const <Map<String, dynamic>>[],
        'updatedAt': pl.updatedAt.toIso8601String(),
        'isEnabled': pl.isEnabled,
      };
    }).toList();

    final payload = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'playlists': sanitizedPlaylists,
      'favoriteIds': favoriteIds.toList(),
      'youtubePlaylists': youtubePlaylists
          .map(
            (yt) => {
              'playlistId': yt.playlistId,
              'title': yt.title,
              'author': yt.author,
              'videoCountText': yt.videoCountText,
              'thumbnailUrl': yt.thumbnailUrl,
            },
          )
          .toList(),
      'settings': settings,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static BackupPreview parseAndPreview(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Format file backup tidak valid.');
    }
    final schemaVersion = (decoded['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Versi skema backup ($schemaVersion) tidak didukung.',
      );
    }

    final exportedAt = DateTime.tryParse(
      decoded['exportedAt']?.toString() ?? '',
    );

    final rawPlaylists = decoded['playlists'];
    final playlists = <M3uPlaylist>[];
    if (rawPlaylists is List) {
      for (final item in rawPlaylists) {
        if (item is Map<String, dynamic>) {
          playlists.add(M3uPlaylist.fromJson(item));
        }
      }
    }

    final rawFavs = decoded['favoriteIds'];
    final favoriteIds = rawFavs is List
        ? rawFavs.whereType<String>().where((s) => s.isNotEmpty).toList()
        : <String>[];

    final rawYt = decoded['youtubePlaylists'];
    final youtubePlaylists = <NewTubePlaylistItem>[];
    if (rawYt is List) {
      for (final item in rawYt) {
        if (item is! Map<String, dynamic>) continue;
        final pid = item['playlistId']?.toString() ?? '';
        if (pid.isEmpty) continue;
        youtubePlaylists.add(
          NewTubePlaylistItem(
            playlistId: pid,
            title: item['title']?.toString() ?? 'YouTube Playlist',
            author: item['author']?.toString() ?? 'YouTube',
            videoCountText: item['videoCountText']?.toString() ?? '',
            thumbnailUrl: item['thumbnailUrl']?.toString() ?? '',
          ),
        );
      }
    }

    final rawSettings = decoded['settings'];
    final settings = rawSettings is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawSettings)
        : <String, dynamic>{};

    final urlCount = playlists.where((p) => p.isUrlSource).length;
    final localCount = playlists.length - urlCount;

    return BackupPreview(
      schemaVersion: schemaVersion,
      exportedAt: exportedAt,
      urlPlaylistCount: urlCount,
      localPlaylistCount: localCount,
      favoriteCount: favoriteIds.length,
      youtubePlaylistCount: youtubePlaylists.length,
      settingsCount: settings.length,
      playlists: playlists,
      favoriteIds: favoriteIds,
      youtubePlaylists: youtubePlaylists,
      settings: settings,
    );
  }
}
