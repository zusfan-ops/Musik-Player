import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_models.dart';
import '../services/artwork_service.dart';
import '../services/cast_media_server.dart';
import '../services/directory_scanner_service.dart';
import 'package:http/http.dart' as http;
import '../services/config_backup_service.dart';
import '../services/github_m3u_sync_service.dart';
import '../services/link_checker_service.dart';
import '../services/m3u_service.dart';
import '../services/newtube_service.dart';

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
  static const String _kOnboardingKey = 'has_seen_onboarding_v1';
  static const String _kDeadLinksKey = 'dead_m3u_track_ids_v1';
  static const String _kHideDeadLinksKey = 'hide_dead_m3u_links_v1';
  static const String _kEqEnabledKey = 'eq_enabled_v1';
  static const String _kEqGainsKey = 'eq_band_gains_v1';
  static const String _kEqPresetKey = 'eq_preset_v1';
  static const String _kBassBoostKey = 'eq_bass_boost_v1';
  static const String _kLoudnessDbKey = 'eq_loudness_db_v1';
  static const String _kAutoSyncYtPlaylistsKey = 'auto_sync_yt_playlists_v1';
  static const String _kSeededDefaultTvKey = 'seeded_default_tv_v1';
  static const String _kYtAutoCacheEnabledKey = 'yt_auto_cache_enabled_v1';
  static const int _maxYtStreamCacheBytes = 500 * 1024 * 1024;
  static const int _targetYtStreamCacheBytes = 400 * 1024 * 1024;
  static const int _maxSingleYtCacheFileBytes = 60 * 1024 * 1024;
  static const String _kAlarmEnabledKey = 'music_alarm_enabled_v1';
  static const String _kAlarmHourKey = 'music_alarm_hour_v1';
  static const String _kAlarmMinuteKey = 'music_alarm_minute_v1';
  static const String _kCrossfadeSecKey = 'audio_crossfade_sec_v1';
  static const String defaultTvPlaylistUrl =
      'https://iptv-org.github.io/iptv/countries/id.m3u';
  static const MethodChannel _widgetChannel =
      MethodChannel('com.musikm3u.player/media_store');
  static bool _mediaKitInitialized = false;
  static void markMediaKitInitialized() => _mediaKitInitialized = true;

  final bool autoScanOnInit;
  late final AndroidEqualizer? _androidEqualizer;
  late final AndroidLoudnessEnhancer? _androidLoudness;
  late final AudioPlayer? _justAudioPlayer;
  late final mk.Player? _mkPlayer;
  bool get _useMediaKit => _mkPlayer != null;
  final CastMediaServer _castServer = CastMediaServer();
  final StreamController<bool> _pipController =
      StreamController<bool>.broadcast();
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
  final Set<String> _downloadingYouTubeIds = {};
  final Set<String> _cachingYouTubeIds = {};
  final Set<String> _downloadedYouTubeIds = {};
  bool _ytAutoCacheEnabled = true;
  bool _isDownloadingYouTubePlaylist = false;
  bool _cancelYouTubeDownloadRequested = false;
  String? _ytDownloadLabel;
  double _ytDownloadProgress = 0.0;
  Map<String, Map<String, dynamic>> _ytOfflineMeta = {};
  List<NewTubePlaylistItem> _autoSyncYouTubePlaylists = [];
  String? _youTubeOfflineRootPath;

  // Memoized derived collections
  List<TrackItem>? _cachedAllTracks;
  List<MusicDirectoryGroup>? _cachedCombinedDirs;
  List<TrackItem>? _cachedFavoriteTracks;
  List<TrackItem>? _cachedOfflineDownloadedTracks;
  List<TrackItem>? _cachedTopPlayedTracks;

  // Active playback state
  List<TrackItem> _queue = [];
  int _windowStart = 0;
  int _currentIndex = -1;
  Uri? _defaultArtUri;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _miniPlayerDismissed = false;
  bool _hasSeenOnboarding = false;
  bool _shuffleEnabled = false;
  RepeatCycleMode _repeatMode = RepeatCycleMode.off;
  double _playbackSpeed = 1.0;
  Duration _duration = Duration.zero;
  int _loadRequestToken = 0;
  DateTime _lastProgressPersist = DateTime.fromMillisecondsSinceEpoch(0);

  // Sleep timer, Music Alarm & Crossfade
  Timer? _sleepTimer;
  DateTime? _sleepEndTime;
  Timer? _alarmTicker;
  Timer? _fadeVolumeTimer;
  bool _alarmEnabled = false;
  int _alarmHour = 6;
  int _alarmMinute = 30;
  String? _lastTriggeredAlarmDateKey;
  int _crossfadeSeconds = 0;

  // Equalizer & audio effects state
  bool _equalizerEnabled = false;
  List<double> _eqBandGains = [0.0, 0.0, 0.0, 0.0, 0.0];
  List<String> _eqBandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];
  double _eqMinDecibels = -15.0;
  double _eqMaxDecibels = 15.0;
  String _activeEqPreset = 'Flat';
  double _bassBoostStrength = 0.0; // 0.0..1.0
  double _loudnessGainDb = 0.0; // 0.0..10.0 dB

  // Link checker state
  Set<String> _deadTrackIds = {};
  bool _hideDeadLinks = true;
  bool _isCheckingLinks = false;
  int _linkCheckDone = 0;
  int _linkCheckTotal = 0;

  // Cast & PiP state
  bool _isCastConnected = false;
  String? _castDeviceName;

  // Lazy-resolved NewTube queue state
  List<NewTubeItem> _pendingNewTubeItems = const [];
  int _newTubeSessionToken = 0;
  int? _preloadingNewTubeSessionToken;

  MusicProvider({this.autoScanOnInit = true}) {
    if (Platform.isAndroid) {
      _androidEqualizer = AndroidEqualizer();
      _androidLoudness = AndroidLoudnessEnhancer();
      _justAudioPlayer = AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [_androidEqualizer!, _androidLoudness!],
        ),
      );
      _mkPlayer = null;
    } else if ((Platform.isWindows || Platform.isLinux) &&
        _mediaKitInitialized) {
      _androidEqualizer = null;
      _androidLoudness = null;
      _justAudioPlayer = null;
      _mkPlayer = mk.Player(
        configuration: const mk.PlayerConfiguration(
          title: 'MediaCenter',
        ),
      );
    } else {
      _androidEqualizer = null;
      _androidLoudness = null;
      _justAudioPlayer = AudioPlayer();
      _mkPlayer = null;
    }
  }

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
  bool get isMiniPlayerVisible => currentTrack != null && !_miniPlayerDismissed;
  bool get hasSeenOnboarding => _hasSeenOnboarding;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatCycleMode get repeatMode => _repeatMode;
  double get playbackSpeed => _playbackSpeed;

  // Equalizer getters
  bool get equalizerEnabled => _equalizerEnabled;
  List<double> get eqBandGains => List.unmodifiable(_eqBandGains);
  List<String> get eqBandLabels => List.unmodifiable(_eqBandLabels);
  double get eqMinDecibels => _eqMinDecibels;
  double get eqMaxDecibels => _eqMaxDecibels;
  String get activeEqPreset => _activeEqPreset;
  double get bassBoostStrength => _bassBoostStrength;
  double get loudnessGainDb => _loudnessGainDb;

  // Link checker getters
  Set<String> get deadTrackIds => Set.unmodifiable(_deadTrackIds);
  bool get hideDeadLinks => _hideDeadLinks;
  bool get isCheckingLinks => _isCheckingLinks;
  int get linkCheckDone => _linkCheckDone;
  int get linkCheckTotal => _linkCheckTotal;
  bool isTrackDead(String trackId) => _deadTrackIds.contains(trackId);

  // Cast & PiP getters
  bool get isCastConnected => _isCastConnected;
  String? get castDeviceName => _castDeviceName;
  Stream<bool> get pipModeStream => _pipController.stream;

  Duration? get sleepTimerRemaining {
    if (_sleepEndTime == null) return null;
    final diff = _sleepEndTime!.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  bool get alarmEnabled => _alarmEnabled;
  int get alarmHour => _alarmHour;
  int get alarmMinute => _alarmMinute;
  int get crossfadeSeconds => _crossfadeSeconds;

  bool isTrackDownloading(String trackId) =>
      _downloadingTrackIds.contains(trackId);

  bool isYouTubeVideoDownloaded(String videoId) =>
      _downloadedYouTubeIds.contains(videoId);

  bool isYouTubeVideoDownloading(String videoId) =>
      _downloadingYouTubeIds.contains(videoId);

  bool get isDownloadingYouTube =>
      _isDownloadingYouTubePlaylist || _downloadingYouTubeIds.isNotEmpty;

  String? get ytDownloadLabel => _ytDownloadLabel;
  double get ytDownloadProgress => _ytDownloadProgress;

  List<TrackItem> get allOfflineMusicTracks =>
      allTracks.where((t) => !t.isVideo && t.isOfflineReady).toList();

  List<MusicDirectoryGroup> get youTubeOfflineFolders {
    final root = _youTubeOfflineRootPath;
    if (root == null || root.isEmpty) return const [];
    final normRoot = p.normalize(root).toLowerCase();
    return combinedDirectoryGroups
        .where((g) => p.normalize(g.directoryPath).toLowerCase().startsWith(normRoot))
        .toList();
  }

  List<NewTubePlaylistItem> get autoSyncYouTubePlaylists =>
      List.unmodifiable(_autoSyncYouTubePlaylists);

  bool isYouTubePlaylistAutoSync(String playlistId) =>
      _autoSyncYouTubePlaylists.any((p) => p.playlistId == playlistId);

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

  @visibleForTesting
  Future<void> initializeForTest() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPersistedData();
    _invalidateLibraryCache();
    _initialized = true;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    _attachPlayerListeners();
    if (Platform.isAndroid || Platform.isWindows) {
      _widgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'onWidgetAction') {
          await _handleWidgetAction(call.arguments as String?);
        } else if (call.method == 'onPipChanged') {
          final inPip = call.arguments == true;
          if (!_pipController.isClosed) {
            _pipController.add(inPip);
          }
        } else if (call.method == 'onCastSessionChanged') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          final connected = args?['connected'] == true;
          final devName = args?['deviceName'] as String?;
          _onCastSessionUpdated(connected, devName);
        }
      });
    }
    _prefs = await SharedPreferences.getInstance();
    _loadPersistedData();
    unawaited(ArtworkService.warmCacheFromDisk());
    unawaited(_syncAudioEffectsToPipeline());
    _invalidateLibraryCache();

    _initialized = true;
    notifyListeners();

    unawaited(_configureAudioSession());
    unawaited(_prepareDefaultArtworkUri());

    if (autoScanOnInit) {
      unawaited(_seedDefaultTvPlaylistIfNeeded());
      unawaited(syncGithubM3uDirectory());
      unawaited(
        refreshPermissionsAndScan(requestInteractive: false).then((_) async {
          if (Platform.isAndroid) {
            final pending = await _widgetChannel
                .invokeMethod<String>('consumePendingWidgetAction')
                .catchError((_) => null);
            await _handleWidgetAction(pending);
          }
        }),
      );
    }
  }

  Future<void> _seedDefaultTvPlaylistIfNeeded() async {
    try {
      final alreadySeeded = _prefs?.getBool(_kSeededDefaultTvKey) ?? false;
      if (alreadySeeded ||
          _playlists.any(
            (p) =>
                p.sourceLocation.toLowerCase() ==
                defaultTvPlaylistUrl.toLowerCase(),
          )) {
        return;
      }
      await _prefs?.setBool(_kSeededDefaultTvKey, true);
      await addM3uFromUrls(
        rawUrlsInput: defaultTvPlaylistUrl,
        customName: 'TV Indonesia',
      );
    } catch (_) {
      // Allow retry next launch if offline on first launch
      await _prefs?.setBool(_kSeededDefaultTvKey, false);
    }
  }

  Future<void> _handleWidgetAction(String? action) async {
    if (action == null || action.isEmpty) return;
    if (action == 'com.musikm3u.player.WIDGET_PLAY_PAUSE') {
      await togglePlayPause();
    } else if (action == 'com.musikm3u.player.WIDGET_NEXT') {
      await playNext();
    } else if (action == 'com.musikm3u.player.WIDGET_PREV') {
      await playPrevious();
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
    final mkPlayer = _mkPlayer;
    if (mkPlayer != null) {
      _subscriptions.add(
        mkPlayer.stream.error.listen((error) {
          _isBuffering = false;
          _isPlaying = false;
          _syncHomeWidgets();
          _lastError = 'Gangguan pemutaran audio: $error';
          notifyListeners();
        }),
      );
      _subscriptions.add(
        mkPlayer.stream.playlist.listen((playlist) {
          final realIdx = _windowStart + playlist.index;
          if (realIdx >= 0 &&
              realIdx < _queue.length &&
              realIdx != _currentIndex) {
            _currentIndex = realIdx;
            _positionNotifier.value = Duration.zero;
            _bufferedPositionNotifier.value = Duration.zero;
            _duration = mkPlayer.state.duration;
            _recordTrackPlayed(_queue[realIdx]);
            _syncHomeWidgets();
            _maybePreloadNextNewTubeTrack();
            if (_crossfadeSeconds > 0 && _sleepEndTime == null) {
              _fadeInPlayerVolume(
                startVol: 0.25,
                durationSeconds: _crossfadeSeconds.clamp(1, 4),
              );
            }
            notifyListeners();
          }
        }),
      );
      _subscriptions.add(
        mkPlayer.stream.playing.listen((playing) {
          if (_isPlaying != playing) {
            _isPlaying = playing;
            _syncHomeWidgets();
            notifyListeners();
          }
        }),
      );
      _subscriptions.add(
        mkPlayer.stream.position.listen((pos) {
          _positionNotifier.value = pos;
          final active = currentTrack;
          if (_crossfadeSeconds > 0 &&
              _isPlaying &&
              _sleepEndTime == null &&
              _repeatMode != RepeatCycleMode.one &&
              _duration > Duration(seconds: _crossfadeSeconds + 2)) {
            final remainingMs = _duration.inMilliseconds - pos.inMilliseconds;
            final fadeWindowMs = _crossfadeSeconds * 1000;
            if (remainingMs > 0 && remainingMs <= fadeWindowMs) {
              final vol = (remainingMs / fadeWindowMs).clamp(0.15, 1.0);
              unawaited(_setPlayerVolume(vol));
            }
          }
          if (active != null &&
              DateTime.now().difference(_lastProgressPersist).inSeconds >= 5) {
            _lastProgressPersist = DateTime.now();
            _trackProgressSeconds[active.id] = pos.inSeconds;
            _syncHomeWidgets();
            unawaited(_persistProgressMap());
          }
        }),
      );
      _subscriptions.add(
        mkPlayer.stream.buffer.listen((buffered) {
          _bufferedPositionNotifier.value = buffered;
        }),
      );
      _subscriptions.add(
        mkPlayer.stream.duration.listen((dur) {
          if (_duration != dur) {
            _duration = dur;
            notifyListeners();
          }
        }),
      );
      _subscriptions.add(
        mkPlayer.stream.buffering.listen((buffering) {
          if (_isBuffering != buffering) {
            _isBuffering = buffering;
            notifyListeners();
          }
        }),
      );
      _subscriptions.add(
        mkPlayer.stream.completed.listen((completed) {
          if (completed && _repeatMode == RepeatCycleMode.off) {
            final pl = mkPlayer.state.playlist;
            if (pl.medias.isEmpty || pl.index >= pl.medias.length - 1) {
              _handleTrackCompleted();
            }
          }
        }),
      );
      return;
    }

    final player = _justAudioPlayer!;
    _subscriptions.add(
      player.playbackEventStream.listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _isBuffering = false;
          _isPlaying = false;
          _syncHomeWidgets();
          _lastError = 'Gangguan pemutaran audio: $error';
          notifyListeners();
        },
      ),
    );

    _subscriptions.add(
      player.currentIndexStream.listen((idx) {
        if (idx == null) return;
        final realIdx = _windowStart + idx;
        if (realIdx >= 0 &&
            realIdx < _queue.length &&
            realIdx != _currentIndex) {
          _currentIndex = realIdx;
          _positionNotifier.value = Duration.zero;
          _bufferedPositionNotifier.value = Duration.zero;
          _duration = player.duration ?? Duration.zero;
          _recordTrackPlayed(_queue[realIdx]);
          _syncHomeWidgets();
          _maybePreloadNextNewTubeTrack();
          if (_crossfadeSeconds > 0 && _sleepEndTime == null) {
            _fadeInPlayerVolume(
              startVol: 0.25,
              durationSeconds: _crossfadeSeconds.clamp(1, 4),
            );
          }
          notifyListeners();
        }
      }),
    );

    _subscriptions.add(
      player.playingStream.listen((playing) {
        if (_isPlaying != playing) {
          _isPlaying = playing;
          _syncHomeWidgets();
          notifyListeners();
        }
      }),
    );

    // High-frequency position updates ONLY notify `_positionNotifier` (not global ChangeNotifier!)
    _subscriptions.add(
      player.positionStream.listen((pos) {
        _positionNotifier.value = pos;
        final active = currentTrack;
        if (_crossfadeSeconds > 0 &&
            _isPlaying &&
            _sleepEndTime == null &&
            _repeatMode != RepeatCycleMode.one &&
            _duration > Duration(seconds: _crossfadeSeconds + 2)) {
          final remainingMs = _duration.inMilliseconds - pos.inMilliseconds;
          final fadeWindowMs = _crossfadeSeconds * 1000;
          if (remainingMs > 0 && remainingMs <= fadeWindowMs) {
            final vol = (remainingMs / fadeWindowMs).clamp(0.15, 1.0);
            unawaited(_setPlayerVolume(vol));
          }
        }
        if (active != null &&
            DateTime.now().difference(_lastProgressPersist).inSeconds >= 5) {
          _lastProgressPersist = DateTime.now();
          _trackProgressSeconds[active.id] = pos.inSeconds;
          _syncHomeWidgets();
          unawaited(_persistProgressMap());
        }
      }),
    );

    _subscriptions.add(
      player.bufferedPositionStream.listen((buffered) {
        _bufferedPositionNotifier.value = buffered;
      }),
    );

    _subscriptions.add(
      player.durationStream.listen((dur) {
        if (dur != null && _duration != dur) {
          _duration = dur;
          notifyListeners();
        }
      }),
    );

    _subscriptions.add(
      player.playerStateStream.listen((state) {
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
    try {
      final rawAutoSync =
          prefs.getStringList(_kAutoSyncYtPlaylistsKey) ?? const [];
      _autoSyncYouTubePlaylists = rawAutoSync
          .map((s) {
            final m = jsonDecode(s) as Map<String, dynamic>;
            return NewTubePlaylistItem(
              playlistId: m['playlistId']?.toString() ?? '',
              title: m['title']?.toString() ?? 'YouTube Playlist',
              author: m['author']?.toString() ?? 'YouTube',
              videoCountText: m['videoCountText']?.toString() ?? '',
              thumbnailUrl: m['thumbnailUrl']?.toString() ?? '',
            );
          })
          .where((p) => p.playlistId.isNotEmpty)
          .toList();
    } catch (_) {
      _autoSyncYouTubePlaylists = [];
    }
    _favoriteIds =
        Set<String>.from(prefs.getStringList(_kFavoritesKey) ?? const []);
    _alarmEnabled = prefs.getBool(_kAlarmEnabledKey) ?? false;
    _alarmHour = prefs.getInt(_kAlarmHourKey) ?? 6;
    _alarmMinute = prefs.getInt(_kAlarmMinuteKey) ?? 30;
    _crossfadeSeconds = prefs.getInt(_kCrossfadeSecKey) ?? 0;
    if (_alarmEnabled) {
      _startAlarmTicker();
    }
    _hasSeenOnboarding = prefs.getBool(_kOnboardingKey) ?? false;
    _deadTrackIds =
        Set<String>.from(prefs.getStringList(_kDeadLinksKey) ?? const []);
    _hideDeadLinks = prefs.getBool(_kHideDeadLinksKey) ?? true;
    _ytAutoCacheEnabled = prefs.getBool(_kYtAutoCacheEnabledKey) ?? true;
    _equalizerEnabled = prefs.getBool(_kEqEnabledKey) ?? false;
    _activeEqPreset = prefs.getString(_kEqPresetKey) ?? 'Flat';
    _bassBoostStrength = prefs.getDouble(_kBassBoostKey) ?? 0.0;
    _loudnessGainDb = prefs.getDouble(_kLoudnessDbKey) ?? 0.0;
    try {
      final rawEq = prefs.getStringList(_kEqGainsKey);
      if (rawEq != null && rawEq.length == 5) {
        _eqBandGains = rawEq.map((e) => double.tryParse(e) ?? 0.0).toList();
      }
    } catch (_) {}

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

      final offlineRoot = await _getYouTubeOfflineRootDir();
      _youTubeOfflineRootPath = offlineRoot.path;
      await _loadYouTubeOfflineMeta(offlineRoot);
      final scanDirs = <String>[
        ..._customDirectories,
        offlineRoot.path,
      ];

      final result = await DirectoryScannerService.scanDirectories(
        customDirectories: scanDirs,
        includeDefaultAndroidDirs: true,
      );
      _directoryGroups = _enrichScannedGroupsWithYouTubeMeta(
        result.directories,
        offlineRoot.path,
      );
      _discoveredM3uFiles = result.discoveredM3uFiles;
      _invalidateLibraryCache();
      unawaited(autoFetchMissingArtworkForTracks(allTracks, maxFetch: 24));
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

  static const String _kGithubM3uShasKey = 'github_m3u_shas_v1';
  static const String _kBackendM3uShasKey = 'backend_m3u_shas_v1';
  bool _isSyncingGithubM3u = false;
  String? _pendingGithubM3uNotice;
  DateTime? _lastGithubM3uSyncAt;
  String? _lastGithubM3uSyncError;

  bool get isSyncingGithubM3u => _isSyncingGithubM3u;
  String? get pendingGithubM3uNotice => _pendingGithubM3uNotice;
  DateTime? get lastGithubM3uSyncAt => _lastGithubM3uSyncAt;
  String? get lastGithubM3uSyncError => _lastGithubM3uSyncError;

  void clearGithubM3uNotice() {
    _pendingGithubM3uNotice = null;
  }

  static String _safeDecodeLower(String value) {
    try {
      return Uri.decodeFull(value).trim().toLowerCase();
    } catch (_) {
      return value.trim().toLowerCase();
    }
  }

  /// Checks `zusfan-ops/Musik-Player/m3u` on GitHub for new, updated, or deleted `.m3u` files
  /// and automatically updates TV/CCTV playlists + raises an in-app notification.
  Future<int> syncGithubM3uDirectory({
    bool showNoChangeNotice = false,
    http.Client? httpClient,
  }) async {
    if (_isSyncingGithubM3u) return 0;
    _isSyncingGithubM3u = true;
    notifyListeners();

    int changedCount = 0;
    try {
      final rawSaved = _prefs?.getString(_kGithubM3uShasKey);
      final Map<String, String> knownShas = {};
      if (rawSaved != null && rawSaved.isNotEmpty) {
        final decoded = jsonDecode(rawSaved);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.key is String && entry.value is String) {
              knownShas[entry.key as String] = entry.value as String;
            }
          }
        }
      }

      // Remove legacy hardcoded bundled/D:\m3u CCTV copies (keep TV Indonesia & user links)
      final beforeLegacyCount = _playlists.length;
      _playlists.removeWhere((pl) {
        final loc = pl.sourceLocation.toLowerCase();
        return loc.startsWith('asset://assets/m3u/') ||
            (pl.sourceType == M3uSourceType.file &&
                (loc.contains(r'\m3u\') || loc.contains('/m3u/')));
      });
      final bool legacyRemoved = _playlists.length != beforeLegacyCount;

      final remoteEntries =
          await GithubM3uSyncService.fetchRemoteEntries(client: httpClient);
      final remoteDecodedUrls =
          remoteEntries.map((e) => _safeDecodeLower(e.downloadUrl)).toSet();
      final remoteNamesLower =
          remoteEntries.map((e) => e.name.trim().toLowerCase()).toSet();

      final removedFileNames = knownShas.keys
          .where((k) => !remoteNamesLower.contains(k.trim().toLowerCase()))
          .toList();
      final removedDisplayNamesLower = removedFileNames
          .map(
            (name) => GithubM3uSyncService.formatPlaylistDisplayName(name)
                .toLowerCase(),
          )
          .toSet();
      knownShas.removeWhere(
        (k, _) => !remoteNamesLower.contains(k.trim().toLowerCase()),
      );

      final removedNames = <String>[];
      _playlists.removeWhere((pl) {
        final decodedLoc = _safeDecodeLower(pl.sourceLocation);
        final isGithubRepoM3u = decodedLoc.startsWith(
              'https://raw.githubusercontent.com/zusfan-ops/musik-player/',
            ) ||
            decodedLoc.startsWith(
              'https://github.com/zusfan-ops/musik-player/',
            );
        final shouldRemove = isGithubRepoM3u &&
            (!remoteDecodedUrls.contains(decodedLoc) ||
                removedDisplayNamesLower.contains(pl.name.trim().toLowerCase()));
        if (shouldRemove) {
          removedNames.add(pl.name);
        }
        return shouldRemove;
      });

      final changedEntries = GithubM3uSyncService.diffChangedEntries(
        remoteEntries: remoteEntries,
        knownShas: knownShas,
      );

      final addedNames = <String>[];
      final updatedNames = <String>[];

      for (final entry in changedEntries) {
        try {
          final bytes = await GithubM3uSyncService.downloadFileBytes(
            entry.downloadUrl,
            client: httpClient,
          );
          final displayName =
              GithubM3uSyncService.formatPlaylistDisplayName(entry.name);
          final existingIdx = _playlists.indexWhere(
            (pl) =>
                _safeDecodeLower(pl.sourceLocation) ==
                    _safeDecodeLower(entry.downloadUrl) ||
                pl.name.toLowerCase() == displayName.toLowerCase(),
          );
          final parsed = await M3uService.importFromBytes(
            bytes: bytes,
            displayFileName: entry.name,
            resolvedSourcePath: entry.downloadUrl,
            existingId: existingIdx >= 0 ? _playlists[existingIdx].id : null,
          );
          final playlist = M3uPlaylist(
            id: parsed.id,
            name: displayName,
            sourceType: M3uSourceType.url,
            sourceLocation: entry.downloadUrl,
            tracks: parsed.tracks,
            updatedAt: parsed.updatedAt,
            isEnabled: parsed.isEnabled,
          );
          if (existingIdx >= 0) {
            _playlists[existingIdx] = playlist;
            updatedNames.add(displayName);
          } else {
            _playlists.insert(0, playlist);
            addedNames.add(displayName);
          }
          knownShas[entry.name] = entry.sha;
          changedCount++;
        } catch (_) {
          // Skip failed file and keep others syncing
        }
      }

      // Also sync active M3U sources managed from the MediaCenter Backend
      final backendEntries =
          await GithubM3uSyncService.fetchBackendEntries(client: httpClient);
      if (backendEntries != null) {
        final rawBackendSaved = _prefs?.getString(_kBackendM3uShasKey);
        final Map<String, String> knownBackendShas = {};
        if (rawBackendSaved != null && rawBackendSaved.isNotEmpty) {
          final decoded = jsonDecode(rawBackendSaved);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              if (entry.key is String && entry.value is String) {
                knownBackendShas[entry.key as String] = entry.value as String;
              }
            }
          }
        }

        final backendUrlsLower =
            backendEntries.map((e) => _safeDecodeLower(e.downloadUrl)).toSet();
        final backendNamesLower =
            backendEntries.map((e) => e.name.trim().toLowerCase()).toSet();
        final removedBackendKeys = knownBackendShas.keys
            .where((k) => !backendNamesLower.contains(k.trim().toLowerCase()))
            .toList();
        knownBackendShas.removeWhere(
          (k, _) => !backendNamesLower.contains(k.trim().toLowerCase()),
        );
        final removedBackendLower =
            removedBackendKeys.map((k) => k.trim().toLowerCase()).toSet();

        _playlists.removeWhere((pl) {
          final decodedLoc = _safeDecodeLower(pl.sourceLocation);
          final isBackendM3u = decodedLoc.contains('/api/v1/m3u-sources/') ||
              removedBackendLower.contains(pl.name.trim().toLowerCase());
          final shouldRemove = isBackendM3u &&
              (!backendUrlsLower.contains(decodedLoc) ||
                  removedBackendLower.contains(pl.name.trim().toLowerCase()));
          if (shouldRemove) {
            removedNames.add(pl.name);
          }
          return shouldRemove;
        });

        for (final entry in backendEntries) {
          if (knownBackendShas[entry.name] == entry.sha) continue;
          try {
            final bytes = await GithubM3uSyncService.downloadFileBytes(
              entry.downloadUrl,
              client: httpClient,
            );
            final existingIdx = _playlists.indexWhere(
              (pl) =>
                  _safeDecodeLower(pl.sourceLocation) ==
                      _safeDecodeLower(entry.downloadUrl) ||
                  pl.name.toLowerCase() == entry.name.toLowerCase(),
            );
            final parsed = await M3uService.importFromBytes(
              bytes: bytes,
              displayFileName: entry.name,
              resolvedSourcePath: entry.downloadUrl,
              existingId: existingIdx >= 0 ? _playlists[existingIdx].id : null,
            );
            final playlist = M3uPlaylist(
              id: parsed.id,
              name: entry.name,
              category: entry.category ?? 'TV & CCTV',
              sourceType: M3uSourceType.url,
              sourceLocation: entry.downloadUrl,
              tracks: parsed.tracks,
              updatedAt: parsed.updatedAt,
              isEnabled: parsed.isEnabled,
            );
            if (existingIdx >= 0) {
              _playlists[existingIdx] = playlist;
              updatedNames.add(entry.name);
            } else {
              _playlists.insert(0, playlist);
              addedNames.add(entry.name);
            }
            knownBackendShas[entry.name] = entry.sha;
            changedCount++;
          } catch (_) {}
        }

        await _prefs?.setString(
          _kBackendM3uShasKey,
          jsonEncode(knownBackendShas),
        );
      }

      final bool hasPlaylistMutations =
          changedCount > 0 || removedNames.isNotEmpty || legacyRemoved;
      if (hasPlaylistMutations || removedFileNames.isNotEmpty) {
        await _prefs?.setString(_kGithubM3uShasKey, jsonEncode(knownShas));
      }
      if (hasPlaylistMutations) {
        _invalidateLibraryCache();
        await _persistPlaylists();

        final parts = <String>[];
        if (addedNames.isNotEmpty) {
          parts.add('${addedNames.length} baru (${addedNames.join(', ')})');
        }
        if (updatedNames.isNotEmpty) {
          parts.add(
            '${updatedNames.length} diperbarui (${updatedNames.join(', ')})',
          );
        }
        if (removedNames.isNotEmpty) {
          parts.add(
            '${removedNames.length} dihapus (${removedNames.join(', ')})',
          );
        }
        if (parts.isNotEmpty) {
          _pendingGithubM3uNotice =
              'Update list TV/CCTV dari GitHub: ${parts.join(' • ')}';
        }
      } else if (showNoChangeNotice) {
        _pendingGithubM3uNotice = 'Daftar TV & CCTV GitHub sudah paling baru.';
      }
      _lastGithubM3uSyncAt = DateTime.now();
      _lastGithubM3uSyncError = null;
      return changedCount + removedNames.length;
    } catch (e) {
      _lastGithubM3uSyncError = 'Gagal sinkronisasi M3U GitHub';
      return 0;
    } finally {
      _isSyncingGithubM3u = false;
      notifyListeners();
    }
  }

  M3uPlaylist? findDuplicatePlaylistByUrl(String rawUrl) {
    final target = _safeDecodeLower(rawUrl);
    if (target.isEmpty) return null;
    for (final pl in _playlists) {
      if (pl.isUrlSource && _safeDecodeLower(pl.sourceLocation) == target) {
        return pl;
      }
    }
    return null;
  }

  Future<void> setPlaylistCategory(String playlistId, String category) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final clean = category.trim().isEmpty ? 'Umum' : category.trim();
    _playlists[idx] = _playlists[idx].copyWith(category: clean);
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> reorderPlaylists(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _playlists.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= _playlists.length || target == oldIndex) return;
    final item = _playlists.removeAt(oldIndex);
    _playlists.insert(target, item);
    await _persistPlaylists();
    notifyListeners();
  }

  String exportBackupJson() {
    return ConfigBackupService.buildBackupJson(
      playlists: _playlists,
      favoriteIds: _favoriteIds,
      youtubePlaylists: _autoSyncYouTubePlaylists,
      settings: {
        'ytAutoCacheEnabled': _ytAutoCacheEnabled,
        'hideDeadLinks': _hideDeadLinks,
        'equalizerEnabled': _equalizerEnabled,
        'activeEqPreset': _activeEqPreset,
        'bassBoostStrength': _bassBoostStrength,
        'loudnessGainDb': _loudnessGainDb,
        'eqBandGains': _eqBandGains,
        'crossfadeSeconds': _crossfadeSeconds,
      },
    );
  }

  Future<({int addedPlaylists, int restoredFavorites})> restoreBackup(
    BackupPreview preview, {
    required bool replaceExisting,
  }) async {
    int addedPlaylists = 0;
    if (replaceExisting) {
      _playlists = List<M3uPlaylist>.from(preview.playlists);
      addedPlaylists = _playlists.length;
    } else {
      final existingUrls = _playlists
          .where((p) => p.isUrlSource)
          .map((p) => _safeDecodeLower(p.sourceLocation))
          .toSet();
      final existingIds = _playlists.map((p) => p.id).toSet();
      for (final pl in preview.playlists) {
        final dupUrl = pl.isUrlSource &&
            existingUrls.contains(_safeDecodeLower(pl.sourceLocation));
        if (dupUrl || existingIds.contains(pl.id)) continue;
        _playlists.add(pl);
        if (pl.isUrlSource) {
          existingUrls.add(_safeDecodeLower(pl.sourceLocation));
        }
        existingIds.add(pl.id);
        addedPlaylists++;
      }
    }

    int restoredFavorites = 0;
    if (replaceExisting) {
      _favoriteIds = preview.favoriteIds.toSet();
      restoredFavorites = _favoriteIds.length;
    } else {
      for (final id in preview.favoriteIds) {
        if (_favoriteIds.add(id)) restoredFavorites++;
      }
    }

    if (replaceExisting) {
      _autoSyncYouTubePlaylists =
          List<NewTubePlaylistItem>.from(preview.youtubePlaylists);
    } else {
      final existingYt =
          _autoSyncYouTubePlaylists.map((e) => e.playlistId).toSet();
      for (final yt in preview.youtubePlaylists) {
        if (existingYt.add(yt.playlistId)) {
          _autoSyncYouTubePlaylists.add(yt);
        }
      }
    }

    final s = preview.settings;
    if (s['ytAutoCacheEnabled'] is bool) {
      _ytAutoCacheEnabled = s['ytAutoCacheEnabled'] as bool;
      await _prefs?.setBool(_kYtAutoCacheEnabledKey, _ytAutoCacheEnabled);
    }
    if (s['hideDeadLinks'] is bool) {
      _hideDeadLinks = s['hideDeadLinks'] as bool;
      await _prefs?.setBool(_kHideDeadLinksKey, _hideDeadLinks);
    }
    if (s['equalizerEnabled'] is bool) {
      _equalizerEnabled = s['equalizerEnabled'] as bool;
      await _prefs?.setBool(_kEqEnabledKey, _equalizerEnabled);
    }
    if (s['activeEqPreset'] is String) {
      _activeEqPreset = s['activeEqPreset'] as String;
      await _prefs?.setString(_kEqPresetKey, _activeEqPreset);
    }
    if (s['bassBoostStrength'] is num) {
      _bassBoostStrength = (s['bassBoostStrength'] as num).toDouble().clamp(0.0, 1.0);
      await _prefs?.setDouble(_kBassBoostKey, _bassBoostStrength);
    }
    if (s['loudnessGainDb'] is num) {
      _loudnessGainDb = (s['loudnessGainDb'] as num).toDouble().clamp(0.0, 15.0);
      await _prefs?.setDouble(_kLoudnessDbKey, _loudnessGainDb);
    }
    if (s['eqBandGains'] is List && (s['eqBandGains'] as List).length == 5) {
      _eqBandGains = (s['eqBandGains'] as List)
          .map((e) => e is num ? e.toDouble().clamp(-15.0, 15.0) : 0.0)
          .toList();
      await _prefs?.setStringList(
        _kEqGainsKey,
        _eqBandGains.map((e) => e.toString()).toList(),
      );
    }
    if (s['crossfadeSeconds'] is num) {
      _crossfadeSeconds = (s['crossfadeSeconds'] as num).toInt().clamp(0, 12);
      await _prefs?.setInt(_kCrossfadeSecKey, _crossfadeSeconds);
    }
    unawaited(_syncAudioEffectsToPipeline());

    await _prefs?.setStringList(_kFavoritesKey, _favoriteIds.toList());
    await _prefs?.setStringList(
      _kAutoSyncYtPlaylistsKey,
      _autoSyncYouTubePlaylists
          .map(
            (yt) => jsonEncode({
              'playlistId': yt.playlistId,
              'title': yt.title,
              'author': yt.author,
              'videoCountText': yt.videoCountText,
              'thumbnailUrl': yt.thumbnailUrl,
            }),
          )
          .toList(),
    );
    _invalidateLibraryCache();
    await _persistPlaylists();
    notifyListeners();

    return (
      addedPlaylists: addedPlaylists,
      restoredFavorites: restoredFavorites,
    );
  }

  /// Imports every `.m3u` / `.m3u8` file found inside [dirPath] as a TV playlist.
  /// Existing playlists with the same path or same name are refreshed in place.
  Future<int> importM3uFolder(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;

    _isImportingM3u = true;
    _lastError = null;
    notifyListeners();

    int imported = 0;
    try {
      final files = <File>[];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (ext == '.m3u' || ext == '.m3u8') files.add(entity);
      }
      files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

      for (final file in files) {
        try {
          final name = p.basenameWithoutExtension(file.path).toLowerCase();
          final existingIdx = _playlists.indexWhere(
            (pl) =>
                pl.sourceType == M3uSourceType.file &&
                (p.normalize(pl.sourceLocation).toLowerCase() ==
                        p.normalize(file.path).toLowerCase() ||
                    pl.name.toLowerCase() == name),
          );
          final playlist = await M3uService.importFromFile(
            filePath: file.path,
            additionalSearchDirs: _knownLocalDirectories,
            existingId: existingIdx >= 0 ? _playlists[existingIdx].id : null,
          );
          if (existingIdx >= 0) {
            _playlists[existingIdx] = playlist;
          } else {
            _playlists.insert(0, playlist);
          }
          imported++;
        } catch (e) {
          _lastError = 'Gagal mengimpor ${p.basename(file.path)}: $e';
        }
      }

      final normalizedDir = p.normalize(dirPath).toLowerCase();
      final currentPaths =
          files.map((f) => p.normalize(f.path).toLowerCase()).toSet();
      _playlists.removeWhere((pl) {
        if (pl.sourceType != M3uSourceType.file) return false;
        final src = p.normalize(pl.sourceLocation).toLowerCase();
        return (src.startsWith('$normalizedDir${p.separator}') ||
                src.startsWith('$normalizedDir/')) &&
            !currentPaths.contains(src);
      });

      _invalidateLibraryCache();
      await _persistPlaylists();
      return imported;
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

  // ==================== YOUTUBE MUSIC & PLAYLIST OFFLINE DOWNLOAD ====================

  static final RegExp _ytFilenameIdRegex = RegExp(r'\[([a-zA-Z0-9_-]{11})\]');

  @visibleForTesting
  Directory? offlineRootOverride;

  Future<Directory> _getYouTubeOfflineRootDir() async {
    if (offlineRootOverride != null) return offlineRootOverride!;
    final docDir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docDir.path, 'MediaCenterOffline'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<void> _loadYouTubeOfflineMeta(Directory offlineRoot) async {
    try {
      final metaFile = File(p.join(offlineRoot.path, 'offline_meta.json'));
      if (!await metaFile.exists()) return;
      final raw = await metaFile.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _ytOfflineMeta = decoded.map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        );
      }
    } catch (_) {}
  }

  Future<void> _saveYouTubeOfflineMeta(Directory offlineRoot) async {
    try {
      final metaFile = File(p.join(offlineRoot.path, 'offline_meta.json'));
      await metaFile.writeAsString(jsonEncode(_ytOfflineMeta));
    } catch (_) {}
  }

  List<MusicDirectoryGroup> _enrichScannedGroupsWithYouTubeMeta(
    List<MusicDirectoryGroup> groups,
    String offlineRootPath,
  ) {
    _downloadedYouTubeIds.clear();
    final normRoot = p.normalize(offlineRootPath).toLowerCase();
    return groups.map((group) {
      final updatedTracks = group.tracks.map((t) {
        final match = _ytFilenameIdRegex.firstMatch(p.basename(t.pathOrUrl));
        final videoId = match?.group(1);
        final isUnderOfflineRoot =
            p.normalize(t.directoryPath).toLowerCase().startsWith(normRoot);
        if (videoId != null && isUnderOfflineRoot) {
          _downloadedYouTubeIds.add(videoId);
        }
        final meta = videoId != null ? _ytOfflineMeta[videoId] : null;
        if (meta != null) {
          final localArt = meta['localArtworkPath'] as String?;
          final resolvedArt = (localArt != null &&
                  localArt.isNotEmpty &&
                  File(localArt).existsSync())
              ? localArt
              : (meta['artworkUrl'] as String?);
          return t.copyWith(
            title: (meta['title'] as String?) ?? t.title,
            artist: (meta['artist'] as String?) ?? t.artist,
            artworkUrl: resolvedArt ?? t.artworkUrl,
            durationSeconds:
                (meta['durationSeconds'] as num?)?.toInt() ?? t.durationSeconds,
          );
        }
        final cachedArt = ArtworkService.getCachedLocalPath(t.id);
        if (cachedArt != null) {
          return t.copyWith(artworkUrl: cachedArt);
        }
        return t;
      }).toList();
      return MusicDirectoryGroup(
        directoryPath: group.directoryPath,
        directoryName: group.directoryName,
        parentPath: group.parentPath,
        tracks: updatedTracks,
        isCustomRoot: group.isCustomRoot,
      );
    }).toList();
  }

  Future<void> _recordYouTubeMetaWithArtwork(
    NewTubeItem item,
    Directory offlineRoot,
  ) async {
    final artFile = File(p.join(offlineRoot.path, '.art', '${item.videoId}.jpg'));
    final localArtPath = await NewTubeService.downloadArtworkToFile(
      item.thumbnailUrl,
      artFile,
    );
    _ytOfflineMeta[item.videoId] = {
      'title': item.title,
      'artist': item.author,
      'artworkUrl': item.thumbnailUrl,
      'localArtworkPath': ?localArtPath,
      if (item.duration != null) 'durationSeconds': item.duration!.inSeconds,
    };
  }

  void cancelYouTubeDownload() {
    _cancelYouTubeDownloadRequested = true;
    notifyListeners();
  }

  /// Downloads a single YouTube track into the unified `Lagu Offline` directory.
  Future<bool> downloadNewTubeTrack(NewTubeItem item) async {
    if (_downloadingYouTubeIds.contains(item.videoId)) return false;
    _downloadingYouTubeIds.add(item.videoId);
    _cancelYouTubeDownloadRequested = false;
    _ytDownloadLabel = item.title;
    _ytDownloadProgress = 0.0;
    notifyListeners();

    try {
      final offlineRoot = await _getYouTubeOfflineRootDir();
      _youTubeOfflineRootPath = offlineRoot.path;
      await _loadYouTubeOfflineMeta(offlineRoot);
      final singleDir = Directory(p.join(offlineRoot.path, 'Lagu Offline'));

      await NewTubeService.downloadAudioToDirectory(
        item: item,
        targetDir: singleDir,
        isCancelled: () => _cancelYouTubeDownloadRequested,
        onProgress: (prog) {
          _ytDownloadProgress = prog;
          notifyListeners();
        },
      );

      await _recordYouTubeMetaWithArtwork(item, offlineRoot);
      _downloadedYouTubeIds.add(item.videoId);
      await _saveYouTubeOfflineMeta(offlineRoot);
      await refreshPermissionsAndScan(requestInteractive: false);
      return true;
    } catch (e) {
      _lastError = 'Gagal mengunduh "${item.title}": $e';
      return false;
    } finally {
      _downloadingYouTubeIds.remove(item.videoId);
      if (_downloadingYouTubeIds.isEmpty && !_isDownloadingYouTubePlaylist) {
        _ytDownloadLabel = null;
        _ytDownloadProgress = 0.0;
      }
      notifyListeners();
    }
  }

  /// Downloads an entire YouTube playlist into a directory named after [playlist.title].
  Future<int> downloadNewTubePlaylist(
    NewTubePlaylistItem playlist, [
    List<NewTubeItem>? preloadedItems,
  ]) async {
    if (_isDownloadingYouTubePlaylist) return 0;
    _isDownloadingYouTubePlaylist = true;
    _cancelYouTubeDownloadRequested = false;
    _ytDownloadLabel = 'Memuat playlist ${playlist.title}...';
    _ytDownloadProgress = 0.0;
    notifyListeners();

    int successCount = 0;
    try {
      final items = (preloadedItems != null && preloadedItems.isNotEmpty)
          ? preloadedItems
          : await NewTubeService.fetchPlaylistVideos(playlist.playlistId);

      if (items.isEmpty) {
        _lastError = 'Playlist "${playlist.title}" tidak memiliki lagu yang dapat diunduh.';
        return 0;
      }

      final offlineRoot = await _getYouTubeOfflineRootDir();
      _youTubeOfflineRootPath = offlineRoot.path;
      await _loadYouTubeOfflineMeta(offlineRoot);
      final folderName = NewTubeService.sanitizeFileName(
        playlist.title,
        fallback: 'YouTube Playlist',
      );
      final playlistDir = Directory(p.join(offlineRoot.path, folderName));

      Object? lastTrackErr;
      for (int i = 0; i < items.length; i++) {
        if (_cancelYouTubeDownloadRequested) break;
        final item = items[i];
        _downloadingYouTubeIds.add(item.videoId);
        _ytDownloadLabel = '${playlist.title} (${i + 1}/${items.length})';
        _ytDownloadProgress = i / items.length;
        notifyListeners();

        try {
          await NewTubeService.downloadAudioToDirectory(
            item: item,
            targetDir: playlistDir,
            isCancelled: () => _cancelYouTubeDownloadRequested,
            onProgress: (trackProg) {
              _ytDownloadProgress =
                  ((i + trackProg) / items.length).clamp(0.0, 1.0);
              notifyListeners();
            },
          );
          await _recordYouTubeMetaWithArtwork(item, offlineRoot);
          _downloadedYouTubeIds.add(item.videoId);
          successCount++;
        } catch (e) {
          lastTrackErr = e;
          // Continue with remaining tracks in playlist
        } finally {
          _downloadingYouTubeIds.remove(item.videoId);
        }
      }

      if (successCount == 0 && lastTrackErr != null) {
        _lastError =
            'Gagal mengunduh playlist "${playlist.title}": $lastTrackErr';
      }

      await _saveYouTubeOfflineMeta(offlineRoot);
      await refreshPermissionsAndScan(requestInteractive: false);
      return successCount;
    } catch (e) {
      _lastError = 'Gagal mengunduh playlist "${playlist.title}": $e';
      return successCount;
    } finally {
      _isDownloadingYouTubePlaylist = false;
      _cancelYouTubeDownloadRequested = false;
      _ytDownloadLabel = null;
      _ytDownloadProgress = 0.0;
      notifyListeners();
    }
  }

  Future<void> _persistAutoSyncYouTubePlaylists() async {
    final encoded = _autoSyncYouTubePlaylists
        .map((pl) => jsonEncode({
              'playlistId': pl.playlistId,
              'title': pl.title,
              'author': pl.author,
              'videoCountText': pl.videoCountText,
              'thumbnailUrl': pl.thumbnailUrl,
            }))
        .toList();
    await _prefs?.setStringList(_kAutoSyncYtPlaylistsKey, encoded);
  }

  Future<void> toggleAutoSyncYouTubePlaylist(
    NewTubePlaylistItem playlist,
  ) async {
    final idx = _autoSyncYouTubePlaylists
        .indexWhere((p) => p.playlistId == playlist.playlistId);
    if (idx >= 0) {
      _autoSyncYouTubePlaylists.removeAt(idx);
      await _persistAutoSyncYouTubePlaylists();
      notifyListeners();
    } else {
      _autoSyncYouTubePlaylists.add(playlist);
      await _persistAutoSyncYouTubePlaylists();
      notifyListeners();
      if (!_isDownloadingYouTubePlaylist) {
        unawaited(downloadNewTubePlaylist(playlist));
      }
    }
  }

  Future<int> syncAllAutoSyncYouTubePlaylists() async {
    if (_autoSyncYouTubePlaylists.isEmpty) return 0;
    int totalSynced = 0;
    for (final pl in List<NewTubePlaylistItem>.from(_autoSyncYouTubePlaylists)) {
      if (_cancelYouTubeDownloadRequested) break;
      totalSynced += await downloadNewTubePlaylist(pl);
    }
    return totalSynced;
  }

  /// Returns storage size and file counts for `MediaCenterOffline` folders.
  Future<({
    int totalBytes,
    int fileCount,
    List<({String name, String path, int fileCount, int totalBytes})> folders,
  })> getOfflineStorageSummary() async {
    final offlineRoot = await _getYouTubeOfflineRootDir();
    if (!await offlineRoot.exists()) {
      return (
        totalBytes: 0,
        fileCount: 0,
        folders: <({String name, String path, int fileCount, int totalBytes})>[],
      );
    }

    int totalBytes = 0;
    int totalFiles = 0;
    final List<({String name, String path, int fileCount, int totalBytes})>
        folders = [];

    await for (final entity in offlineRoot.list(followLinks: false)) {
      if (entity is! Directory) continue;
      int folderBytes = 0;
      int folderFiles = 0;
      try {
        await for (final sub in entity.list(recursive: true, followLinks: false)) {
          if (sub is File && !p.basename(sub.path).endsWith('.json')) {
            folderBytes += await sub.length();
            folderFiles++;
          }
        }
      } catch (_) {}
      if (folderFiles > 0 || folderBytes > 0) {
        totalBytes += folderBytes;
        totalFiles += folderFiles;
        folders.add((
          name: p.basename(entity.path),
          path: entity.path,
          fileCount: folderFiles,
          totalBytes: folderBytes,
        ));
      }
    }

    folders.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return (totalBytes: totalBytes, fileCount: totalFiles, folders: folders);
  }

  Future<void> deleteOfflineFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await refreshPermissionsAndScan(requestInteractive: false);
  }

  Future<void> clearAllYouTubeOfflineCache() async {
    final offlineRoot = await _getYouTubeOfflineRootDir();
    if (await offlineRoot.exists()) {
      await offlineRoot.delete(recursive: true);
    }
    _ytOfflineMeta.clear();
    _downloadedYouTubeIds.clear();
    await refreshPermissionsAndScan(requestInteractive: false);
  }

  bool isYouTubeOfflineTrack(TrackItem track) {
    final root = _youTubeOfflineRootPath;
    if (root == null || root.isEmpty) return false;
    return p
        .normalize(track.directoryPath)
        .toLowerCase()
        .startsWith(p.normalize(root).toLowerCase());
  }

  Future<bool> deleteDownloadedTrack(TrackItem track) async {
    try {
      final f = File(track.playableSource);
      if (await f.exists()) {
        await f.delete();
      }
      final match = _ytFilenameIdRegex.firstMatch(p.basename(f.path));
      final videoId = match?.group(1);
      if (videoId != null) {
        _downloadedYouTubeIds.remove(videoId);
        _ytOfflineMeta.remove(videoId);
        final offlineRoot = await _getYouTubeOfflineRootDir();
        final artFile = File(p.join(offlineRoot.path, '.art', '$videoId.jpg'));
        if (await artFile.exists()) {
          await artFile.delete();
        }
        await _saveYouTubeOfflineMeta(offlineRoot);
      }
      await refreshPermissionsAndScan(requestInteractive: false);
      return true;
    } catch (e) {
      _lastError = 'Gagal menghapus file unduhan: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteDownloadedYouTubeByVideoId(String videoId) async {
    try {
      final offlineRoot = await _getYouTubeOfflineRootDir();
      if (await offlineRoot.exists()) {
        await for (final entity
            in offlineRoot.list(recursive: true, followLinks: false)) {
          if (entity is File &&
              p.basename(entity.path).contains('[$videoId]')) {
            await entity.delete();
          }
        }
      }
      _downloadedYouTubeIds.remove(videoId);
      _ytOfflineMeta.remove(videoId);
      await _saveYouTubeOfflineMeta(offlineRoot);
      await refreshPermissionsAndScan(requestInteractive: false);
      return true;
    } catch (e) {
      _lastError = 'Gagal menghapus lagu YouTube: $e';
      notifyListeners();
      return false;
    }
  }

  /// Automatically searches and caches album/track artwork for directory tracks missing artwork.
  Future<void> autoFetchMissingArtworkForTracks(
    List<TrackItem> tracks, {
    int maxFetch = 24,
  }) async {
    if (tracks.isEmpty) return;
    final updatedMap = await ArtworkService.enrichTracksBatch(
      tracks,
      maxFetch: maxFetch,
    );
    if (updatedMap.isEmpty) return;

    bool anyChanged = false;
    _directoryGroups = _directoryGroups.map((group) {
      bool groupChanged = false;
      final newTracks = group.tracks.map((t) {
        final artPath = updatedMap[t.id];
        if (artPath != null && artPath != t.artworkUrl) {
          groupChanged = true;
          anyChanged = true;
          return t.copyWith(artworkUrl: artPath);
        }
        return t;
      }).toList();
      if (!groupChanged) return group;
      return MusicDirectoryGroup(
        directoryPath: group.directoryPath,
        directoryName: group.directoryName,
        parentPath: group.parentPath,
        tracks: newTracks,
        isCustomRoot: group.isCustomRoot,
      );
    }).toList();

    if (anyChanged) {
      _invalidateLibraryCache();
      notifyListeners();
    }
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

  bool _notificationPermissionChecked = false;

  Future<void> _ensureNotificationPermissionOnce() async {
    if (!Platform.isAndroid || _notificationPermissionChecked) return;
    _notificationPermissionChecked = true;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Safe fallback in test or unsupported environments
    }
  }

  LoopMode _toJustAudioLoopMode(RepeatCycleMode mode) {
    switch (mode) {
      case RepeatCycleMode.off:
        return LoopMode.off;
      case RepeatCycleMode.all:
        return LoopMode.all;
      case RepeatCycleMode.one:
        return LoopMode.one;
    }
  }

  Future<void> _prepareDefaultArtworkUri() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final artFile = File(p.join(supportDir.path, 'default_lockscreen_art.png'));
      if (!await artFile.exists()) {
        final data = await rootBundle.load('assets/logo2.png');
        await artFile.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      _defaultArtUri = Uri.file(artFile.path);
    } catch (_) {
      // Safe fallback in test or unsupported environments
    }
  }

  AudioSource _buildAudioSource(TrackItem track) {
    final mediaTag = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.directoryName,
      duration: track.durationSeconds != null && track.durationSeconds! > 0
          ? Duration(seconds: track.durationSeconds!)
          : null,
      artUri: track.hasLocalArtwork
          ? Uri.file(track.artworkUrl!)
          : (track.hasValidNetworkArtwork
              ? Uri.tryParse(track.artworkUrl!)
              : _defaultArtUri),
    );

    if (track.isLocalFile) {
      if (track.playableSource.startsWith('content://')) {
        return AudioSource.uri(Uri.parse(track.playableSource), tag: mediaTag);
      }
      return AudioSource.file(track.playableSource, tag: mediaTag);
    }

    if (track.playsFromLocalFile) {
      final filePath = track.playableSource;
      if (filePath.startsWith('content://')) {
        return AudioSource.uri(Uri.parse(filePath), tag: mediaTag);
      }
      if (File(filePath).existsSync()) {
        return AudioSource.file(filePath, tag: mediaTag);
      }
      return AudioSource.uri(
        Uri.parse(track.pathOrUrl),
        headers: track.httpHeaders,
        tag: mediaTag,
      );
    }

    return AudioSource.uri(
      Uri.parse(track.playableSource),
      headers: track.httpHeaders,
      tag: mediaTag,
    );
  }

  mk.Media _buildMediaKitMedia(TrackItem track) {
    return mk.Media(
      track.playableSource,
      httpHeaders: track.httpHeaders,
    );
  }

  Future<void> _setPlayerVolume(double vol) async {
    final clamped = vol.clamp(0.0, 1.0);
    final mkPlayer = _mkPlayer;
    if (mkPlayer != null) {
      await mkPlayer.setVolume(clamped * 100.0);
    } else {
      await _justAudioPlayer?.setVolume(clamped);
    }
  }

  mk.PlaylistMode _toMediaKitPlaylistMode(RepeatCycleMode mode) {
    switch (mode) {
      case RepeatCycleMode.off:
        return mk.PlaylistMode.none;
      case RepeatCycleMode.all:
        return mk.PlaylistMode.loop;
      case RepeatCycleMode.one:
        return mk.PlaylistMode.single;
    }
  }

  Future<void> playTrackList(
    List<TrackItem> tracks, {
    int initialIndex = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;

    _newTubeSessionToken++;
    _pendingNewTubeItems = const [];
    _queue = List<TrackItem>.from(tracks);
    _shuffleEnabled = shuffle;

    int targetIndex = initialIndex.clamp(0, _queue.length - 1);
    if (shuffle && initialIndex == 0 && _queue.length > 1) {
      targetIndex = _random.nextInt(_queue.length);
    }

    await _setQueueAndPlay(targetIndex);
  }

  Future<void> playSingleTrack(TrackItem track) async {
    await playTrackList([track], initialIndex: 0);
  }

  bool get ytAutoCacheEnabled => _ytAutoCacheEnabled;

  Future<void> setYtAutoCacheEnabled(bool enabled) async {
    _ytAutoCacheEnabled = enabled;
    await _prefs?.setBool(_kYtAutoCacheEnabledKey, enabled);
    notifyListeners();
  }

  /// Plays a NewTube search/list as a continuous queue with lazy background
  /// resolution of upcoming tracks so Next & Auto-Next work on lockscreen too.
  Future<bool> playNewTubePlaylist(
    List<NewTubeItem> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) return false;
    final startIdx = initialIndex.clamp(0, items.length - 1);
    final token = ++_newTubeSessionToken;

    final firstItem = items[startIdx];
    final firstTrack = await resolveNewTubeAudioTrack(firstItem);
    if (firstTrack == null || token != _newTubeSessionToken) {
      return false;
    }

    _pendingNewTubeItems = items.sublist(startIdx + 1);
    _queue = [firstTrack];
    _shuffleEnabled = false;
    await _setQueueAndPlay(0);
    if (token != _newTubeSessionToken) return false;

    // Preload the next 2 tracks in background so hasNext becomes true immediately
    unawaited(_preloadNewTubeTracks(token, count: 2));
    return true;
  }

  static String? _sanitizeVideoId(String videoId) {
    final trimmed = videoId.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }

  Future<Directory> _getYouTubeStreamCacheDir() async {
    final offlineRoot = await _getYouTubeOfflineRootDir();
    _youTubeOfflineRootPath = offlineRoot.path;
    return Directory(p.join(offlineRoot.path, '.stream_cache'));
  }

  /// Checks local `.stream_cache` and downloaded YouTube offline folders for [videoId].
  /// Returns a local [File] if present (> 1 KB) and updates its modified timestamp for LRU.
  Future<File?> findCachedYouTubeAudioFile(String videoId) async {
    final safeId = _sanitizeVideoId(videoId);
    if (safeId == null) return null;

    final cacheDir = await _getYouTubeStreamCacheDir();
    if (await cacheDir.exists()) {
      for (final ext in const ['m4a', 'opus', 'mp3', 'aac']) {
        final candidate = File(p.join(cacheDir.path, '$safeId.$ext'));
        if (await candidate.exists() && await candidate.length() > 1024) {
          try {
            await candidate.setLastModified(DateTime.now());
          } catch (_) {}
          return candidate;
        }
      }
    }

    final offlineRoot = await _getYouTubeOfflineRootDir();
    if (await offlineRoot.exists()) {
      final token = '[$safeId]';
      try {
        await for (final entity
            in offlineRoot.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          if (name.endsWith('.part') || name.endsWith('.json')) continue;
          if (name.contains(token) && await entity.length() > 1024) {
            return entity;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Resolves a YouTube audio track using Cache-First playback to save mobile data,
  /// and optionally caches the audio-only stream in the background when online.
  Future<TrackItem?> resolveNewTubeAudioTrack(
    NewTubeItem item, {
    bool triggerAutoCache = true,
  }) async {
    final cachedFile = await findCachedYouTubeAudioFile(item.videoId);
    if (cachedFile != null) {
      final meta = _ytOfflineMeta[item.videoId];
      final localArt = meta?['localArtworkPath']?.toString();
      return TrackItem(
        id: 'yt_cached_${item.videoId}',
        title: item.title,
        artist: item.author,
        album: 'YouTube Cache Offline',
        sourceType: TrackSourceType.localFile,
        pathOrUrl: cachedFile.path,
        offlineCachePath: cachedFile.path,
        localFileAvailable: true,
        directoryPath: p.dirname(cachedFile.path),
        directoryName: 'YouTube Cache Offline',
        durationSeconds: item.duration?.inSeconds,
        artworkUrl: (localArt != null && localArt.isNotEmpty)
            ? localArt
            : item.thumbnailUrl,
        isVideo: false,
      );
    }

    final audio = await NewTubeService.resolveAudioStream(item.videoId);
    if (audio != null && audio.url.isNotEmpty) {
      if (triggerAutoCache && _ytAutoCacheEnabled) {
        unawaited(
          _cacheYouTubeAudioInBackground(
            item: item,
            streamUrl: audio.url,
            headers: audio.headers,
          ),
        );
      }
      return item.toTrackItem(
        streamUrl: audio.url,
        httpHeaders: audio.headers,
        asVideo: false,
      );
    }
    final muxed = await NewTubeService.resolveVideoStream(item.videoId);
    if (muxed != null && muxed.url.isNotEmpty) {
      return item.toTrackItem(
        streamUrl: muxed.url,
        httpHeaders: muxed.headers,
        asVideo: false,
      );
    }
    return null;
  }

  Future<void> _cacheYouTubeAudioInBackground({
    required NewTubeItem item,
    required String streamUrl,
    required Map<String, String> headers,
    http.Client? client,
  }) async {
    final safeId = _sanitizeVideoId(item.videoId);
    if (safeId == null || _cachingYouTubeIds.contains(safeId)) return;
    _cachingYouTubeIds.add(safeId);

    File? partFile;
    final activeClient = client ?? http.Client();
    try {
      final cacheDir = await _getYouTubeStreamCacheDir();
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      if (await findCachedYouTubeAudioFile(safeId) != null) return;

      final uri = Uri.tryParse(streamUrl);
      if (uri == null || uri.scheme.toLowerCase() != 'https') return;

      final req = http.Request('GET', uri)..headers.addAll(headers);
      final streamed = await activeClient
          .send(req)
          .timeout(const Duration(seconds: 20));
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) return;

      final contentType =
          (streamed.headers['content-type'] ?? '').toLowerCase();
      final ext = contentType.contains('webm') ? 'opus' : 'm4a';
      final finalFile = File(p.join(cacheDir.path, '$safeId.$ext'));
      partFile = File(p.join(cacheDir.path, '$safeId.$ext.part'));

      final sink = partFile.openWrite();
      int written = 0;
      bool aborted = false;
      try {
        await for (final chunk in streamed.stream) {
          written += chunk.length;
          if (written > _maxYtCacheFileBytesGuard) {
            aborted = true;
            break;
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (aborted || written <= 1024) {
        if (await partFile.exists()) await partFile.delete();
        return;
      }

      await partFile.rename(finalFile.path);
      final offlineRoot = await _getYouTubeOfflineRootDir();
      await _recordYouTubeMetaWithArtwork(item, offlineRoot);
      await _saveYouTubeOfflineMeta(offlineRoot);
      await enforceYouTubeStreamCacheLimit(cacheDir);
    } catch (_) {
      if (partFile != null && await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
    } finally {
      _cachingYouTubeIds.remove(safeId);
      if (client == null) activeClient.close();
    }
  }

  static const int _maxYtCacheFileBytesGuard = _maxSingleYtCacheFileBytes;

  @visibleForTesting
  Future<void> enforceYouTubeStreamCacheLimit(
    Directory cacheDir, {
    int maxBytes = _maxYtStreamCacheBytes,
    int targetBytes = _targetYtStreamCacheBytes,
  }) async {
    if (!await cacheDir.exists()) return;
    final entries = <({File file, int size, DateTime modified})>[];
    int total = 0;

    await for (final entity in cacheDir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.basename(entity.path).endsWith('.part')) continue;
      try {
        final stat = await entity.stat();
        total += stat.size;
        entries.add((file: entity, size: stat.size, modified: stat.modified));
      } catch (_) {}
    }

    if (total <= maxBytes) return;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= targetBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {}
    }
  }

  Future<void> _preloadNewTubeTracks(int token, {int count = 1}) async {
    if (token != _newTubeSessionToken ||
        _preloadingNewTubeSessionToken == token ||
        _pendingNewTubeItems.isEmpty) {
      return;
    }
    _preloadingNewTubeSessionToken = token;
    try {
      int added = 0;
      while (added < count &&
          _pendingNewTubeItems.isNotEmpty &&
          token == _newTubeSessionToken) {
        final nextItem = _pendingNewTubeItems.first;
        _pendingNewTubeItems = _pendingNewTubeItems.sublist(1);
        final resolved = await resolveNewTubeAudioTrack(
          nextItem,
          triggerAutoCache: false,
        );
        if (token != _newTubeSessionToken) return;
        if (resolved != null) {
          await addToQueue(resolved);
          added++;
        }
      }
    } finally {
      if (_preloadingNewTubeSessionToken == token) {
        _preloadingNewTubeSessionToken = null;
      }
    }
  }

  void _maybePreloadNextNewTubeTrack() {
    if (_pendingNewTubeItems.isEmpty) return;
    final remainingInQueue = _queue.length - 1 - _currentIndex;
    if (remainingInQueue <= 1) {
      unawaited(_preloadNewTubeTracks(_newTubeSessionToken, count: 1));
    }
  }

  Future<void> addToQueue(TrackItem track) async {
    if (_queue.isEmpty) {
      await playSingleTrack(track);
      return;
    }
    _queue.add(track);
    if (_useMediaKit) {
      unawaited(_mkPlayer!.add(_buildMediaKitMedia(track)).catchError((_) {}));
    } else {
      unawaited(
        _justAudioPlayer!
            .addAudioSource(_buildAudioSource(track))
            .catchError((_) {}),
      );
    }
    notifyListeners();
  }

  Future<void> markOnboardingSeen() async {
    _hasSeenOnboarding = true;
    await _prefs?.setBool(_kOnboardingKey, true);
    notifyListeners();
  }

  void hideMiniPlayer() {
    if (_miniPlayerDismissed) return;
    _miniPlayerDismissed = true;
    notifyListeners();
  }

  void showMiniPlayer() {
    if (currentTrack != null && _miniPlayerDismissed) {
      _miniPlayerDismissed = false;
      notifyListeners();
    }
  }

  Future<void> stopPlayback() async {
    try {
      if (_useMediaKit) {
        await _mkPlayer!.stop();
      } else {
        await _justAudioPlayer!.stop();
      }
    } catch (_) {}
    _isPlaying = false;
    _isBuffering = false;
    _positionNotifier.value = Duration.zero;
    _miniPlayerDismissed = true;
    _syncHomeWidgets();
    notifyListeners();
  }

  Future<void> jumpToQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _miniPlayerDismissed = false;
    final windowIdx = index - _windowStart;
    final sequenceLen = _useMediaKit
        ? _mkPlayer!.state.playlist.medias.length
        : _justAudioPlayer!.sequence.length;
    if (windowIdx >= 0 && windowIdx < sequenceLen) {
      _currentIndex = index;
      _positionNotifier.value = Duration.zero;
      _bufferedPositionNotifier.value = Duration.zero;
      _duration = Duration.zero;
      _lastError = null;
      _syncHomeWidgets();
      notifyListeners();
      try {
        if (_useMediaKit) {
          final mkPlayer = _mkPlayer!;
          await mkPlayer.jump(windowIdx);
          unawaited(mkPlayer.play().catchError((_) {}));
        } else {
          final player = _justAudioPlayer!;
          await player.seek(Duration.zero, index: windowIdx);
          unawaited(player.play().catchError((_) {}));
        }
        _recordTrackPlayed(_queue[index]);
        return;
      } catch (_) {
        // Fallback to full queue reload below
      }
    }
    await _setQueueAndPlay(index);
  }

  Future<void> _setQueueAndPlay(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final int requestToken = ++_loadRequestToken;
    _currentIndex = index;
    _miniPlayerDismissed = false;
    _positionNotifier.value = Duration.zero;
    _bufferedPositionNotifier.value = Duration.zero;
    _duration = Duration.zero;
    _lastError = null;
    notifyListeners();

    final track = _queue[index];
    unawaited(_ensureNotificationPermissionOnce());

    try {
      if (_useMediaKit) {
        final mkPlayer = _mkPlayer!;
        if (_queue.length <= 80) {
          _windowStart = 0;
        } else {
          _windowStart = (index - 20).clamp(0, _queue.length - 60);
        }
        final windowEnd = _queue.length <= 80
            ? _queue.length
            : (_windowStart + 60).clamp(0, _queue.length);
        final windowTracks = _queue.sublist(_windowStart, windowEnd);
        final medias =
            windowTracks.map(_buildMediaKitMedia).toList(growable: false);

        await mkPlayer.open(
          mk.Playlist(medias, index: index - _windowStart),
          play: true,
        );
        if (requestToken != _loadRequestToken) return;
        await mkPlayer.setShuffle(_shuffleEnabled);
        await mkPlayer.setPlaylistMode(_toMediaKitPlaylistMode(_repeatMode));
        await mkPlayer.setRate(_playbackSpeed);
      } else {
        final player = _justAudioPlayer!;
        await player.stop();
        if (requestToken != _loadRequestToken) return;

        // Window large queues (max 60 items) so ExoPlayer & notification Next/Prev respond instantly.
        if (_queue.length <= 80) {
          _windowStart = 0;
        } else {
          _windowStart = (index - 20).clamp(0, _queue.length - 60);
        }
        final windowEnd = _queue.length <= 80
            ? _queue.length
            : (_windowStart + 60).clamp(0, _queue.length);
        final windowTracks = _queue.sublist(_windowStart, windowEnd);
        final sources =
            windowTracks.map(_buildAudioSource).toList(growable: false);

        await player.setAudioSources(
          sources,
          initialIndex: index - _windowStart,
          initialPosition: Duration.zero,
        );

        if (requestToken != _loadRequestToken) return;
        await player.setShuffleModeEnabled(_shuffleEnabled);
        await player.setLoopMode(_toJustAudioLoopMode(_repeatMode));
        await player.setSpeed(_playbackSpeed);
        unawaited(
          player.play().catchError((Object e) {
            if (requestToken == _loadRequestToken) {
              _isBuffering = false;
              _isPlaying = false;
              _syncHomeWidgets();
              _lastError = 'Tidak dapat memutar "${track.title}": $e';
              notifyListeners();
            }
          }),
        );
      }

      _recordTrackPlayed(track);
      _syncHomeWidgets();
      if (_isCastConnected) {
        unawaited(_pushCurrentTrackToCast(positionMs: 0));
      }
    } catch (e) {
      if (requestToken != _loadRequestToken) return;
      _isBuffering = false;
      _isPlaying = false;
      _syncHomeWidgets();
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
      if (_useMediaKit) {
        final mkPlayer = _mkPlayer!;
        if (mkPlayer.state.playing) {
          await pause();
        } else {
          if (mkPlayer.state.completed) {
            await mkPlayer.seek(Duration.zero);
          }
          await mkPlayer.play();
        }
      } else {
        final player = _justAudioPlayer!;
        if (player.playing) {
          await pause();
        } else {
          if (player.processingState == ProcessingState.completed) {
            await player.seek(Duration.zero);
          }
          await player.play();
          if (_isCastConnected) {
            unawaited(
              _widgetChannel.invokeMethod('castControl', {'action': 'play'})
                  .catchError((_) => false),
            );
          }
        }
      }
    } catch (e) {
      _lastError = 'Gagal mengubah status putar: $e';
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (_useMediaKit) {
      await _mkPlayer!.pause();
    } else {
      await _justAudioPlayer!.pause();
    }
    if (_isCastConnected) {
      unawaited(
        _widgetChannel.invokeMethod('castControl', {'action': 'pause'})
            .catchError((_) => false),
      );
    }
  }

  Future<void> seekTo(Duration target) async {
    if (_useMediaKit) {
      await _mkPlayer!.seek(target);
    } else {
      await _justAudioPlayer!.seek(target);
    }
    _syncHomeWidgets();
    if (_isCastConnected) {
      unawaited(
        _widgetChannel.invokeMethod('castControl', {
          'action': 'seek',
          'positionMs': target.inMilliseconds,
        }).catchError((_) => false),
      );
    }
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    if (_useMediaKit) {
      final mkPlayer = _mkPlayer!;
      final pl = mkPlayer.state.playlist;
      if (pl.index + 1 < pl.medias.length) {
        await mkPlayer.next();
        if (!mkPlayer.state.playing) {
          unawaited(mkPlayer.play().catchError((_) {}));
        }
        return;
      }
    } else {
      final player = _justAudioPlayer!;
      if (player.hasNext) {
        if (_currentIndex + 1 < _queue.length) {
          _currentIndex++;
          _positionNotifier.value = Duration.zero;
          _syncHomeWidgets();
          notifyListeners();
        }
        await player.seekToNext();
        if (!player.playing) unawaited(player.play().catchError((_) {}));
        return;
      }
    }

    if (_shuffleEnabled && _queue.length > 1) {
      int nextIdx = _currentIndex;
      for (int attempt = 0; attempt < 5 && nextIdx == _currentIndex; attempt++) {
        nextIdx = _random.nextInt(_queue.length);
      }
      await _setQueueAndPlay(nextIdx);
      return;
    }

    if (_currentIndex + 1 < _queue.length) {
      await _setQueueAndPlay(_currentIndex + 1);
    } else if (_repeatMode == RepeatCycleMode.all) {
      await _setQueueAndPlay(0);
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) return;
    if (_positionNotifier.value.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }
    if (_useMediaKit) {
      final mkPlayer = _mkPlayer!;
      final pl = mkPlayer.state.playlist;
      if (pl.index > 0) {
        await mkPlayer.previous();
        if (!mkPlayer.state.playing) {
          unawaited(mkPlayer.play().catchError((_) {}));
        }
        return;
      }
    } else {
      final player = _justAudioPlayer!;
      if (player.hasPrevious) {
        if (_currentIndex - 1 >= 0) {
          _currentIndex--;
          _positionNotifier.value = Duration.zero;
          _syncHomeWidgets();
          notifyListeners();
        }
        await player.seekToPrevious();
        if (!player.playing) unawaited(player.play().catchError((_) {}));
        return;
      }
    }

    if (_currentIndex - 1 >= 0) {
      await _setQueueAndPlay(_currentIndex - 1);
    } else if (_repeatMode == RepeatCycleMode.all) {
      await _setQueueAndPlay(_queue.length - 1);
    } else {
      await seekTo(Duration.zero);
    }
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    if (_useMediaKit) {
      unawaited(_mkPlayer!.setShuffle(_shuffleEnabled).catchError((_) {}));
    } else {
      unawaited(
        _justAudioPlayer!
            .setShuffleModeEnabled(_shuffleEnabled)
            .catchError((_) {}),
      );
    }
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
    if (_useMediaKit) {
      unawaited(
        _mkPlayer!
            .setPlaylistMode(_toMediaKitPlaylistMode(_repeatMode))
            .catchError((_) {}),
      );
    } else {
      unawaited(
        _justAudioPlayer!
            .setLoopMode(_toJustAudioLoopMode(_repeatMode))
            .catchError((_) {}),
      );
    }
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed.clamp(0.5, 2.0);
    if (_useMediaKit) {
      await _mkPlayer!.setRate(_playbackSpeed);
    } else {
      await _justAudioPlayer!.setSpeed(_playbackSpeed);
    }
    notifyListeners();
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (duration == null) {
      _sleepEndTime = null;
      unawaited(_setPlayerVolume(1.0));
      notifyListeners();
      return;
    }
    _sleepEndTime = DateTime.now().add(duration);
    _sleepTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final end = _sleepEndTime;
      if (end == null) {
        timer.cancel();
        return;
      }
      final rem = end.difference(DateTime.now());
      if (rem <= Duration.zero) {
        timer.cancel();
        _sleepTimer = null;
        _sleepEndTime = null;
        unawaited(pause().then((_) => _setPlayerVolume(1.0)));
        notifyListeners();
      } else if (rem.inMilliseconds <= 10000 && _isPlaying) {
        final vol = (rem.inMilliseconds / 10000).clamp(0.08, 1.0);
        unawaited(_setPlayerVolume(vol));
      }
    });
    notifyListeners();
  }

  void _fadeInPlayerVolume({
    double startVol = 0.2,
    int durationSeconds = 3,
  }) {
    _fadeVolumeTimer?.cancel();
    unawaited(_setPlayerVolume(startVol));
    final totalSteps = (durationSeconds * 5).clamp(5, 30);
    int step = 0;
    _fadeVolumeTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      step++;
      final progress = (step / totalSteps).clamp(0.0, 1.0);
      final vol = startVol + (1.0 - startVol) * progress;
      unawaited(_setPlayerVolume(vol.clamp(0.0, 1.0)));
      if (step >= totalSteps) {
        t.cancel();
        _fadeVolumeTimer = null;
      }
    });
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    _crossfadeSeconds = seconds.clamp(0, 10);
    await _prefs?.setInt(_kCrossfadeSecKey, _crossfadeSeconds);
    if (_crossfadeSeconds == 0) {
      _fadeVolumeTimer?.cancel();
      unawaited(_setPlayerVolume(1.0));
    }
    notifyListeners();
  }

  void _startAlarmTicker() {
    _alarmTicker?.cancel();
    _alarmTicker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_alarmEnabled) return;
      final now = DateTime.now();
      if (now.hour == _alarmHour && now.minute == _alarmMinute) {
        final dateKey = '${now.year}-${now.month}-${now.day}';
        if (_lastTriggeredAlarmDateKey == dateKey) return;
        _lastTriggeredAlarmDateKey = dateKey;
        final candidates = allOfflineMusicTracks.isNotEmpty
            ? allOfflineMusicTracks
            : (favoriteTracks.isNotEmpty ? favoriteTracks : allTracks);
        if (candidates.isNotEmpty) {
          _fadeInPlayerVolume(startVol: 0.15, durationSeconds: 5);
          unawaited(playTrackList(candidates));
        }
      }
    });
  }

  Future<void> setMusicAlarm({
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    _alarmEnabled = enabled;
    if (hour != null) _alarmHour = hour.clamp(0, 23);
    if (minute != null) _alarmMinute = minute.clamp(0, 59);
    _lastTriggeredAlarmDateKey = null;
    await _prefs?.setBool(_kAlarmEnabledKey, _alarmEnabled);
    await _prefs?.setInt(_kAlarmHourKey, _alarmHour);
    await _prefs?.setInt(_kAlarmMinuteKey, _alarmMinute);
    if (_alarmEnabled) {
      _startAlarmTicker();
    } else {
      _alarmTicker?.cancel();
      _alarmTicker = null;
    }
    notifyListeners();
  }

  void _handleTrackCompleted() {
    final active = currentTrack;
    if (active != null) {
      _trackProgressSeconds.remove(active.id);
      unawaited(_persistProgressMap());
    }

    final sequenceLen = _useMediaKit
        ? _mkPlayer!.state.playlist.medias.length
        : _justAudioPlayer!.sequence.length;
    if (sequenceLen == _queue.length) {
      // Queue auto-advance and LoopMode.one/all are handled natively by player.
      _isPlaying = false;
      _miniPlayerDismissed = true;
      _syncHomeWidgets();
      notifyListeners();
      return;
    }

    if (_repeatMode == RepeatCycleMode.one && _currentIndex >= 0) {
      final Future<void> replay;
      if (_useMediaKit) {
        final mkPlayer = _mkPlayer!;
        replay = mkPlayer.seek(Duration.zero).then((_) => mkPlayer.play());
      } else {
        final player = _justAudioPlayer!;
        replay = player.seek(Duration.zero).then((_) => player.play());
      }
      replay.catchError((Object e) {
        _lastError = 'Gagal mengulang lagu: $e';
        _syncHomeWidgets();
        notifyListeners();
      });
      return;
    }

    if (_shuffleEnabled && _queue.length > 1) {
      playNext();
      return;
    }

    if (_currentIndex + 1 < _queue.length) {
      _setQueueAndPlay(_currentIndex + 1);
    } else if (_repeatMode == RepeatCycleMode.all && _queue.isNotEmpty) {
      _setQueueAndPlay(0);
    } else {
      _isPlaying = false;
      _miniPlayerDismissed = true;
      _syncHomeWidgets();
      notifyListeners();
    }
  }

  void _syncHomeWidgets() {
    if (!Platform.isAndroid) return;
    final track = currentTrack;
    final totalMs = _duration.inMilliseconds;
    final posMs = _positionNotifier.value.inMilliseconds;
    final progressPct = totalMs > 0 ? ((posMs * 100) ~/ totalMs).clamp(0, 100) : 0;

    unawaited(
      _widgetChannel.invokeMethod<bool>('updateHomeWidget', {
        'title': track?.title ?? 'MediaCenter',
        'subtitle': track != null
            ? '${track.artist} • ${track.directoryName}'
            : 'Ketuk untuk memutar musik',
        'badge': track == null
            ? 'MEDIACENTER • OFFLINE'
            : (track.isOfflineReady ? 'OFFLINE • ${track.directoryName}' : 'LIVE LINK • ${track.directoryName}'),
        'isPlaying': _isPlaying,
        'progress': progressPct,
        'hasActiveSession': track != null,
      }).catchError((_) => false),
    );
  }

  static const Map<String, List<double>> eqPresets = {
    'Flat': [0.0, 0.0, 0.0, 0.0, 0.0],
    'Bass Boost': [6.5, 4.5, 0.0, 0.5, 1.0],
    'Pop': [-1.0, 2.5, 4.0, 2.0, -1.0],
    'Rock': [4.5, 2.5, -1.0, 3.0, 4.5],
    'Jazz': [3.0, 1.5, -1.5, 2.0, 3.5],
    'Vocal': [-2.0, -1.0, 4.5, 3.5, 1.0],
  };

  Future<void> setEqualizerEnabled(bool enabled) async {
    _equalizerEnabled = enabled;
    await _prefs?.setBool(_kEqEnabledKey, enabled);
    await _syncAudioEffectsToPipeline();
    notifyListeners();
  }

  Future<void> setEqBandGain(int index, double gainDb) async {
    if (index < 0 || index >= _eqBandGains.length) return;
    _eqBandGains[index] = gainDb.clamp(_eqMinDecibels, _eqMaxDecibels);
    _activeEqPreset = 'Custom';
    await _prefs?.setString(_kEqPresetKey, _activeEqPreset);
    await _prefs?.setStringList(
      _kEqGainsKey,
      _eqBandGains.map((g) => g.toStringAsFixed(2)).toList(),
    );
    await _syncAudioEffectsToPipeline();
    notifyListeners();
  }

  Future<void> applyEqPreset(String presetName) async {
    final values = eqPresets[presetName];
    if (values == null) return;
    _activeEqPreset = presetName;
    _eqBandGains = List<double>.from(values);
    _equalizerEnabled = presetName != 'Flat' || _bassBoostStrength > 0;
    await _prefs?.setString(_kEqPresetKey, presetName);
    await _prefs?.setBool(_kEqEnabledKey, _equalizerEnabled);
    await _prefs?.setStringList(
      _kEqGainsKey,
      _eqBandGains.map((g) => g.toStringAsFixed(2)).toList(),
    );
    await _syncAudioEffectsToPipeline();
    notifyListeners();
  }

  Future<void> setBassBoost(double strength) async {
    _bassBoostStrength = strength.clamp(0.0, 1.0);
    if (_bassBoostStrength > 0 && !_equalizerEnabled) {
      _equalizerEnabled = true;
      await _prefs?.setBool(_kEqEnabledKey, true);
    }
    await _prefs?.setDouble(_kBassBoostKey, _bassBoostStrength);
    await _syncAudioEffectsToPipeline();
    notifyListeners();
  }

  Future<void> setLoudnessGain(double gainDb) async {
    _loudnessGainDb = gainDb.clamp(0.0, 10.0);
    await _prefs?.setDouble(_kLoudnessDbKey, _loudnessGainDb);
    await _syncAudioEffectsToPipeline();
    notifyListeners();
  }

  Future<void> _syncAudioEffectsToPipeline() async {
    if (!Platform.isAndroid) return;
    try {
      final eq = _androidEqualizer;
      if (eq != null) {
        await eq.setEnabled(_equalizerEnabled);
        final params = await eq.parameters;
        _eqMinDecibels = params.minDecibels;
        _eqMaxDecibels = params.maxDecibels;
        final bands = params.bands;
        final labels = <String>[];
        for (int i = 0; i < bands.length && i < _eqBandGains.length; i++) {
          final hz = bands[i].centerFrequency.round();
          labels.add(hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)}kHz' : '${hz}Hz');
          final bassExtra = (i == 0 ? _bassBoostStrength * 6.0 : (i == 1 ? _bassBoostStrength * 3.5 : 0.0));
          final targetGain = (_eqBandGains[i] + bassExtra).clamp(
            params.minDecibels,
            params.maxDecibels,
          );
          await bands[i].setGain(targetGain);
        }
        if (labels.length == 5) {
          _eqBandLabels = labels;
        }
      }

      final loudness = _androidLoudness;
      if (loudness != null) {
        await loudness.setEnabled(_loudnessGainDb > 0.05);
        await loudness.setTargetGain(_loudnessGainDb / 10.0);
      }
    } catch (_) {
      // Safe fallback when pipeline isn't attached to an active session yet
    }
  }

  Future<LinkCheckResult> checkPlaylistLinks(String playlistId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) {
      return const LinkCheckResult(totalChecked: 0, onlineCount: 0, deadTrackIds: {});
    }
    final playlist = _playlists[idx];
    _isCheckingLinks = true;
    _linkCheckDone = 0;
    _linkCheckTotal = playlist.tracks.where((t) => !t.isLocalFile).length;
    notifyListeners();

    try {
      final res = await LinkCheckerService.checkTracks(
        playlist.tracks,
        onProgress: (done, total) {
          _linkCheckDone = done;
          _linkCheckTotal = total;
          notifyListeners();
        },
      );
      final playlistTrackIds = playlist.tracks.map((t) => t.id).toSet();
      _deadTrackIds.removeWhere(playlistTrackIds.contains);
      _deadTrackIds.addAll(res.deadTrackIds);
      await _prefs?.setStringList(_kDeadLinksKey, _deadTrackIds.toList());
      return res;
    } finally {
      _isCheckingLinks = false;
      notifyListeners();
    }
  }

  Future<void> setHideDeadLinks(bool hide) async {
    _hideDeadLinks = hide;
    await _prefs?.setBool(_kHideDeadLinksKey, hide);
    notifyListeners();
  }

  Future<void> unhideAllLinks() async {
    _deadTrackIds.clear();
    await _prefs?.setStringList(_kDeadLinksKey, const []);
    notifyListeners();
  }

  Future<bool> enterPictureInPicture() async {
    if (!Platform.isAndroid && !Platform.isWindows) return false;
    try {
      final ok =
          await _widgetChannel.invokeMethod<bool>('enterPictureInPicture');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> exitPictureInPicture() async {
    if (!Platform.isWindows) return false;
    try {
      final ok =
          await _widgetChannel.invokeMethod<bool>('exitPictureInPicture');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> startPipWindowDrag() async {
    if (!Platform.isWindows) return;
    try {
      await _widgetChannel.invokeMethod<bool>('startWindowDrag');
    } catch (_) {}
  }

  Future<bool> openCastPicker() async {
    if (!Platform.isAndroid) return false;
    try {
      if (await Permission.nearbyWifiDevices.isDenied) {
        await Permission.nearbyWifiDevices.request();
      }
    } catch (_) {}
    try {
      final ok = await _widgetChannel.invokeMethod<bool>('openCastDialog');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnectCast() async {
    if (!Platform.isAndroid) return;
    try {
      await _widgetChannel.invokeMethod<bool>('disconnectCast');
    } catch (_) {}
    _isCastConnected = false;
    _castDeviceName = null;
    notifyListeners();
  }

  void _onCastSessionUpdated(bool connected, String? deviceName) {
    _isCastConnected = connected;
    _castDeviceName = deviceName;
    notifyListeners();
    if (connected && currentTrack != null) {
      final posMs = _positionNotifier.value.inMilliseconds;
      unawaited(pause().catchError((_) {}));
      unawaited(_pushCurrentTrackToCast(positionMs: posMs));
    }
  }

  Future<void> _pushCurrentTrackToCast({int positionMs = 0}) async {
    final track = currentTrack;
    if (track == null || !_isCastConnected || !Platform.isAndroid) return;
    try {
      String? url;
      String mime = 'audio/mpeg';
      if (track.playsFromLocalFile) {
        url = await _castServer.serveLocalFile(track.playableSource);
        mime = CastMediaServer.mimeTypeForPath(track.playableSource);
      } else if (track.httpHeaders != null && track.httpHeaders!.isNotEmpty) {
        mime = 'audio/mp4';
        url = await _castServer.serveRemoteProxy(
          track.playableSource,
          track.httpHeaders!,
          mimeType: mime,
        );
      } else {
        url = track.playableSource;
      }
      if (url == null || url.isEmpty) return;
      await _widgetChannel.invokeMethod<bool>('castPlayMedia', {
        'url': url,
        'title': track.title,
        'subtitle': '${track.artist} • ${track.directoryName}',
        'mimeType': mime,
        'positionMs': positionMs,
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _alarmTicker?.cancel();
    _fadeVolumeTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _pipController.close();
    unawaited(_castServer.dispose());
    _positionNotifier.dispose();
    _bufferedPositionNotifier.dispose();
    _justAudioPlayer?.dispose();
    unawaited(_mkPlayer?.dispose());
    super.dispose();
  }
}
