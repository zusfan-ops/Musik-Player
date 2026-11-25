import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/jellyfin_config.dart';
import '../models/jellyfin_profile_models.dart';
import '../services/jellyfin_service.dart';

class ProfileJellyfinProvider extends ChangeNotifier {
  static const String _kDisplayNameKey = 'profile_display_name_v1';
  static const String _kBioSubtitleKey = 'profile_bio_subtitle_v1';
  static const String _kAvatarModeKey = 'profile_avatar_mode_v1';
  static const String _kAvatarPresetKey = 'profile_avatar_preset_v1';
  static const String _kCustomAvatarPathKey = 'profile_custom_avatar_path_v1';
  static const String _kJfMovieProgressKey = 'jellyfin_movie_progress_sec_v1';

  final bool autoConnectOnInit;
  SharedPreferences? _prefs;
  bool _initialized = false;

  // Profile & Avatar State
  String _displayName = 'Penikmat Musik';
  String _bioSubtitle = 'Offline M3U • Direktori • Hallsem Cinema';
  AvatarSourceMode _avatarMode = AvatarSourceMode.preset;
  int _avatarPresetIndex = 0;
  String? _customAvatarPath;

  // Built-in Integrated Jellyfin State (zero manual input required)
  final String _serverUrl = JellyfinBuiltInConfig.serverUrl;
  final String _apiKey = JellyfinBuiltInConfig.apiKey;
  String _serverName = JellyfinBuiltInConfig.defaultServerName;
  String _serverVersion = '';
  String _selectedUserId = JellyfinBuiltInConfig.defaultUserId;
  List<JellyfinUserSummary> _availableUsers = const [
    JellyfinUserSummary(
      id: JellyfinBuiltInConfig.defaultUserId,
      name: JellyfinBuiltInConfig.username,
    ),
  ];
  List<JellyfinMovieItem> _movies = [];
  Map<String, int> _movieWatchSeconds = {};

  bool _isLoadingMovies = false;
  bool _isConnected = true;
  String? _errorMessage;
  int _fetchToken = 0;

  ProfileJellyfinProvider({this.autoConnectOnInit = true});

  bool get initialized => _initialized;
  String get displayName => _displayName;
  String get bioSubtitle => _bioSubtitle;
  AvatarSourceMode get avatarMode => _avatarMode;
  int get avatarPresetIndex => _avatarPresetIndex;
  String? get customAvatarPath => _customAvatarPath;

  String get serverUrl => _serverUrl;
  bool get hasCredentials => _serverUrl.isNotEmpty && _apiKey.isNotEmpty;
  bool get isConnected => _isConnected;
  bool get isLoadingMovies => _isLoadingMovies;
  String get serverName => _serverName;
  String get serverVersion => _serverVersion;
  String get activeUsername =>
      selectedUser?.name ?? JellyfinBuiltInConfig.username;
  String get selectedUserId => _selectedUserId;
  List<JellyfinUserSummary> get availableUsers =>
      List.unmodifiable(_availableUsers);
  List<JellyfinMovieItem> get movies => List.unmodifiable(_movies);
  String? get errorMessage => _errorMessage;

  JellyfinUserSummary? get selectedUser {
    for (final u in _availableUsers) {
      if (u.id == _selectedUserId) return u;
    }
    return null;
  }

  Map<String, String> get authHeaders =>
      _apiKey.isNotEmpty ? JellyfinService.buildAuthHeaders(_apiKey) : const {};

  String sanitizeError(Object error) =>
      JellyfinService.sanitizeErrorMessage(error, _apiKey);

  String? get jellyfinUserAvatarUrl {
    final u = selectedUser;
    if (!hasCredentials || u == null || !u.hasPrimaryImage) return null;
    return JellyfinService.buildUserAvatarUrl(_serverUrl, u.id);
  }

  int savedMoviePositionSeconds(String movieId) =>
      _movieWatchSeconds[movieId] ?? 0;

  double movieProgressRatio(JellyfinMovieItem movie) {
    final localSec = _movieWatchSeconds[movie.id] ?? 0;
    final durSec = movie.duration?.inSeconds ?? 0;
    if (localSec > 0 && durSec > 0) {
      return (localSec / durSec).clamp(0.0, 1.0);
    }
    return movie.serverResumeRatio;
  }

  List<JellyfinMovieItem> get continueWatchingMovies {
    return _movies.where((m) => movieProgressRatio(m) > 0.02).toList();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadPersistedProfile();
    _initialized = true;
    notifyListeners();

    if (autoConnectOnInit && hasCredentials) {
      unawaited(connectAndSyncBuiltInJellyfin());
    }
  }

  Future<void> _loadPersistedProfile() async {
    final prefs = _prefs;
    if (prefs == null) return;

    _displayName = prefs.getString(_kDisplayNameKey) ?? 'Penikmat Musik';
    _bioSubtitle =
        prefs.getString(_kBioSubtitleKey) ?? 'Offline M3U • Direktori • Hallsem Cinema';

    final modeStr = prefs.getString(_kAvatarModeKey) ?? 'preset';
    _avatarMode = AvatarSourceMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => AvatarSourceMode.preset,
    );
    _avatarPresetIndex = prefs.getInt(_kAvatarPresetKey) ?? 0;

    final savedAvatar = prefs.getString(_kCustomAvatarPathKey);
    if (savedAvatar != null && savedAvatar.isNotEmpty) {
      try {
        if (await File(savedAvatar).exists()) {
          _customAvatarPath = savedAvatar;
        } else if (_avatarMode == AvatarSourceMode.customFile) {
          _avatarMode = AvatarSourceMode.preset;
        }
      } catch (_) {
        _customAvatarPath = null;
      }
    }

    try {
      final rawProg = prefs.getString(_kJfMovieProgressKey);
      if (rawProg != null && rawProg.isNotEmpty) {
        final map = jsonDecode(rawProg) as Map<String, dynamic>;
        _movieWatchSeconds = map.map((k, v) => MapEntry(k, (v as num).toInt()));
      }
    } catch (_) {
      _movieWatchSeconds = {};
    }
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  // ==================== PROFILE & AVATAR CUSTOMIZATION ====================

  Future<void> updateProfileInfo({
    required String displayName,
    required String bioSubtitle,
  }) async {
    final cleanName = displayName.trim();
    final cleanBio = bioSubtitle.trim();
    if (cleanName.isNotEmpty) {
      _displayName = cleanName;
      await _prefs?.setString(_kDisplayNameKey, _displayName);
    }
    _bioSubtitle =
        cleanBio.isEmpty ? 'Offline M3U • Direktori • Hallsem Cinema' : cleanBio;
    await _prefs?.setString(_kBioSubtitleKey, _bioSubtitle);
    notifyListeners();
  }

  Future<void> selectPresetAvatar(int index) async {
    _avatarPresetIndex = index.clamp(0, AvatarPresetStyle.presets.length - 1);
    _avatarMode = AvatarSourceMode.preset;
    await _prefs?.setInt(_kAvatarPresetKey, _avatarPresetIndex);
    await _prefs?.setString(_kAvatarModeKey, _avatarMode.name);
    notifyListeners();
  }

  Future<void> useJellyfinAvatar() async {
    if (jellyfinUserAvatarUrl == null) return;
    _avatarMode = AvatarSourceMode.jellyfinAvatar;
    await _prefs?.setString(_kAvatarModeKey, _avatarMode.name);
    notifyListeners();
  }

  Future<bool> pickCustomAvatarImage() async {
    _errorMessage = null;
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Pilih Foto Avatar Profil',
        type: FileType.image,
      );
      if (picked == null) return false;

      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return false;
      if (bytes.length > 12 * 1024 * 1024) {
        _errorMessage = 'Ukuran foto avatar maksimal 12 MB.';
        notifyListeners();
        return false;
      }

      final supportDir = await getApplicationSupportDirectory();
      final avatarDir = Directory(p.join(supportDir.path, 'profile'));
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }

      String ext = p.extension(picked.name).toLowerCase();
      if (!const {'.png', '.jpg', '.jpeg', '.webp'}.contains(ext)) {
        ext = '.png';
      }

      final hash = sha256.convert(bytes).toString().substring(0, 16);
      final targetPath = p.join(avatarDir.path, 'avatar_$hash$ext');
      final outFile = File(targetPath);
      await outFile.writeAsBytes(bytes, flush: true);

      final previous = _customAvatarPath;
      if (previous != null && previous != targetPath) {
        try {
          final oldFile = File(previous);
          if (await oldFile.exists()) await oldFile.delete();
        } catch (_) {}
      }

      _customAvatarPath = targetPath;
      _avatarMode = AvatarSourceMode.customFile;
      await _prefs?.setString(_kCustomAvatarPathKey, targetPath);
      await _prefs?.setString(_kAvatarModeKey, _avatarMode.name);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Gagal mengatur foto avatar: $e';
      notifyListeners();
      return false;
    }
  }

  // ==================== INTEGRATED JELLYFIN SYNC ====================

  Future<void> connectAndSyncBuiltInJellyfin() async {
    try {
      final result = await JellyfinService.testAndDiscoverServer(
        rawServerUrl: _serverUrl,
        rawApiKey: _apiKey,
      );
      _serverName = result.serverName;
      _serverVersion = result.serverVersion;
      if (result.users.isNotEmpty) {
        _availableUsers = result.users;
        final matchedUser = result.users.where(
          (u) =>
              u.name.toLowerCase() ==
              JellyfinBuiltInConfig.username.toLowerCase(),
        );
        if (matchedUser.isNotEmpty) {
          _selectedUserId = matchedUser.first.id;
        }
      }
      _isConnected = true;
    } catch (_) {
      // Proceed to fetch movies directly for user `nonton`
    }
    await refreshMovies();
  }

  Future<void> refreshMovies({String searchQuery = ''}) async {
    if (!hasCredentials) return;
    final token = ++_fetchToken;
    _isLoadingMovies = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fetched = await JellyfinService.fetchMoviesAndVideos(
        serverUrl: _serverUrl,
        apiKey: _apiKey,
        userId: _selectedUserId,
        searchQuery: searchQuery,
      );
      if (token != _fetchToken) return;
      _movies = fetched;
      _isConnected = true;
    } catch (e) {
      if (token != _fetchToken) return;
      _isConnected = false;
      _errorMessage = JellyfinService.sanitizeErrorMessage(e, _apiKey);
    } finally {
      if (token == _fetchToken) {
        _isLoadingMovies = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveMovieProgress(String movieId, Duration position) async {
    if (movieId.isEmpty) return;
    _movieWatchSeconds[movieId] = position.inSeconds;
    await _prefs?.setString(
      _kJfMovieProgressKey,
      jsonEncode(_movieWatchSeconds),
    );
    notifyListeners();
  }

  String posterUrlFor(JellyfinMovieItem item) =>
      JellyfinService.buildPrimaryImageUrl(_serverUrl, item.id);

  String backdropUrlFor(JellyfinMovieItem item) =>
      item.hasBackdropImage
          ? JellyfinService.buildBackdropImageUrl(_serverUrl, item.id)
          : JellyfinService.buildPrimaryImageUrl(_serverUrl, item.id);

  Uri buildMovieStreamUri(
    JellyfinMovieItem item, {
    required bool useHlsTranscode,
    required String playSessionId,
  }) {
    if (useHlsTranscode) {
      return JellyfinService.buildHlsStreamUri(
        serverUrl: _serverUrl,
        itemId: item.id,
        mediaSourceId: item.mediaSourceId,
        playSessionId: playSessionId,
      );
    }
    return JellyfinService.buildDirectStreamUri(
      serverUrl: _serverUrl,
      itemId: item.id,
      mediaSourceId: item.mediaSourceId,
    );
  }

  Future<void> stopHlsEncodingSession(String playSessionId) async {
    if (!hasCredentials) return;
    await JellyfinService.stopActiveEncoding(
      serverUrl: _serverUrl,
      apiKey: _apiKey,
      playSessionId: playSessionId,
    );
  }
}
