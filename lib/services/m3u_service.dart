import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/music_models.dart';

class ParsedM3uResult {
  final String? embeddedTitle;
  final List<TrackItem> tracks;

  const ParsedM3uResult({
    this.embeddedTitle,
    required this.tracks,
  });
}

class M3uService {
  static const Duration _httpTimeout = Duration(seconds: 25);
  static const Duration _chunkIdleTimeout = Duration(seconds: 25);
  static const Duration _maxDownloadWallTime = Duration(minutes: 3);
  static const int maxOfflineTrackBytes = 150 * 1024 * 1024; // 150 MB safety cap

  static final RegExp _extInfRegex = RegExp(
    r'^#EXTINF:\s*(-?\d+(?:\.\d+)?)([^,]*),(.*)$',
    caseSensitive: false,
  );

  static final RegExp _attrRegex = RegExp(
    r'([a-zA-Z0-9_-]+)\s*=\s*"([^"]*)"',
  );

  /// Generates a short, filesystem-safe filename stem (< 48 chars) to prevent `ENAMETOOLONG`.
  static String safeCacheFileStem(String rawKey, {String prefix = 'm3u'}) {
    final digest = sha256.convert(utf8.encode(rawKey)).toString();
    return '${prefix}_${digest.substring(0, 32)}';
  }

  /// Validates that an M3U URL uses HTTP or HTTPS with a valid host.
  static Uri validateRemoteUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Alamat link M3U tidak boleh kosong.');
    }
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Format URL M3U tidak valid. Gunakan link http:// atau https://.',
      );
    }
    return uri;
  }

  /// Decodes raw bytes using UTF-8 with BOM removal and Latin-1 fallback for legacy M3U files.
  static String decodeM3uBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';
    List<int> cleanBytes = bytes;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      cleanBytes = bytes.sublist(3);
    }
    try {
      return utf8.decode(cleanBytes);
    } catch (_) {
      return latin1.decode(cleanBytes);
    }
  }

  static String? _cleanGroupName(String? rawGroup) {
    if (rawGroup == null) return null;
    final trimmed = rawGroup.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == 'undefined' ||
        trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }

  /// Parses M3U / M3U8 text into structured [TrackItem] entries (supports audio, local video, & IPTV HLS streams).
  static ParsedM3uResult parseM3uContent({
    required String content,
    required String playlistId,
    required String fallbackPlaylistName,
    String? baseDirectoryPath,
    List<String> additionalSearchDirs = const [],
    Uri? baseRemoteUri,
    bool probeFilesystem = false,
  }) {
    final lines = const LineSplitter().convert(content);
    String? playlistTitle;
    String? pendingExtInfTitle;
    int? pendingDuration;
    String? pendingGroup;
    String? pendingArtwork;
    bool pendingIptvMeta = false;
    bool pendingVlcOpts = false;
    Map<String, String> pendingHeaders = {};

    void resetPending() {
      pendingExtInfTitle = null;
      pendingDuration = null;
      pendingGroup = null;
      pendingArtwork = null;
      pendingIptvMeta = false;
      pendingVlcOpts = false;
      pendingHeaders = {};
    }

    final List<TrackItem> tracks = [];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        final upper = line.toUpperCase();
        if (upper.startsWith('#PLAYLIST:')) {
          final val = line.substring(10).trim();
          if (val.isNotEmpty) playlistTitle = val;
        } else if (upper.startsWith('#EXTGRP:')) {
          pendingGroup = _cleanGroupName(line.substring(8));
        } else if (upper.startsWith('#EXTIMG:')) {
          final val = line.substring(8).trim();
          if (val.isNotEmpty) pendingArtwork = val;
        } else if (upper.startsWith('#EXTVLCOPT:')) {
          pendingVlcOpts = true;
          final opt = line.substring(11).trim();
          final eqIdx = opt.indexOf('=');
          if (eqIdx > 0 && eqIdx + 1 < opt.length) {
            final key = opt.substring(0, eqIdx).trim().toLowerCase();
            final val = opt.substring(eqIdx + 1).trim();
            if (val.isNotEmpty) {
              if (key == 'http-user-agent') {
                pendingHeaders['User-Agent'] = val;
              } else if (key == 'http-referrer' || key == 'http-referer') {
                pendingHeaders['Referer'] = val;
              } else if (key == 'http-origin') {
                pendingHeaders['Origin'] = val;
              }
            }
          }
        } else if (upper.startsWith('#KODIPROP:')) {
          pendingVlcOpts = true;
        } else if (upper.startsWith('#EXTINF:')) {
          final match = _extInfRegex.firstMatch(line);
          if (match != null) {
            final durNum = double.tryParse(match.group(1) ?? '');
            if (durNum != null) {
              pendingDuration = durNum.round();
            }
            final attrsRaw = match.group(2) ?? '';
            for (final attrMatch in _attrRegex.allMatches(attrsRaw)) {
              final key = (attrMatch.group(1) ?? '').toLowerCase();
              final val = (attrMatch.group(2) ?? '').trim();
              if (val.isEmpty) continue;
              if (key == 'tvg-logo' || key == 'logo' || key == 'cover') {
                pendingArtwork = val;
              } else if (key == 'group-title' || key == 'group') {
                pendingGroup = _cleanGroupName(val);
              } else if (key == 'user-agent' || key == 'http-user-agent') {
                pendingHeaders['User-Agent'] = val;
              } else if (key == 'referrer' || key == 'http-referrer') {
                pendingHeaders['Referer'] = val;
              }
              if (key.startsWith('tvg-')) {
                pendingIptvMeta = true;
              }
            }
            pendingExtInfTitle = (match.group(3) ?? '').trim();
          } else {
            final commaIdx = line.indexOf(',');
            if (commaIdx != -1 && commaIdx + 1 < line.length) {
              pendingExtInfTitle = line.substring(commaIdx + 1).trim();
            }
          }
        }
        continue;
      }

      // Some IPTV M3U lines append `|User-Agent=...&Referer=...` after the URL
      String entryUrlPart = line;
      final pipeIdx = line.indexOf('|');
      if (pipeIdx > 0 &&
          (line.startsWith('http://') || line.startsWith('https://'))) {
        entryUrlPart = line.substring(0, pipeIdx).trim();
        final rawHeaderPairs = line.substring(pipeIdx + 1).split('&');
        for (final pair in rawHeaderPairs) {
          final eq = pair.indexOf('=');
          if (eq > 0 && eq + 1 < pair.length) {
            final hKey = pair.substring(0, eq).trim();
            final hVal = Uri.decodeFull(pair.substring(eq + 1).trim());
            if (hKey.isNotEmpty && hVal.isNotEmpty) {
              pendingHeaders[hKey] = hVal;
            }
          }
        }
      }

      final resolved = _resolveEntrySource(
        rawEntry: entryUrlPart,
        baseDirectoryPath: baseDirectoryPath,
        additionalSearchDirs: additionalSearchDirs,
        baseRemoteUri: baseRemoteUri,
        probeFilesystem: probeFilesystem,
      );

      if (resolved == null) {
        resetPending();
        continue;
      }

      final parsedMeta = _extractArtistAndTitle(
        extInfLabel: pendingExtInfTitle,
        resolvedPathOrUrl: resolved.pathOrUrl,
      );

      final isVideoEntry = TrackItem.detectIsVideo(
        pathOrUrl: resolved.pathOrUrl,
        title: parsedMeta.title,
        hasIptvMetadata: pendingIptvMeta,
        hasVlcVideoOpts: pendingVlcOpts,
      );

      final dirPath = resolved.isRemote
          ? (pendingGroup ?? fallbackPlaylistName)
          : p.dirname(resolved.pathOrUrl);
      final dirName = resolved.isRemote
          ? (pendingGroup ?? fallbackPlaylistName)
          : _friendlyDirName(dirPath, fallbackPlaylistName);

      tracks.add(
        TrackItem(
          id: TrackItem.generateId(resolved.pathOrUrl, playlistId: playlistId),
          title: parsedMeta.title,
          artist: parsedMeta.artist,
          album: pendingGroup ?? fallbackPlaylistName,
          groupTitle: pendingGroup,
          sourceType: resolved.isRemote
              ? TrackSourceType.remoteStream
              : TrackSourceType.localFile,
          pathOrUrl: resolved.pathOrUrl,
          localFileAvailable: resolved.localExists,
          directoryPath: dirPath,
          directoryName: dirName,
          playlistId: playlistId,
          durationSeconds:
              (pendingDuration != null && pendingDuration! > 0)
                  ? pendingDuration
                  : (pendingDuration != null && pendingDuration! < 0 ? -1 : null),
          artworkUrl: pendingArtwork,
          isVideo: isVideoEntry,
          httpHeaders:
              pendingHeaders.isEmpty ? null : Map<String, String>.from(pendingHeaders),
        ),
      );

      resetPending();
    }

    return ParsedM3uResult(
      embeddedTitle: playlistTitle,
      tracks: tracks,
    );
  }

  static _ResolvedSource? _resolveEntrySource({
    required String rawEntry,
    String? baseDirectoryPath,
    List<String> additionalSearchDirs = const [],
    Uri? baseRemoteUri,
    required bool probeFilesystem,
  }) {
    final trimmed = rawEntry.trim();
    if (trimmed.isEmpty) return null;

    // 1. Explicit remote stream or file link (http/https/rtsp/rtmp/ws/wss)
    if (RegExp(r'^(https?|rtsp|rtmp|wss?)://', caseSensitive: false)
        .hasMatch(trimmed)) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty) return null;
      return _ResolvedSource(
        pathOrUrl: uri.toString(),
        isRemote: true,
        localExists: false,
      );
    }

    // 2. file:// URI
    if (trimmed.toLowerCase().startsWith('file://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        String filePath;
        try {
          filePath = uri.toFilePath(windows: Platform.isWindows);
        } catch (_) {
          filePath = Uri.decodeFull(
            trimmed.replaceFirst(
              RegExp(r'^file:///?', caseSensitive: false),
              '/',
            ),
          );
        }
        return _ResolvedSource(
          pathOrUrl: filePath,
          isRemote: false,
          localExists: !probeFilesystem || _safeFileExists(filePath),
        );
      }
    }

    // 3. Relative entry inside a remote M3U URL
    if (baseRemoteUri != null &&
        !trimmed.startsWith('/storage/') &&
        !trimmed.startsWith('/sdcard/') &&
        !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
      if (probeFilesystem) {
        final androidCandidate = _tryResolveAndroidOfflinePath(
          trimmed,
          baseDirectoryPath,
          additionalSearchDirs,
        );
        if (androidCandidate != null) {
          return _ResolvedSource(
            pathOrUrl: androidCandidate,
            isRemote: false,
            localExists: true,
          );
        }
      }
      final resolvedUri = baseRemoteUri.resolve(trimmed);
      if (resolvedUri.scheme == 'http' || resolvedUri.scheme == 'https') {
        return _ResolvedSource(
          pathOrUrl: resolvedUri.toString(),
          isRemote: true,
          localExists: false,
        );
      }
    }

    // 4. Local absolute or relative file path (offline M3U)
    final normalizedSeparators = Platform.isWindows
        ? trimmed.replaceAll('/', '\\')
        : trimmed.replaceAll('\\', '/');

    if (p.isAbsolute(normalizedSeparators)) {
      final normalizedAbs = p.normalize(normalizedSeparators);
      if (probeFilesystem) {
        if (_safeFileExists(normalizedAbs)) {
          return _ResolvedSource(
            pathOrUrl: normalizedAbs,
            isRemote: false,
            localExists: true,
          );
        }
        if (!Platform.isWindows) {
          final storageAlt = '/storage/emulated/0$normalizedSeparators';
          if (_safeFileExists(storageAlt)) {
            return _ResolvedSource(
              pathOrUrl: storageAlt,
              isRemote: false,
              localExists: true,
            );
          }
        }
        return _ResolvedSource(
          pathOrUrl: normalizedAbs,
          isRemote: false,
          localExists: false,
        );
      }
      return _ResolvedSource(
        pathOrUrl: normalizedAbs,
        isRemote: false,
        localExists: true,
      );
    }

    if (!Platform.isWindows &&
        probeFilesystem &&
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
      final strippedDrive = trimmed.substring(2).replaceAll('\\', '/');
      final androidCandidate = _tryResolveAndroidOfflinePath(
        strippedDrive,
        baseDirectoryPath,
        additionalSearchDirs,
      );
      if (androidCandidate != null) {
        return _ResolvedSource(
          pathOrUrl: androidCandidate,
          isRemote: false,
          localExists: true,
        );
      }
    }

    if (probeFilesystem) {
      final found = _tryResolveAndroidOfflinePath(
        normalizedSeparators,
        baseDirectoryPath,
        additionalSearchDirs,
      );
      if (found != null) {
        return _ResolvedSource(
          pathOrUrl: found,
          isRemote: false,
          localExists: true,
        );
      }
    }

    if (baseDirectoryPath != null && baseDirectoryPath.isNotEmpty) {
      final candidate =
          p.normalize(p.join(baseDirectoryPath, normalizedSeparators));
      return _ResolvedSource(
        pathOrUrl: candidate,
        isRemote: false,
        localExists: !probeFilesystem || _safeFileExists(candidate),
      );
    }

    return _ResolvedSource(
      pathOrUrl: normalizedSeparators,
      isRemote: false,
      localExists: !probeFilesystem || _safeFileExists(normalizedSeparators),
    );
  }

  static bool _safeFileExists(String filePath) {
    try {
      return File(filePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String? _tryResolveAndroidOfflinePath(
    String relativeOrStripped,
    String? baseDirectoryPath,
    List<String> additionalSearchDirs,
  ) {
    final cleanRel = relativeOrStripped
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    final baseFileOnly = p.basename(cleanRel);

    final roots = <String>[
      if (baseDirectoryPath != null && baseDirectoryPath.isNotEmpty)
        baseDirectoryPath,
      ...additionalSearchDirs,
      '/storage/emulated/0',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ];

    for (final root in roots) {
      final testPath = p.normalize(p.join(root, cleanRel));
      if (_safeFileExists(testPath)) return testPath;
      if (baseFileOnly != cleanRel && baseFileOnly.isNotEmpty) {
        final flatCandidate = p.normalize(p.join(root, baseFileOnly));
        if (_safeFileExists(flatCandidate)) return flatCandidate;
      }
    }
    return null;
  }

  static ({String artist, String title}) _extractArtistAndTitle({
    String? extInfLabel,
    required String resolvedPathOrUrl,
  }) {
    if (extInfLabel != null && extInfLabel.trim().isNotEmpty) {
      final clean = extInfLabel.trim();
      final sepIndex = clean.indexOf(' - ');
      if (sepIndex > 0 && sepIndex + 3 < clean.length) {
        return (
          artist: clean.substring(0, sepIndex).trim(),
          title: clean.substring(sepIndex + 3).trim(),
        );
      }
      return (artist: 'Playlist M3U', title: clean);
    }

    String baseName = p.basenameWithoutExtension(
      resolvedPathOrUrl.split('?').first,
    );
    try {
      baseName = Uri.decodeComponent(baseName);
    } catch (_) {}
    baseName = baseName.replaceAll('_', ' ').trim();
    if (baseName.isEmpty) {
      baseName = 'Track Media';
    }
    final sepIndex = baseName.indexOf(' - ');
    if (sepIndex > 0 && sepIndex + 3 < baseName.length) {
      return (
        artist: baseName.substring(0, sepIndex).trim(),
        title: baseName.substring(sepIndex + 3).trim(),
      );
    }
    return (artist: 'Offline Media', title: baseName);
  }

  static String _friendlyDirName(String dirPath, String fallback) {
    final base = p.basename(dirPath).trim();
    if (base.isEmpty ||
        base == '.' ||
        base == '/' ||
        base == '\\' ||
        base.toLowerCase() == 'undefined') {
      return fallback;
    }
    return base;
  }

  /// Imports raw M3U bytes (used for Android SAF `content://` URIs & direct file reads).
  static Future<M3uPlaylist> importFromBytes({
    required List<int> bytes,
    required String displayFileName,
    String? resolvedSourcePath,
    String? baseDirectoryPath,
    List<String> additionalSearchDirs = const [],
    String? customName,
    String? existingId,
  }) async {
    final content = decodeM3uBytes(bytes);
    final seed = resolvedSourcePath ?? displayFileName;
    final id = existingId ?? safeCacheFileStem(seed, prefix: 'm3u_file');
    final defaultName = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : p.basenameWithoutExtension(displayFileName);

    final parsed = parseM3uContent(
      content: content,
      playlistId: id,
      fallbackPlaylistName: defaultName,
      baseDirectoryPath: baseDirectoryPath,
      additionalSearchDirs: additionalSearchDirs,
      probeFilesystem: true,
    );

    final cachedPath = await _saveOfflineM3uCopy(id, content);

    return M3uPlaylist(
      id: id,
      name: customName?.trim().isNotEmpty == true
          ? customName!.trim()
          : (parsed.embeddedTitle ?? defaultName),
      sourceType: M3uSourceType.file,
      sourceLocation: resolvedSourcePath ?? cachedPath,
      cachedM3uPath: cachedPath,
      tracks: parsed.tracks,
      updatedAt: DateTime.now(),
    );
  }

  /// Imports a local M3U / M3U8 file and caches a backup copy for guaranteed offline resilience.
  static Future<M3uPlaylist> importFromFile({
    required String filePath,
    List<String> additionalSearchDirs = const [],
    String? customName,
    String? existingId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File M3U tidak ditemukan', filePath);
    }
    final bytes = await file.readAsBytes();
    return importFromBytes(
      bytes: bytes,
      displayFileName: p.basename(filePath),
      resolvedSourcePath: filePath,
      baseDirectoryPath: p.dirname(filePath),
      additionalSearchDirs: additionalSearchDirs,
      customName: customName,
      existingId: existingId,
    );
  }

  /// Imports an M3U / M3U8 playlist from a remote HTTP/HTTPS URL and stores a local offline M3U cache.
  static Future<M3uPlaylist> importFromUrl({
    required String rawUrl,
    String? customName,
    String? existingId,
    Map<String, String>? existingOfflineTrackMap,
  }) async {
    final uri = validateRemoteUrl(rawUrl);
    final response = await http
        .get(
          uri,
          headers: const {
            'User-Agent': 'M3UMusikPlayer/1.1 (Android; OfflineM3U)',
            'Accept': '*/*',
          },
        )
        .timeout(_httpTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Gagal mengunduh playlist M3U (HTTP ${response.statusCode}).',
        uri: uri,
      );
    }

    final content = decodeM3uBytes(response.bodyBytes);
    final id = existingId ?? safeCacheFileStem(uri.toString(), prefix: 'm3u_url');

    final urlFileName = p.basenameWithoutExtension(uri.path);
    final defaultName = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : (urlFileName.isNotEmpty ? urlFileName : uri.host);

    final parsed = parseM3uContent(
      content: content,
      playlistId: id,
      fallbackPlaylistName: defaultName,
      baseRemoteUri: uri,
      probeFilesystem: true,
    );

    final List<TrackItem> mergedTracks = [];
    for (final track in parsed.tracks) {
      final existingOffline = existingOfflineTrackMap?[track.pathOrUrl];
      if (existingOffline != null && await File(existingOffline).exists()) {
        mergedTracks.add(track.copyWith(offlineCachePath: existingOffline));
      } else {
        mergedTracks.add(track);
      }
    }

    final cachedPath = await _saveOfflineM3uCopy(id, content);

    return M3uPlaylist(
      id: id,
      name: customName?.trim().isNotEmpty == true
          ? customName!.trim()
          : (parsed.embeddedTitle ?? defaultName),
      sourceType: M3uSourceType.url,
      sourceLocation: uri.toString(),
      cachedM3uPath: cachedPath,
      tracks: mergedTracks,
      updatedAt: DateTime.now(),
    );
  }

  /// Safely downloads a finite remote audio/video file into offline storage (rejects live HLS `.m3u8` streams).
  static Future<String> downloadTrackForOffline(TrackItem track) async {
    if (track.isLocalFile) return track.pathOrUrl;
    if (track.hasOfflineCache && await File(track.offlineCachePath!).exists()) {
      return track.offlineCachePath!;
    }

    final lowerPath = track.pathOrUrl.split('?').first.toLowerCase();
    if ((track.durationSeconds != null && track.durationSeconds! < 0) ||
        lowerPath.endsWith('.m3u8')) {
      throw const FileSystemException(
        'Siaran TV / Live Stream HLS (.m3u8) tidak dapat diunduh sebagai file statis offline.',
      );
    }

    final uri = validateRemoteUrl(track.pathOrUrl);
    final client = http.Client();
    File? partFile;

    try {
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] =
            track.httpHeaders?['User-Agent'] ?? 'M3UMusikPlayer/1.1 (Android)';
      if (track.httpHeaders != null) {
        request.headers.addAll(track.httpHeaders!);
      }
      final streamed = await client.send(request).timeout(_httpTimeout);

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw HttpException(
          'Gagal mengunduh media (HTTP ${streamed.statusCode})',
          uri: uri,
        );
      }

      final declaredLen = streamed.contentLength;
      if (declaredLen != null && declaredLen > maxOfflineTrackBytes) {
        throw const FileSystemException(
          'Ukuran file media melebihi batas aman 150 MB.',
        );
      }

      final supportDir = await getApplicationSupportDirectory();
      final offlineDir = Directory(p.join(supportDir.path, 'offline_tracks'));
      if (!await offlineDir.exists()) {
        await offlineDir.create(recursive: true);
      }

      String ext = p.extension(uri.path).toLowerCase();
      if (ext.isEmpty || ext.length > 6 || ext == '.m3u' || ext == '.m3u8') {
        ext = track.isVideo ? '.mp4' : '.mp3';
      }
      final safeStem = safeCacheFileStem(track.pathOrUrl, prefix: 'aud');
      final targetPath = p.join(offlineDir.path, '$safeStem$ext');
      partFile = File('$targetPath.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }

      final sink = partFile.openWrite();
      int receivedBytes = 0;
      final stopwatch = Stopwatch()..start();

      try {
        await for (final chunk
            in streamed.stream.timeout(_chunkIdleTimeout)) {
          receivedBytes += chunk.length;
          if (receivedBytes > maxOfflineTrackBytes) {
            throw const FileSystemException(
              'Unduhan dihentikan: stream melebihi 150 MB (kemungkinan live stream).',
            );
          }
          if (stopwatch.elapsed > _maxDownloadWallTime) {
            throw TimeoutException(
              'Waktu unduhan melebihi batas 3 menit (kemungkinan live stream).',
            );
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (receivedBytes == 0) {
        throw const FileSystemException('File media kosong (0 byte).');
      }

      final finalFile = File(targetPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(targetPath);
      return targetPath;
    } catch (_) {
      if (partFile != null) {
        try {
          if (await partFile.exists()) {
            await partFile.delete();
          }
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Generates Extended M3U content so users can also create/save custom offline M3U playlists.
  static String serializeToM3u({
    required String playlistName,
    required List<TrackItem> tracks,
  }) {
    final buffer = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#PLAYLIST:$playlistName');

    for (final track in tracks) {
      final dur = track.durationSeconds ?? -1;
      final groupAttr = track.groupTitle != null && track.groupTitle!.isNotEmpty
          ? ' group-title="${track.groupTitle!.replaceAll('"', "'")}"'
          : '';
      final logoAttr = track.hasValidNetworkArtwork
          ? ' tvg-logo="${track.artworkUrl!.replaceAll('"', "'")}"'
          : '';
      buffer.writeln(
        '#EXTINF:$dur$groupAttr$logoAttr,${track.artist} - ${track.title}',
      );
      final ua = track.httpHeaders?['User-Agent'];
      if (ua != null && ua.isNotEmpty) {
        buffer.writeln('#EXTVLCOPT:http-user-agent=$ua');
      }
      final ref = track.httpHeaders?['Referer'];
      if (ref != null && ref.isNotEmpty) {
        buffer.writeln('#EXTVLCOPT:http-referrer=$ref');
      }
      buffer.writeln(track.playableSource);
    }
    return buffer.toString();
  }

  static Future<M3uPlaylist> createCustomOfflineM3u({
    required String name,
    required List<TrackItem> tracks,
  }) async {
    final id = safeCacheFileStem(
      '${name}_${DateTime.now().microsecondsSinceEpoch}',
      prefix: 'm3u_custom',
    );
    final content = serializeToM3u(playlistName: name, tracks: tracks);
    final savedPath = await _saveOfflineM3uCopy(id, content);

    final clonedTracks = tracks
        .map(
          (t) => t.copyWith(
            id: TrackItem.generateId(t.playableSource, playlistId: id),
            playlistId: id,
          ),
        )
        .toList();

    return M3uPlaylist(
      id: id,
      name: name,
      sourceType: M3uSourceType.file,
      sourceLocation: savedPath,
      cachedM3uPath: savedPath,
      tracks: clonedTracks,
      updatedAt: DateTime.now(),
    );
  }

  static Future<String> _saveOfflineM3uCopy(String id, String content) async {
    final supportDir = await getApplicationSupportDirectory();
    final playlistsDir = Directory(p.join(supportDir.path, 'playlists'));
    if (!await playlistsDir.exists()) {
      await playlistsDir.create(recursive: true);
    }
    final safeName = safeCacheFileStem(id, prefix: 'pl');
    final file = File(p.join(playlistsDir.path, '$safeName.m3u8'));
    await file.writeAsString(content, flush: true);
    return file.path;
  }
}

class _ResolvedSource {
  final String pathOrUrl;
  final bool isRemote;
  final bool localExists;

  const _ResolvedSource({
    required this.pathOrUrl,
    required this.isRemote,
    required this.localExists,
  });
}
