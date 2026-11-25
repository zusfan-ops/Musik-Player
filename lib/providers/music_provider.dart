import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_models.dart';
import '../services/directory_scanner_service.dart';
import '../services/m3u_service.dart';

enum RepeatCycleMode {
  off,
  all,
  one,
}

class MusicProvider extends ChangeNotifier {
  static const String _kPlaylistsKey = 'm3u_playlists_v1';
  static const String _kCustomDirsKey = 'custom_music_dirs_v1';
  static const String _kFavoritesKey = 'favorite_track_ids_v1';
  static const String _kRecentTracksKey = 'recent_tracks_v1';
  static const String _kProgressMapKey = 'track_progress_sec_v1';
  static const String _kPlayCountMapKey = 'track_play_counts_v1';

  final bool autoScanOnInit;
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Random _random = Random();

  // Decoupled high-frequency position notifiers so main screens never rebuild 5x/sec!
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _bufferedPositionNotifier =
      ValueNotifier<Duration>(Duration.zero);

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool _isScanning = false;
  bool _isImportingM3u = false;
  bool _hasStoragePermission = false;
  String? _lastError;

  // Library state
  List<MusicDirectoryGroup> _directoryGroups = [];
  List<String> _customDirectories = [];
  List<String> _discoveredM3uFiles = [];
  List<M3uPlaylist> _playlists = [];
  Set<String> _favoriteIds = {};
  List<TrackItem> _recentTracks = [];
  Map<String, int> _trackProgressSeconds = {};
  Map<String, int> _playCounts = {};
  final Set<String> _downloadingTrackIds = {};

  // Memoized derived collections
  List<TrackItem>? _cachedAllTracks;
  List<MusicDirectoryGroup>? _cachedCombinedDirs;
  List<TrackItem>? _cachedFavoriteTracks;
  List<TrackItem>? _cachedOfflineDownloadedTracks;
  List<TrackItem>? _cachedTopPlayedTracks;

  // Active playback state
  List<TrackItem> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _shuffleEnabled = false;
  RepeatCycleMode _repeatMode = RepeatCycleMode.off;
  double _playbackSpeed = 1.0;
  Duration _duration = Duration.zero;
  int _loadRequestToken = 0;
  DateTime _lastProgressPersist = DateTime.fromMillisecondsSinceEpoch(0);

  // Sleep timer
  Timer? _sleepTimer;
  DateTime? _sleepEndTime;

  MusicProvider({this.autoScanOnInit = true});

  // Getters
  bool get initialized => _initialized;
  bool get isScanning => _isScanning;
  bool get isImportingM3u => _isImportingM3u;
  bool get hasStoragePermission => _hasStoragePermission;
  String? get lastError => _lastError;

  ValueListenable<Duration> get positionListenable => _positionNotifier;
  ValueListenable<Duration> get bufferedPositionListenable =>
      _bufferedPositionNotifier;

  Duration get position => _positionNotifier.value;
  Duration get bufferedPosition => _bufferedPositionNotifier.value;
  Duration get duration => _duration;

  List<MusicDirectoryGroup> get directoryGroups =>
      List.unmodifiable(_directoryGroups);
  List<String> get customDirectories => List.unmodifiable(_customDirectories);
  List<String> get discoveredM3uFiles => List.unmodifiable(_discoveredM3uFiles);
  List<M3uPlaylist> get playlists => List.unmodifiable(_playlists);
  List<TrackItem> get recentTracks => List.unmodifiable(_recentTracks);
  List<TrackItem> get queue => List.unmodifiable(_queue);

  int get currentIndex => _currentIndex;
  TrackItem? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatCycleMode get repeatMode => _repeatMode;
  double get playbackSpeed => _playbackSpeed;

  Duration? get sleepTimerRemaining {
    if (_sleepEndTime == null) return null;
    final diff = _sleepEndTime!.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  bool isTrackDownloading(String trackId) =>
      _downloadingTrackIds.contains(trackId);

  bool isFavorite(String trackId) => _favoriteIds.contains(trackId);

  int playCountOf(String trackId) => _playCounts[trackId] ?? 0;

  double savedProgressRatio(TrackItem track) {
    final savedSec = _trackProgressSeconds[track.id] ?? 0;
    final totalSec = track.durationSeconds ?? 210;
    if (savedSec <= 0 || totalSec <= 0) return 0.0;
    return (savedSec / totalSec).clamp(0.0, 1.0);
  }

  void _invalidateLibraryCache() {
    _cachedAllTracks = null;
    _cachedCombinedDirs = null;
    _cachedFavoriteTracks = null;
    _cachedOfflineDownloadedTracks = null;
    _cachedTopPlayedTracks = null;
  }

  /// Memoized unique tracks across scanned directories and enabled M3U playlists.
  List<TrackItem> get allTracks {
    if (_cachedAllTracks != null) return _cachedAllTracks!;
    final Map<String, TrackItem> map = {};
    for (final group in _directoryGroups) {
      for (final t in group.tracks) {
        map[t.id] = t;
      }
    }
    for (final pl in _playlists) {
      if (!pl.isEnabled) continue;
      for (final t in pl.tracks) {
        map[t.id] = t;
      }
    }
    _cachedAllTracks = List.unmodifiable(map.values.toList());
    return _cachedAllTracks!;
  }

  List<TrackItem> get favoriteTracks {
    if (_cachedFavoriteTracks != null) return _cachedFavoriteTracks!;
    final Map<String, TrackItem> byId = {for (final t in allTracks) t.id: t};
    for (final t in _recentTracks) {
      byId.putIfAbsent(t.id, () => t);
    }
    _cachedFavoriteTracks = List.unmodifiable(
      _favoriteIds.map((id) => byId[id]).whereType<TrackItem>().toList(),
    );
    return _cachedFavoriteTracks!;
  }

  List<TrackItem> get offlineDownloadedTracks {
    if (_cachedOfflineDownloadedTracks != null) {
      return _cachedOfflineDownloadedTracks!;
    }
    final List<TrackItem> list = [];
    for (final pl in _playlists) {
      for (final t in pl.tracks) {
        if (!t.isLocalFile && t.hasOfflineCache) {
          list.add(t);
        }
      }
    }
    _cachedOfflineDownloadedTracks = List.unmodifiable(list);
    return _cachedOfflineDownloadedTracks!;
  }

  List<TrackItem> get topPlayedTracks {
    if (_cachedTopPlayedTracks != null) return _cachedTopPlayedTracks!;
    final candidates = allTracks;
    if (candidates.isEmpty) {
      _cachedTopPlayedTracks = const [];
      return _cachedTopPlayedTracks!;
    }
    final sorted = List<TrackItem>.from(candidates)
      ..sort((a, b) {
        final cmp = (_playCounts[b.id] ?? 0).compareTo(_playCounts[a.id] ?? 0);
        if (cmp != 0) return cmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    _cachedTopPlayedTracks = List.unmodifiable(sorted.take(10).toList());
    return _cachedTopPlayedTracks!;
  }

  List<MusicDirectoryGroup> get combinedDirectoryGroups {
    if (_cachedCombinedDirs != null) return _cachedCombinedDirs!;
    final Map<String, List<TrackItem>> map = {};
    final Set<String> seenPaths = {};
    final Set<String> customSet =
        _customDirectories.map((d) => p.normalize(d)).toSet();

    for (final group in _directoryGroups) {
      for (final t in group.tracks) {
        if (seenPaths.add(t.pathOrUrl)) {
          map.putIfAbsent(group.directoryPath, () => []).add(t);
        }
      }
    }

    for (final pl in _playlists) {
      if (!pl.isEnabled) continue;
      for (final t in pl.tracks) {
        if (t.isLocalFile && seenPaths.add(t.pathOrUrl)) {
          map.putIfAbsent(t.directoryPath, () => []).add(t);
        }
      }
    }

    final keys = map.keys.toList()
      ..sort((a, b) =>
          p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));

    _cachedCombinedDirs = List.unmodifiable(
      keys.map((dirPath) {
        final dirName = p.basename(dirPath);
        return MusicDirectoryGroup(
          directoryPath: dirPath,
          directoryName: dirName.isEmpty ? dirPath : dirName,
          parentPath: p.dirname(dirPath),
          tracks: map[dirPath]!,
          isCustomRoot: customSet.any(
            (c) => dirPath == c || p.isWithin(c, dirPath),
          ),
        );
      }).toList(),
    );
    return _cachedCombinedDirs!;
  }

  List<String> get _knownLocalDirectories => <String>{
        ..._customDirectories,
        for (final g in _directoryGroups) g.directoryPath,
        for (final m in _discoveredM3uFiles) p.dirname(m),
      }.toList();

  Future<void> initialize() async {
    if (_initialized) return;

    _attachPlayerListeners();
    _prefs = await SharedPreferences.getInstance();
    _loadPersistedData();
    _invalidateLibraryCache();

    _initialized = true;
    notifyListeners();

    unawaited(_configureAudioSession());

    if (autoScanOnInit) {
      unawaited(refreshPermissionsAndScan(requestInteractive: false));
    }
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance.timeout(
        const Duration(seconds: 2),
      );
      await session
          .configure(const AudioSessionConfiguration.music())
          .timeout(const Duration(seconds: 2));
      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) {
          if (_isPlaying) {
            pause();
          }
        }),
      );
    } catch (_) {
      // Safe fallback in test or environments without native audio session
    }
  }

  void _attachPlayerListeners() {
    _subscriptions.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _isBuffering = false;
          _isPlaying = false;
          _lastError = 'Gangguan pemutaran audio: $error';
          notifyListeners();
        },
      ),
    );

    _subscriptions.add(
      _player.playingStream.listen((playing) {
        if (_isPlaying != playing) {
          _isPlaying = playing;
          notifyListeners();
        }
      }),
    );

    // High-frequency position updates ONLY notify `_positionNotifier` (not global ChangeNotifier!)
    _subscriptions.add(
      _player.positionStream.listen((pos) {
        _positionNotifier.value = pos;
        final active = currentTrack;
        if (active != null &&
            DateTime.now().difference(_lastProgressPersist).inSeconds >= 5) {
          _lastProgressPersist = DateTime.now();
          _trackProgressSeconds[active.id] = pos.inSeconds;
          unawaited(_persistProgressMap());
        }
      }),
    );

    _subscriptions.add(
      _player.bufferedPositionStream.listen((buffered) {
        _bufferedPositionNotifier.value = buffered;
      }),
    );

    _subscriptions.add(
      _player.durationStream.listen((dur) {
        if (dur != null && _duration != dur) {
          _duration = dur;
          notifyListeners();
        }
      }),
    );

    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        final buffering = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        if (_isBuffering != buffering) {
          _isBuffering = buffering;
          notifyListeners();
        }
        if (state.processingState == ProcessingState.completed) {
          _handleTrackCompleted();
        }
      }),
    );
  }

  void _loadPersistedData() {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final rawPlaylists = prefs.getStringList(_kPlaylistsKey) ?? const [];
      _playlists = rawPlaylists
          .map((s) => M3uPlaylist.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _playlists = [];
    }

    _customDirectories =
        List<String>.from(prefs.getStringList(_kCustomDirsKey) ?? const []);
    _favoriteIds =
        Set<String>.from(prefs.getStringList(_kFavoritesKey) ?? const []);

    try {
      final rawRecents = prefs.getStringList(_kRecentTracksKey) ?? const [];
      _recentTracks = rawRecents
          .map((s) => TrackItem.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _recentTracks = [];
    }

    try {
      final rawProgress = prefs.getString(_kProgressMapKey);
      if (rawProgress != null && rawProgress.isNotEmpty) {
        final decoded = jsonDecode(rawProgress) as Map<String, dynamic>;
        _trackProgressSeconds = decoded.map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
      }
    } catch (_) {
      _trackProgressSeconds = {};
    }

    try {
      final rawCounts = prefs.getString(_kPlayCountMapKey);
      if (rawCounts != null && rawCounts.isNotEmpty) {
        final decoded = jsonDecode(rawCounts) as Map<String, dynamic>;
        _playCounts = decoded.map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
      }
    } catch (_) {
      _playCounts = {};
    }
  }

  Future<void> _persistPlaylists() async {
    final encoded = _playlists.map((p) => jsonEncode(p.toJson())).toList();
    await _prefs?.setStringList(_kPlaylistsKey, encoded);
  }

  Future<void> _persistCustomDirs() async {
    await _prefs?.setStringList(_kCustomDirsKey, _customDirectories);
  }

  Future<void> _persistFavorites() async {
    await _prefs?.setStringList(_kFavoritesKey, _favoriteIds.toList());
  }

  Future<void> _persistRecentTracks() async {
    final encoded =
        _recentTracks.take(25).map((t) => jsonEncode(t.toJson())).toList();
    await _prefs?.setStringList(_kRecentTracksKey, encoded);
  }

  Future<void> _persistProgressMap() async {
    await _prefs?.setString(_kProgressMapKey, jsonEncode(_trackProgressSeconds));
  }

  Future<void> _persistPlayCounts() async {
    await _prefs?.setString(_kPlayCountMapKey, jsonEncode(_playCounts));
  }

  void clearError() {
    if (_lastError != null) {
      _lastError = null;
      notifyListeners();
    }
  }

  // ==================== DIRECTORY ACCESS & SCANNING ====================

  Future<void> refreshPermissionsAndScan({
    bool requestInteractive = true,
    bool requestAllFiles = false,
  }) async {
    if (_isScanning) return;
    _isScanning = true;
    _lastError = null;
    notifyListeners();

    try {
      if (requestInteractive) {
        _hasStoragePermission =
            await DirectoryScannerService.requestAudioAndDirectoryPermission(
          requestAllFilesIfNeeded: requestAllFiles,
        );
      } else {
        _hasStoragePermission =
            await DirectoryScannerService.checkAudioAndDirectoryPermission();
      }

      final result = await DirectoryScannerService.scanDirectories(
        customDirectories: _customDirectories,
        includeDefaultAndroidDirs: true,
      );
      _directoryGroups = result.directories;
      _discoveredM3uFiles = result.discoveredM3uFiles;
      _invalidateLibraryCache();
    } catch (e) {
      _lastError = 'Gagal memindai direktori musik: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Opens native folder picker so user can add one or more custom music directories.
  Future<bool> pickAndAddDirectory() async {
    try {
      await DirectoryScannerService.requestAudioAndDirectoryPermission(
        requestAllFilesIfNeeded: true,
      );
      final selectedUri = await FilePicker.pickDirectory(
        dialogTitle: 'Pilih Direktori Musik Offline',
      );
      if (selectedUri == null) {
        return false;
      }
      final resolvedDir =
          DirectoryScannerService.resolveAndroidSafUriToPath(selectedUri) ??
              (selectedUri.path.isNotEmpty ? selectedUri.path : null);
      if (resolvedDir == null || resolvedDir.trim().isEmpty) {
        return false;
      }
      final normalized = p.normalize(resolvedDir.trim());
      if (!_customDirectories.contains(normalized)) {
        _customDirectories.add(normalized);
        await _persistCustomDirs();
      }
      await refreshPermissionsAndScan(requestInteractive: false);
      return true;
    } catch (e) {
      _lastError = 'Tidak dapat mengakses direktori: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> addDirectoryByPath(String rawPath) async {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return;
    final normalized = p.normalize(trimmed);
    if (!await Directory(normalized).exists()) {
      throw FileSystemException('Direktori tidak ditemukan', normalized);
    }
    if (!_customDirectories.contains(normalized)) {
      _customDirectories.add(normalized);
      await _persistCustomDirs();
    }
    await refreshPermissionsAndScan(requestInteractive: false);
  }

  Future<void> removeCustomDirectory(String dirPath) async {
    _customDirectories.remove(dirPath);
    await _persistCustomDirs();
    await refreshPermissionsAndScan(requestInteractive: false);
  }

  // ==================== MULTI-M3U PLAYLIST MANAGEMENT ====================

  /// Lets user select one or MULTIPLE local `.m3u` / `.m3u8` files via SAF or file explorer!
  Future<int> pickAndImportM3uFiles() async {
    _isImportingM3u = true;
    _lastError = null;
    notifyListeners();

    int importedCount = 0;
    try {
      await DirectoryScannerService.requestAudioAndDirectoryPermission(
        requestAllFilesIfNeeded: false,
      );
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Pilih Satu atau Beberapa File Playlist M3U / M3U8',
        type: FileType.custom,
        allowedExtensions: const ['m3u', 'm3u8', 'txt'],
      );
      if (files.isEmpty) {
        return 0;
      }

      for (final file in files) {
        // Resolve real storage path from Android SAF URI (e.g. primary:Music/Pop/list.m3u)
        String? resolvedRealPath =
            DirectoryScannerService.resolveAndroidSafUriToPath(file.uri) ??
                file.path;

        // If SAF gave an opaque URI (e.g. msf:123), check if filename matches any discovered M3U in folders
        if (resolvedRealPath == null || resolvedRealPath.isEmpty) {
          final matched = _discoveredM3uFiles.cast<String?>().firstWhere(
                (m) =>
                    m != null &&
                    p.basename(m).toLowerCase() == file.name.toLowerCase(),
                orElse: () => null,
              );
          resolvedRealPath = matched;
        }

        final String? baseDir =
            resolvedRealPath != null ? p.dirname(resolvedRealPath) : null;

        // Read bytes directly via PlatformFile.readAsBytes() (works for both SAF content:// and file://!)
        final bytes = await file.readAsBytes();
        final existingIdx = _playlists.indexWhere(
          (pl) =>
              pl.sourceType == M3uSourceType.file &&
              ((resolvedRealPath != null &&
                      p.normalize(pl.sourceLocation) ==
                          p.normalize(resolvedRealPath)) ||
                  pl.name.toLowerCase() ==
                      p.basenameWithoutExtension(file.name).toLowerCase()),
        );

        final playlist = await M3uService.importFromBytes(
          bytes: bytes,
          displayFileName: file.name,
          resolvedSourcePath: resolvedRealPath,
          baseDirectoryPath: baseDir,
          additionalSearchDirs: _knownLocalDirectories,
          existingId: existingIdx >= 0 ? _playlists[existingIdx].id : null,
        );

        if (existingIdx >= 0) {
          _playlists[existingIdx] = playlist;
        } else {
          _playlists.insert(0, playlist);
        }
        importedCount++;
      }

      _invalidateLibraryCache();
      await _persistPlaylists();
      return importedCount;
    } catch (e) {
      _lastError = 'Gagal mengimpor file M3U: $e';
      return importedCount;
    } finally {
      _isImportingM3u = false;
      notifyListeners();
    }
  }

  Future<M3uPlaylist> addM3uFromFilePath(
    String filePath, {
    String? customName,
  }) async {
    final existingIdx = _playlists.indexWhere(
      (pl) =>
          pl.sourceType == M3uSourceType.file &&
          p.normalize(pl.sourceLocation) == p.normalize(filePath),
    );
    final playlist = await M3uService.importFromFile(
      filePath: filePath,
      additionalSearchDirs: _knownLocalDirectories,
      customName: customName,
      existingId: existingIdx >= 0 ? _playlists[existingIdx].id : null,
    );

    if (existingIdx >= 0) {
      _playlists[existingIdx] = playlist;
    } else {
      _playlists.insert(0, playlist);
    }
    _invalidateLibraryCache();
    await _persistPlaylists();
    notifyListeners();
    return playlist;
  }

  /// Adds one or multiple M3U URLs (supports multi-line input so user can paste several links at once!).
  Future<int> addM3uFromUrls({
    required String rawUrlsInput,
    String? customName,
  }) async {
    final lines = const LineSplitter()
        .convert(rawUrlsInput)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw const FormatException('Masukkan minimal satu alamat link M3U.');
    }

    _isImportingM3u = true;
    _lastError = null;
    notifyListeners();

    int addedCount = 0;
    try {
      for (int i = 0; i < lines.length; i++) {
        final url = lines[i];
        final nameForThis = (customName != null && customName.trim().isNotEmpty)
            ? (lines.length > 1
                ? '${customName.trim()} #${i + 1}'
                : customName.trim())
            : null;

        final existingIdx = _playlists.indexWhere(
          (pl) =>
              pl.sourceType == M3uSourceType.url &&
              pl.sourceLocation.toLowerCase() == url.toLowerCase(),
        );

        Map<String, String>? existingOfflineMap;
        if (existingIdx >= 0) {
          existingOfflineMap = {
            for (final t in _playlists[existingIdx].tracks)
              if (t.offlineCachePath != null) t.pathOrUrl: t.offlineCachePath!,
          };
        }

        final playlist = await M3uService.importFromUrl(
          rawUrl: url,
          customName: nameForThis,
          existingId: existingIdx >= 0 ? _playlists[existingIdx].id : null,
          existingOfflineTrackMap: existingOfflineMap,
        );

        if (existingIdx >= 0) {
          _playlists[existingIdx] = playlist;
        } else {
          _playlists.insert(0, playlist);
        }
        addedCount++;
      }

      _invalidateLibraryCache();
      await _persistPlaylists();
      return addedCount;
    } finally {
      _isImportingM3u = false;
      notifyListeners();
    }
  }

  Future<void> refreshM3uPlaylist(String playlistId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;

    final current = _playlists[idx];
    _isImportingM3u = true;
    _lastError = null;
    notifyListeners();

    try {
      M3uPlaylist refreshed;
      if (current.isUrlSource) {
        final offlineMap = {
          for (final t in current.tracks)
            if (t.offlineCachePath != null) t.pathOrUrl: t.offlineCachePath!,
        };
        refreshed = await M3uService.importFromUrl(
          rawUrl: current.sourceLocation,
          customName: current.name,
          existingId: current.id,
          existingOfflineTrackMap: offlineMap,
        );
      } else {
        final origExists = await File(current.sourceLocation).exists();
        final sourcePath = origExists
            ? current.sourceLocation
            : (current.cachedM3uPath ?? current.sourceLocation);
        refreshed = await M3uService.importFromFile(
          filePath: sourcePath,
          additionalSearchDirs: _knownLocalDirectories,
          customName: current.name,
          existingId: current.id,
        );
      }
      _playlists[idx] = refreshed.copyWith(isEnabled: current.isEnabled);
      _invalidateLibraryCache();
      await _persistPlaylists();
    } catch (e) {
      _lastError = 'Gagal menyinkronkan playlist "${current.name}": $e';
      rethrow;
    } finally {
      _isImportingM3u = false;
      notifyListeners();
    }
  }

  Future<M3uPlaylist> createOfflinePlaylistFromTracks({
    required String name,
    required List<TrackItem> tracks,
  }) async {
    final playlist = await M3uService.createCustomOfflineM3u(
      name: name,
      tracks: tracks,
    );
    _playlists.insert(0, playlist);
    _invalidateLibraryCache();
    await _persistPlaylists();
    notifyListeners();
    return playlist;
  }

  Future<void> togglePlaylistEnabled(String playlistId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    _playlists[idx] =
        _playlists[idx].copyWith(isEnabled: !_playlists[idx].isEnabled);
    _invalidateLibraryCache();
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    _playlists[idx] = _playlists[idx].copyWith(name: trimmed);
    _invalidateLibraryCache();
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final removed = _playlists.removeAt(idx);

    if (removed.cachedM3uPath != null) {
      try {
        final f = File(removed.cachedM3uPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    // Delete any downloaded offline audio files no longer referenced by any remaining playlist
    final Set<String> stillReferencedCaches = {
      for (final pl in _playlists)
        for (final t in pl.tracks)
          if (t.offlineCachePath != null) t.offlineCachePath!,
    };
    for (final t in removed.tracks) {
      final cachePath = t.offlineCachePath;
      if (cachePath != null &&
          cachePath.isNotEmpty &&
          !stillReferencedCaches.contains(cachePath)) {
        try {
          final f = File(cachePath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        _recentTracks = _recentTracks
            .map((rt) =>
                rt.offlineCachePath == cachePath
                    ? rt.copyWith(clearOfflineCache: true)
                    : rt)
            .toList();
      }
    }

    _invalidateLibraryCache();
    await _persistPlaylists();
    await _persistRecentTracks();
    notifyListeners();
  }

  /// Downloads a remote stream track to offline storage so it works with zero internet.
  Future<bool> downloadTrackOffline(TrackItem track) async {
    if (track.isOfflineReady || _downloadingTrackIds.contains(track.id)) {
      return true;
    }
    _downloadingTrackIds.add(track.id);
    notifyListeners();

    try {
      final cachedFile = await M3uService.downloadTrackForOffline(track);
      _updateTrackOfflineCache(track.pathOrUrl, cachedFile);
      _invalidateLibraryCache();
      await _persistPlaylists();
      return true;
    } catch (e) {
      _lastError = 'Gagal menyimpan lagu untuk offline: $e';
      return false;
    } finally {
      _downloadingTrackIds.remove(track.id);
      notifyListeners();
    }
  }

  Future<int> downloadEntirePlaylistOffline(String playlistId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return 0;
    final tracks = List<TrackItem>.from(_playlists[idx].tracks);
    int success = 0;
    for (final t in tracks) {
      if (t.isOfflineReady) {
        success++;
        continue;
      }
      final lower = t.pathOrUrl.split('?').first.toLowerCase();
      if ((t.durationSeconds != null && t.durationSeconds! < 0) ||
          lower.endsWith('.m3u8')) {
        continue;
      }
      final ok = await downloadTrackOffline(t);
      if (ok) success++;
    }
    return success;
  }

  void _updateTrackOfflineCache(String rawSourceUrl, String offlinePath) {
    for (int pIdx = 0; pIdx < _playlists.length; pIdx++) {
      final pl = _playlists[pIdx];
      bool changed = false;
      final updatedTracks = pl.tracks.map((t) {
        if (t.pathOrUrl == rawSourceUrl) {
          changed = true;
          return t.copyWith(offlineCachePath: offlinePath);
        }
        return t;
      }).toList();
      if (changed) {
        _playlists[pIdx] = pl.copyWith(tracks: updatedTracks);
      }
    }

    for (int qIdx = 0; qIdx < _queue.length; qIdx++) {
      if (_queue[qIdx].pathOrUrl == rawSourceUrl) {
        _queue[qIdx] = _queue[qIdx].copyWith(offlineCachePath: offlinePath);
      }
    }
  }

  // ==================== FAVORITES ====================

  Future<void> toggleFavorite(TrackItem track) async {
    if (_favoriteIds.contains(track.id)) {
      _favoriteIds.remove(track.id);
    } else {
      _favoriteIds.add(track.id);
      if (!_recentTracks.any((t) => t.id == track.id)) {
        _recentTracks.insert(0, track);
        await _persistRecentTracks();
      }
    }
    _invalidateLibraryCache();
    await _persistFavorites();
    notifyListeners();
  }

  // ==================== PLAYBACK ENGINE ====================

  Future<void> playTrackList(
    List<TrackItem> tracks, {
    int initialIndex = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;

    _queue = List<TrackItem>.from(tracks);
    _shuffleEnabled = shuffle;

    int targetIndex = initialIndex.clamp(0, _queue.length - 1);
    if (shuffle && initialIndex == 0 && _queue.length > 1) {
      targetIndex = _random.nextInt(_queue.length);
    }

    await _loadAndPlayAtIndex(targetIndex);
  }

  Future<void> playSingleTrack(TrackItem track) async {
    await playTrackList([track], initialIndex: 0);
  }

  Future<void> addToQueue(TrackItem track) async {
    if (_queue.isEmpty) {
      await playSingleTrack(track);
      return;
    }
    _queue.add(track);
    notifyListeners();
  }

  Future<void> jumpToQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _loadAndPlayAtIndex(index);
  }

  Future<void> _loadAndPlayAtIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final int requestToken = ++_loadRequestToken;
    _currentIndex = index;
    _positionNotifier.value = Duration.zero;
    _bufferedPositionNotifier.value = Duration.zero;
    _duration = Duration.zero;
    _lastError = null;
    notifyListeners();

    final track = _queue[index];
    try {
      await _player.stop();
      if (requestToken != _loadRequestToken) return;

      if (track.playsFromLocalFile) {
        final filePath = track.playableSource;
        final file = File(filePath);
        if (!await file.exists()) {
          // If offline cache was cleared externally, fall back to remote stream if available
          if (!track.isLocalFile) {
            final uri = Uri.parse(track.pathOrUrl);
            await _player.setAudioSource(
              AudioSource.uri(uri, headers: track.httpHeaders),
            );
          } else {
            throw FileSystemException(
              'File audio offline tidak ditemukan di penyimpanan',
              filePath,
            );
          }
        } else {
          await _player.setFilePath(filePath);
        }
      } else {
        final uri = Uri.parse(track.playableSource);
        await _player.setAudioSource(
          AudioSource.uri(uri, headers: track.httpHeaders),
        );
      }

      if (requestToken != _loadRequestToken) return;
      await _player.setSpeed(_playbackSpeed);
      unawaited(
        _player.play().catchError((Object e) {
          if (requestToken == _loadRequestToken) {
            _isBuffering = false;
            _isPlaying = false;
            _lastError = 'Tidak dapat memutar "${track.title}": $e';
            notifyListeners();
          }
        }),
      );

      _recordTrackPlayed(track);
    } catch (e) {
      if (requestToken != _loadRequestToken) return;
      _isBuffering = false;
      _isPlaying = false;
      _lastError = 'Tidak dapat memutar "${track.title}": $e';
      notifyListeners();
    }
  }

  void _recordTrackPlayed(TrackItem track) {
    _recentTracks.removeWhere((t) => t.id == track.id);
    _recentTracks.insert(0, track);
    if (_recentTracks.length > 25) {
      _recentTracks = _recentTracks.sublist(0, 25);
    }
    _playCounts[track.id] = (_playCounts[track.id] ?? 0) + 1;
    _cachedTopPlayedTracks = null;
    _cachedFavoriteTracks = null;
    unawaited(_persistRecentTracks());
    unawaited(_persistPlayCounts());
  }

  Future<void> togglePlayPause() async {
    if (currentTrack == null) {
      final fallback = allTracks;
      if (fallback.isNotEmpty) {
        await playTrackList(fallback);
      }
      return;
    }

    try {
      if (_player.playing) {
        await pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
    } catch (e) {
      _lastError = 'Gagal mengubah status putar: $e';
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> seekTo(Duration target) async {
    await _player.seek(target);
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    if (_shuffleEnabled && _queue.length > 1) {
      int nextIdx = _currentIndex;
      for (int attempt = 0; attempt < 5 && nextIdx == _currentIndex; attempt++) {
        nextIdx = _random.nextInt(_queue.length);
      }
      await _loadAndPlayAtIndex(nextIdx);
      return;
    }

    if (_currentIndex + 1 < _queue.length) {
      await _loadAndPlayAtIndex(_currentIndex + 1);
    } else if (_repeatMode == RepeatCycleMode.all) {
      await _loadAndPlayAtIndex(0);
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) return;
    if (_positionNotifier.value.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_currentIndex - 1 >= 0) {
      await _loadAndPlayAtIndex(_currentIndex - 1);
    } else if (_repeatMode == RepeatCycleMode.all) {
      await _loadAndPlayAtIndex(_queue.length - 1);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
  }

  void cycleRepeatMode() {
    switch (_repeatMode) {
      case RepeatCycleMode.off:
        _repeatMode = RepeatCycleMode.all;
        break;
      case RepeatCycleMode.all:
        _repeatMode = RepeatCycleMode.one;
        break;
      case RepeatCycleMode.one:
        _repeatMode = RepeatCycleMode.off;
        break;
    }
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed.clamp(0.5, 2.0);
    await _player.setSpeed(_playbackSpeed);
    notifyListeners();
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (duration == null) {
      _sleepEndTime = null;
      notifyListeners();
      return;
    }
    _sleepEndTime = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      pause();
      _sleepEndTime = null;
      _sleepTimer = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _handleTrackCompleted() {
    final active = currentTrack;
    if (active != null) {
      _trackProgressSeconds.remove(active.id);
      unawaited(_persistProgressMap());
    }

    if (_repeatMode == RepeatCycleMode.one && _currentIndex >= 0) {
      _player
          .seek(Duration.zero)
          .then((_) => _player.play())
          .catchError((Object e) {
        _lastError = 'Gagal mengulang lagu: $e';
        notifyListeners();
      });
      return;
    }

    if (_shuffleEnabled && _queue.length > 1) {
      playNext();
      return;
    }

    if (_currentIndex + 1 < _queue.length) {
      _loadAndPlayAtIndex(_currentIndex + 1);
    } else if (_repeatMode == RepeatCycleMode.all && _queue.isNotEmpty) {
      _loadAndPlayAtIndex(0);
    } else {
      _isPlaying = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _positionNotifier.dispose();
    _bufferedPositionNotifier.dispose();
    _player.dispose();
    super.dispose();
  }
}
