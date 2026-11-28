import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum TrackSourceType {
  localFile,
  remoteStream,
}

enum M3uSourceType {
  file,
  url,
}

class TrackItem {
  static const Set<String> _pureAudioExtensions = {
    '.mp3',
    '.flac',
    '.wav',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.wma',
    '.amr',
  };

  static const Set<String> _videoAndHlsExtensions = {
    '.m3u8',
    '.mp4',
    '.mkv',
    '.ts',
    '.webm',
    '.avi',
    '.mov',
    '.flv',
    '.m4v',
    '.3gp',
    '.mpd',
  };

  static final RegExp _videoTitleHintRegex = RegExp(
    r'\b(2160p|1080p|720p|480p|360p|4k|uhd|fhd|iptv|tv)\b|\((hd|sd|fhd)\)',
    caseSensitive: false,
  );

  final String id;
  final String title;
  final String artist;
  final String album;
  final String? groupTitle;
  final TrackSourceType sourceType;
  final String pathOrUrl;
  final String? offlineCachePath;
  final bool localFileAvailable;
  final String directoryPath;
  final String directoryName;
  final String? playlistId;
  final int? durationSeconds;
  final String? artworkUrl;
  final bool isVideo;
  final Map<String, String>? httpHeaders;

  const TrackItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.groupTitle,
    required this.sourceType,
    required this.pathOrUrl,
    this.offlineCachePath,
    this.localFileAvailable = true,
    required this.directoryPath,
    required this.directoryName,
    this.playlistId,
    this.durationSeconds,
    this.artworkUrl,
    this.isVideo = false,
    this.httpHeaders,
  });

  /// Detects whether an M3U or local entry is a Video / Live TV / HLS stream rather than pure audio.
  static bool detectIsVideo({
    required String pathOrUrl,
    required String title,
    bool hasIptvMetadata = false,
    bool hasVlcVideoOpts = false,
  }) {
    final cleanPath = pathOrUrl.split('?').first.split('#').first.toLowerCase();
    final ext = p.extension(cleanPath);
    if (_pureAudioExtensions.contains(ext)) {
      return false;
    }
    if (_videoAndHlsExtensions.contains(ext)) {
      return true;
    }
    if (cleanPath.contains('/live/') ||
        cleanPath.contains('.m3u8') ||
        cleanPath.contains('/hls/')) {
      return true;
    }
    if (hasIptvMetadata || hasVlcVideoOpts) {
      return true;
    }
    if (_videoTitleHintRegex.hasMatch(title)) {
      return true;
    }
    return false;
  }

  /// Deterministic compact 32-char SHA-256 hex ID (safe for filenames & SharedPreferences).
  static String generateId(String rawSource, {String? playlistId}) {
    final normalized = rawSource.trim().replaceAll('\\', '/');
    final prefix = playlistId != null ? '$playlistId::' : '';
    final digest = sha256.convert(utf8.encode('$prefix$normalized')).toString();
    return 'trk_${digest.substring(0, 32)}';
  }

  bool get isLocalFile => sourceType == TrackSourceType.localFile;

  /// Pure O(1) memory check (no synchronous disk I/O on UI build thread).
  bool get hasOfflineCache =>
      offlineCachePath != null && offlineCachePath!.isNotEmpty;

  /// Pure O(1) memory check (validated asynchronously during scan/import/download).
  bool get isOfflineReady =>
      isLocalFile ? localFileAvailable : hasOfflineCache;

  /// Prefer local offline cached file when available so M3U URL tracks also work offline.
  String get playableSource {
    if (!isLocalFile && hasOfflineCache) {
      return offlineCachePath!;
    }
    return pathOrUrl;
  }

  bool get playsFromLocalFile => isLocalFile || hasOfflineCache;

  bool get hasValidNetworkArtwork =>
      artworkUrl != null &&
      (artworkUrl!.startsWith('http://') || artworkUrl!.startsWith('https://'));

  bool get hasLocalArtwork =>
      artworkUrl != null &&
      artworkUrl!.isNotEmpty &&
      !hasValidNetworkArtwork &&
      File(artworkUrl!).existsSync();

  String get fileExtension {
    if (isVideo && !isLocalFile) {
      final ext = p.extension(pathOrUrl.split('?').first).toLowerCase();
      if (ext == '.mp4' || ext == '.mkv') {
        return ext.substring(1).toUpperCase();
      }
      return 'VIDEO';
    }
    final ext = p.extension(pathOrUrl.split('?').first).toLowerCase();
    return ext.startsWith('.') ? ext.substring(1).toUpperCase() : 'AUDIO';
  }

  TrackItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? groupTitle,
    TrackSourceType? sourceType,
    String? pathOrUrl,
    String? offlineCachePath,
    bool clearOfflineCache = false,
    bool? localFileAvailable,
    String? directoryPath,
    String? directoryName,
    String? playlistId,
    int? durationSeconds,
    String? artworkUrl,
    bool? isVideo,
    Map<String, String>? httpHeaders,
  }) {
    return TrackItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      groupTitle: groupTitle ?? this.groupTitle,
      sourceType: sourceType ?? this.sourceType,
      pathOrUrl: pathOrUrl ?? this.pathOrUrl,
      offlineCachePath:
          clearOfflineCache ? null : (offlineCachePath ?? this.offlineCachePath),
      localFileAvailable: localFileAvailable ?? this.localFileAvailable,
      directoryPath: directoryPath ?? this.directoryPath,
      directoryName: directoryName ?? this.directoryName,
      playlistId: playlistId ?? this.playlistId,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      isVideo: isVideo ?? this.isVideo,
      httpHeaders: httpHeaders ?? this.httpHeaders,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'groupTitle': groupTitle,
        'sourceType': sourceType.name,
        'pathOrUrl': pathOrUrl,
        'offlineCachePath': offlineCachePath,
        'localFileAvailable': localFileAvailable,
        'directoryPath': directoryPath,
        'directoryName': directoryName,
        'playlistId': playlistId,
        'durationSeconds': durationSeconds,
        'artworkUrl': artworkUrl,
        'isVideo': isVideo,
        if (httpHeaders != null && httpHeaders!.isNotEmpty)
          'httpHeaders': httpHeaders,
      };

  factory TrackItem.fromJson(Map<String, dynamic> json) {
    final sourceStr = json['sourceType'] as String? ?? 'localFile';
    final pathOrUrl = json['pathOrUrl'] as String? ?? '';
    final title = json['title'] as String? ?? 'Unknown Track';
    final rawDirName = json['directoryName'] as String? ?? 'Musik';
    final cleanDirName =
        (rawDirName.toLowerCase() == 'undefined' || rawDirName.toLowerCase() == 'null')
            ? 'Playlist M3U'
            : rawDirName;

    Map<String, String>? parsedHeaders;
    final rawHeaders = json['httpHeaders'];
    if (rawHeaders is Map) {
      parsedHeaders = rawHeaders.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    }

    final bool inferredVideo = json.containsKey('isVideo')
        ? (json['isVideo'] as bool? ?? false)
        : detectIsVideo(pathOrUrl: pathOrUrl, title: title);

    return TrackItem(
      id: json['id'] as String? ?? '',
      title: title,
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? 'Local Audio',
      groupTitle: _sanitizeGroup(json['groupTitle'] as String?),
      sourceType: sourceStr == 'remoteStream'
          ? TrackSourceType.remoteStream
          : TrackSourceType.localFile,
      pathOrUrl: pathOrUrl,
      offlineCachePath: json['offlineCachePath'] as String?,
      localFileAvailable: json['localFileAvailable'] as bool? ?? true,
      directoryPath: json['directoryPath'] as String? ?? '',
      directoryName: cleanDirName,
      playlistId: json['playlistId'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      artworkUrl: json['artworkUrl'] as String?,
      isVideo: inferredVideo,
      httpHeaders: parsedHeaders,
    );
  }

  static String? _sanitizeGroup(String? g) {
    if (g == null) return null;
    final trimmed = g.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == 'undefined' ||
        trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }
}

class MusicDirectoryGroup {
  final String directoryPath;
  final String directoryName;
  final String parentPath;
  final List<TrackItem> tracks;
  final bool isCustomRoot;

  const MusicDirectoryGroup({
    required this.directoryPath,
    required this.directoryName,
    required this.parentPath,
    required this.tracks,
    this.isCustomRoot = false,
  });

  int get trackCount => tracks.length;
}

class M3uPlaylist {
  static const List<String> defaultCategories = [
    'Umum',
    'Favorit',
    'TV & CCTV',
    'Radio',
    'Musik',
  ];

  final String id;
  final String name;
  final String category;
  final M3uSourceType sourceType;
  final String sourceLocation;
  final String? cachedM3uPath;
  final List<TrackItem> tracks;
  final DateTime updatedAt;
  final bool isEnabled;
  final int offlineTrackCount;

  M3uPlaylist({
    required this.id,
    required this.name,
    this.category = 'Umum',
    required this.sourceType,
    required this.sourceLocation,
    this.cachedM3uPath,
    required this.tracks,
    required this.updatedAt,
    this.isEnabled = true,
    int? offlineTrackCount,
  }) : offlineTrackCount =
            offlineTrackCount ?? tracks.where((t) => t.isOfflineReady).length;

  bool get isUrlSource => sourceType == M3uSourceType.url;

  int get videoTrackCount => tracks.where((t) => t.isVideo).length;

  M3uPlaylist copyWith({
    String? id,
    String? name,
    String? category,
    M3uSourceType? sourceType,
    String? sourceLocation,
    String? cachedM3uPath,
    List<TrackItem>? tracks,
    DateTime? updatedAt,
    bool? isEnabled,
  }) {
    final nextTracks = tracks ?? this.tracks;
    return M3uPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      sourceType: sourceType ?? this.sourceType,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      cachedM3uPath: cachedM3uPath ?? this.cachedM3uPath,
      tracks: nextTracks,
      updatedAt: updatedAt ?? this.updatedAt,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'sourceType': sourceType.name,
        'sourceLocation': sourceLocation,
        'cachedM3uPath': cachedM3uPath,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        'isEnabled': isEnabled,
      };

  factory M3uPlaylist.fromJson(Map<String, dynamic> json) {
    final typeStr = json['sourceType'] as String? ?? 'file';
    final rawTracks = json['tracks'] as List<dynamic>? ?? const [];
    final rawCategory = (json['category'] as String? ?? '').trim();
    return M3uPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'M3U Playlist',
      category: rawCategory.isNotEmpty ? rawCategory : 'Umum',
      sourceType:
          typeStr == 'url' ? M3uSourceType.url : M3uSourceType.file,
      sourceLocation: json['sourceLocation'] as String? ?? '',
      cachedM3uPath: json['cachedM3uPath'] as String?,
      tracks: rawTracks
          .whereType<Map<String, dynamic>>()
          .map(TrackItem.fromJson)
          .toList(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }
}
