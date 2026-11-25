import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../models/music_models.dart';

class DirectoryScanResult {
  final List<MusicDirectoryGroup> directories;
  final List<String> discoveredM3uFiles;

  const DirectoryScanResult({
    required this.directories,
    required this.discoveredM3uFiles,
  });
}

class DirectoryScannerService {
  static const MethodChannel _mediaStoreChannel =
      MethodChannel('com.musikm3u.player/media_store');

  static const Set<String> supportedAudioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.wav',
    '.aac',
    '.ogg',
    '.opus',
    '.wma',
    '.amr',
  };

  static const Set<String> m3uExtensions = {
    '.m3u',
    '.m3u8',
  };

  static const List<String> defaultAndroidMusicDirs = [
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Audio',
    '/storage/emulated/0/Podcasts',
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Lagu',
    '/storage/emulated/0/Musik',
  ];

  static bool isSystemTonePath(String filePath, Set<String> customRoots) {
    final normalized = p.normalize(filePath).replaceAll('\\', '/').toLowerCase();
    for (final root in customRoots) {
      final normRoot = p.normalize(root).replaceAll('\\', '/').toLowerCase();
      if (normalized == normRoot || normalized.startsWith('$normRoot/')) {
        return false; // Explicitly requested by user
      }
    }
    return normalized.contains('/ringtones/') ||
        normalized.contains('/notifications/') ||
        normalized.contains('/alarms/') ||
        normalized.endsWith('/ringtones') ||
        normalized.endsWith('/notifications') ||
        normalized.endsWith('/alarms');
  }

  /// Non-interactive check of current permission status (never pops system dialogs).
  static Future<bool> checkAudioAndDirectoryPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final audioStatus = await Permission.audio.status;
      if (audioStatus.isGranted || audioStatus.isLimited) return true;
      final manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) return true;
      final storageStatus = await Permission.storage.status;
      return storageStatus.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Interactive permission request across Android API levels.
  static Future<bool> requestAudioAndDirectoryPermission({
    bool requestAllFilesIfNeeded = false,
  }) async {
    if (!Platform.isAndroid) return true;

    final audioStatus = await Permission.audio.request();
    bool granted = audioStatus.isGranted || audioStatus.isLimited;

    if (!granted) {
      final storageStatus = await Permission.storage.request();
      granted = storageStatus.isGranted;
    }

    if (requestAllFilesIfNeeded) {
      final manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        final res = await Permission.manageExternalStorage.request();
        if (res.isGranted) granted = true;
      } else {
        granted = true;
      }
    } else {
      final manageGranted = await Permission.manageExternalStorage.isGranted;
      if (manageGranted) granted = true;
    }

    return granted;
  }

  /// Resolves an Android SAF `content://` URI or `file://` URI into an Android filesystem path when possible.
  static String? resolveAndroidSafUriToPath(Uri uri) {
    if (uri.scheme == 'file') {
      try {
        return uri.toFilePath(windows: Platform.isWindows);
      } catch (_) {
        return uri.path;
      }
    }
    if (uri.scheme == 'content') {
      final decoded = Uri.decodeFull(uri.toString());
      String? token;
      final docIdx = decoded.indexOf('/document/');
      final treeIdx = decoded.indexOf('/tree/');
      if (docIdx != -1) {
        token = decoded.substring(docIdx + 10);
      } else if (treeIdx != -1) {
        token = decoded.substring(treeIdx + 6);
      }
      if (token != null) {
        final queryIdx = token.indexOf('?');
        if (queryIdx != -1) token = token.substring(0, queryIdx);
        if (token.startsWith('primary:')) {
          final rel = token.substring('primary:'.length);
          return rel.isEmpty
              ? '/storage/emulated/0'
              : '/storage/emulated/0/$rel';
        }
        if (token.startsWith('home:')) {
          final rel = token.substring('home:'.length);
          return rel.isEmpty
              ? '/storage/emulated/0/Documents'
              : '/storage/emulated/0/Documents/$rel';
        }
        if (token.startsWith('raw:')) {
          return token.substring('raw:'.length);
        }
        final colonIdx = token.indexOf(':');
        if (colonIdx > 0 && !token.startsWith('msf:')) {
          final volumeId = token.substring(0, colonIdx);
          final rel = token.substring(colonIdx + 1);
          return rel.isEmpty ? '/storage/$volumeId' : '/storage/$volumeId/$rel';
        }
      }
    }
    return null;
  }

  /// Queries Android's MediaStore via native platform channel (works on Android 11–15+ with READ_MEDIA_AUDIO).
  static Future<List<TrackItem>> _queryNativeMediaStore(
    Set<String> customSet,
  ) async {
    if (!Platform.isAndroid) return const [];
    try {
      final rawList = await _mediaStoreChannel
          .invokeListMethod<Map<dynamic, dynamic>>('queryAllAudio')
          .timeout(const Duration(seconds: 12));
      if (rawList == null || rawList.isEmpty) return const [];

      final List<TrackItem> results = [];
      for (final row in rawList) {
        final rawPath = row['path'] as String?;
        if (rawPath == null || rawPath.isEmpty) continue;
        final filePath = p.normalize(rawPath);

        if (isSystemTonePath(filePath, customSet)) continue;

        final ext = p.extension(filePath).toLowerCase();
        if (!supportedAudioExtensions.contains(ext)) continue;

        final parentDir = p.dirname(filePath);
        final folderName = p.basename(parentDir);
        final parsedFallback = _parseFilenameMetadata(filePath, folderName);

        final rawTitle = (row['title'] as String?)?.trim();
        final rawArtist = (row['artist'] as String?)?.trim();
        final rawAlbum = (row['album'] as String?)?.trim();
        final durationSec = (row['durationSec'] as num?)?.toInt();

        results.add(
          TrackItem(
            id: TrackItem.generateId(filePath),
            title: (rawTitle != null && rawTitle.isNotEmpty)
                ? rawTitle
                : parsedFallback.title,
            artist: (rawArtist != null && rawArtist.isNotEmpty)
                ? rawArtist
                : parsedFallback.artist,
            album: (rawAlbum != null && rawAlbum.isNotEmpty)
                ? rawAlbum
                : (folderName.isEmpty ? 'Local Folder' : folderName),
            sourceType: TrackSourceType.localFile,
            pathOrUrl: filePath,
            localFileAvailable: true,
            directoryPath: parentDir,
            directoryName: folderName.isEmpty ? 'Musik' : folderName,
            durationSeconds: durationSec,
          ),
        );
      }
      return results;
    } catch (_) {
      // Safe fallback in unit tests or if channel is unavailable
      return const [];
    }
  }

  /// Scans Android MediaStore + default/user-selected directories and groups audio files by their folder.
  static Future<DirectoryScanResult> scanDirectories({
    required List<String> customDirectories,
    bool includeDefaultAndroidDirs = true,
  }) async {
    final Set<String> rootCandidates = {};
    final Set<String> customSet =
        customDirectories.map((d) => p.normalize(d)).toSet();

    if (includeDefaultAndroidDirs && Platform.isAndroid) {
      rootCandidates.addAll(defaultAndroidMusicDirs.map(p.normalize));
      try {
        final storageRoot = Directory('/storage');
        if (await storageRoot.exists()) {
          await for (final entity
              in storageRoot.list(followLinks: false).handleError((_) {})) {
            if (entity is Directory) {
              final name = p.basename(entity.path);
              if (name != 'emulated' && name != 'self') {
                rootCandidates.add(p.join(entity.path, 'Music'));
                rootCandidates.add(p.join(entity.path, 'Download'));
              }
            }
          }
        }
      } catch (_) {}
    }

    rootCandidates.addAll(customSet);

    final Map<String, List<TrackItem>> groupedTracks = {};
    final Set<String> seenFilePaths = {};
    final Set<String> discoveredM3u = {};

    // 1. Query Android MediaStore first (discovers ALL music across ALL directories even without All-Files access)
    final mediaStoreTracks = await _queryNativeMediaStore(customSet);
    for (final track in mediaStoreTracks) {
      if (seenFilePaths.add(track.pathOrUrl)) {
        groupedTracks.putIfAbsent(track.directoryPath, () => []).add(track);
      }
    }

    // 2. Walk directories via dart:io (discovers .m3u/.m3u8 files + unindexed custom folders)
    for (final rootPath in rootCandidates) {
      final dir = Directory(rootPath);
      bool exists = false;
      try {
        exists = await dir.exists();
      } catch (_) {
        exists = false;
      }
      if (!exists) continue;

      await _walkDirectorySafely(
        dir: dir,
        depth: 0,
        maxDepth: 6,
        customSet: customSet,
        seenFilePaths: seenFilePaths,
        groupedTracks: groupedTracks,
        discoveredM3u: discoveredM3u,
      );
    }

    final List<MusicDirectoryGroup> groups = [];
    final sortedKeys = groupedTracks.keys.toList()
      ..sort((a, b) =>
          p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));

    for (final dirPath in sortedKeys) {
      final tracks = groupedTracks[dirPath]!;
      if (tracks.isEmpty) continue;
      tracks.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      final dirName = p.basename(dirPath);
      groups.add(
        MusicDirectoryGroup(
          directoryPath: dirPath,
          directoryName: dirName.isEmpty ? dirPath : dirName,
          parentPath: p.dirname(dirPath),
          tracks: tracks,
          isCustomRoot: customSet.any(
            (custom) => dirPath == custom || p.isWithin(custom, dirPath),
          ),
        ),
      );
    }

    final sortedM3u = discoveredM3u.toList()..sort();
    return DirectoryScanResult(
      directories: groups,
      discoveredM3uFiles: sortedM3u,
    );
  }

  static Future<void> _walkDirectorySafely({
    required Directory dir,
    required int depth,
    required int maxDepth,
    required Set<String> customSet,
    required Set<String> seenFilePaths,
    required Map<String, List<TrackItem>> groupedTracks,
    required Set<String> discoveredM3u,
  }) async {
    if (depth > maxDepth) return;

    final baseName = p.basename(dir.path);
    if (baseName.startsWith('.') && depth > 0) return;
    final normalizedDir = p.normalize(dir.path).replaceAll('\\', '/');
    if (normalizedDir.contains('/Android/data') ||
        normalizedDir.contains('/Android/obb')) {
      return;
    }
    if (isSystemTonePath(normalizedDir, customSet)) {
      return;
    }

    try {
      await for (final entity
          in dir.list(recursive: false, followLinks: false).handleError((_) {})) {
        if (entity is File) {
          final filePath = p.normalize(entity.path);
          final ext = p.extension(filePath).toLowerCase();

          if (m3uExtensions.contains(ext)) {
            discoveredM3u.add(filePath);
            continue;
          }

          if (!supportedAudioExtensions.contains(ext)) continue;
          if (isSystemTonePath(filePath, customSet)) continue;
          if (!seenFilePaths.add(filePath)) continue;

          final parentDir = p.dirname(filePath);
          final folderName = p.basename(parentDir);
          final parsed = _parseFilenameMetadata(filePath, folderName);

          final track = TrackItem(
            id: TrackItem.generateId(filePath),
            title: parsed.title,
            artist: parsed.artist,
            album: folderName.isEmpty ? 'Local Folder' : folderName,
            sourceType: TrackSourceType.localFile,
            pathOrUrl: filePath,
            localFileAvailable: true,
            directoryPath: parentDir,
            directoryName: folderName.isEmpty ? 'Musik' : folderName,
          );

          groupedTracks.putIfAbsent(parentDir, () => []).add(track);
        } else if (entity is Directory) {
          await _walkDirectorySafely(
            dir: entity,
            depth: depth + 1,
            maxDepth: maxDepth,
            customSet: customSet,
            seenFilePaths: seenFilePaths,
            groupedTracks: groupedTracks,
            discoveredM3u: discoveredM3u,
          );
        }
      }
    } catch (_) {
      // Gracefully skip restricted directories on Android scoped storage
    }
  }

  static ({String artist, String title}) _parseFilenameMetadata(
    String filePath,
    String folderName,
  ) {
    final rawName = p
        .basenameWithoutExtension(filePath)
        .replaceAll('_', ' ')
        .replaceFirst(RegExp(r'^\d{1,3}[\s._-]+'), '')
        .trim();

    final sep = rawName.indexOf(' - ');
    if (sep > 0 && sep + 3 < rawName.length) {
      return (
        artist: rawName.substring(0, sep).trim(),
        title: rawName.substring(sep + 3).trim(),
      );
    }
    return (
      artist: folderName.isNotEmpty ? folderName : 'Offline Lokal',
      title: rawName.isNotEmpty ? rawName : p.basename(filePath),
    );
  }
}
