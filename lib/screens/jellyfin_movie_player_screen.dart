import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/jellyfin_profile_models.dart';
import '../providers/music_provider.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../theme/app_theme.dart';

class JellyfinMoviePlayerScreen extends StatefulWidget {
  final JellyfinMovieItem movie;
  final bool initialUseHls;

  const JellyfinMoviePlayerScreen({
    super.key,
    required this.movie,
    this.initialUseHls = false,
  });

  @override
  State<JellyfinMoviePlayerScreen> createState() =>
      _JellyfinMoviePlayerScreenState();
}

class _JellyfinMoviePlayerScreenState extends State<JellyfinMoviePlayerScreen> {
  VideoPlayerController? _controller;
  VoidCallback? _controllerListener;
  Timer? _hideControlsTimer;
  int _initToken = 0;
  late bool _useHls;
  bool _hlsWasStarted = false;
  bool _triedAutoFallback = false;
  bool _isInitializing = true;
  bool _showControls = true;
  bool _isZoomCrop = false;
  bool _isLandscapeLocked = true;
  double _playbackSpeed = 1.0;
  String? _playerError;
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  late final String _playSessionId;
  late final ProfileJellyfinProvider _jfProvider;

  @override
  void initState() {
    super.initState();
    _useHls = widget.initialUseHls;
    _playSessionId = 'jf_${DateTime.now().millisecondsSinceEpoch}';
    _jfProvider = context.read<ProfileJellyfinProvider>();

    // Pause background music automatically before cinema playback starts
    final music = context.read<MusicProvider>();
    if (music.isPlaying) {
      unawaited(music.pause());
    }

    _enterCinemaFullscreen(landscape: true);
    unawaited(_initController(resumeFromSaved: true));
  }

  void _enterCinemaFullscreen({required bool landscape}) {
    _isLandscapeLocked = landscape;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (landscape) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _disposeActiveController() async {
    final old = _controller;
    final oldListener = _controllerListener;
    _controller = null;
    _controllerListener = null;
    if (old != null) {
      if (oldListener != null) {
        old.removeListener(oldListener);
      }
      await old.dispose();
    }
  }

  Future<void> _initController({
    required bool resumeFromSaved,
    Duration? explicitPosition,
  }) async {
    final int currentToken = ++_initToken;

    if (mounted) {
      setState(() {
        _isInitializing = true;
        _playerError = null;
      });
    }

    await _disposeActiveController();
    if (!mounted || currentToken != _initToken) return;

    if (_useHls) {
      _hlsWasStarted = true;
    }

    final uri = _jfProvider.buildMovieStreamUri(
      widget.movie,
      useHlsTranscode: _useHls,
      playSessionId: _playSessionId,
    );

    final nextController = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: _jfProvider.authHeaders,
    );

    try {
      await nextController.initialize().timeout(const Duration(seconds: 35));
      if (!mounted || currentToken != _initToken) {
        await nextController.dispose();
        return;
      }

      Duration? targetSeek = explicitPosition;
      if (targetSeek == null && resumeFromSaved) {
        final savedSec = _jfProvider.savedMoviePositionSeconds(widget.movie.id);
        if (savedSec > 5) {
          targetSeek = Duration(seconds: savedSec);
        } else if (widget.movie.playbackPositionTicks > 0) {
          targetSeek = Duration(
            milliseconds: widget.movie.playbackPositionTicks ~/ 10000,
          );
        }
      }

      if (targetSeek != null &&
          nextController.value.duration > Duration.zero &&
          targetSeek <
              nextController.value.duration - const Duration(seconds: 5)) {
        await nextController.seekTo(targetSeek);
      }

      if (!mounted || currentToken != _initToken) {
        await nextController.dispose();
        return;
      }

      void listener() {
        if (!mounted || currentToken != _initToken) return;
        final val = nextController.value;

        // Detect post-init codec/container errors (e.g. AC3/DTS/HEVC decode error on first frame)
        if (val.hasError) {
          final errDesc = val.errorDescription ?? 'Format audio/video tidak didukung secara direct.';
          if (!_useHls && !_triedAutoFallback) {
            _triedAutoFallback = true;
            _useHls = true;
            unawaited(
              _initController(
                resumeFromSaved: false,
                explicitPosition: val.position,
              ),
            );
            return;
          }
          setState(() {
            _isInitializing = false;
            _playerError = _jfProvider.sanitizeError(errDesc);
          });
          return;
        }

        // Throttled 10s watch progress persistence so progress isn't lost if OS kills app
        if (val.isPlaying &&
            val.position.inSeconds > 2 &&
            DateTime.now().difference(_lastProgressSave).inSeconds >= 10) {
          _lastProgressSave = DateTime.now();
          unawaited(
            _jfProvider.saveMovieProgress(widget.movie.id, val.position),
          );
        }
      }

      _controllerListener = listener;
      nextController.addListener(listener);

      await nextController.setPlaybackSpeed(_playbackSpeed);
      await nextController.play();

      if (!mounted || currentToken != _initToken) {
        nextController.removeListener(listener);
        await nextController.dispose();
        return;
      }

      _controller = nextController;
      setState(() => _isInitializing = false);
      _scheduleHideControls();
    } catch (e) {
      await nextController.dispose();
      if (!mounted || currentToken != _initToken) return;

      // Smart automatic fallback from Direct Stream -> Universal HLS if codec/container fails!
      if (!_useHls && !_triedAutoFallback) {
        _triedAutoFallback = true;
        _useHls = true;
        await _initController(
          resumeFromSaved: resumeFromSaved,
          explicitPosition: explicitPosition,
        );
        return;
      }

      setState(() {
        _isInitializing = false;
        _playerError = _jfProvider.sanitizeError(e);
      });
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      final ctrl = _controller;
      if (mounted && ctrl != null && ctrl.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleHideControls();
    }
  }

  Future<void> _skipRelative(Duration delta) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final current = ctrl.value.position;
    final total = ctrl.value.duration;
    Duration next = current + delta;
    if (next.isNegative) next = Duration.zero;
    if (total > Duration.zero && next > total) next = total;
    await ctrl.seekTo(next);
    _scheduleHideControls();
  }

  Future<void> _switchStreamMode(bool toHls) async {
    if (_useHls == toHls) return;
    final currentPos = _controller?.value.position;
    if (_useHls && !toHls) {
      unawaited(_jfProvider.stopHlsEncodingSession(_playSessionId));
    }
    _useHls = toHls;
    await _initController(resumeFromSaved: false, explicitPosition: currentPos);
  }

  String _formatTime(Duration d) {
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  void dispose() {
    _initToken++;
    _hideControlsTimer?.cancel();
    final ctrl = _controller;
    final listener = _controllerListener;
    if (ctrl != null) {
      if (listener != null) {
        ctrl.removeListener(listener);
      }
      if (ctrl.value.isInitialized) {
        unawaited(
          _jfProvider.saveMovieProgress(widget.movie.id, ctrl.value.position),
        );
      }
      ctrl.dispose();
    }
    if (_hlsWasStarted) {
      unawaited(_jfProvider.stopHlsEncodingSession(_playSessionId));
    }
    _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video Surface
            if (ctrl != null && ctrl.value.isInitialized)
              Center(
                child: (_isZoomCrop &&
                        ctrl.value.size.width > 0 &&
                        ctrl.value.size.height > 0)
                    ? SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: ctrl.value.size.width,
                            height: ctrl.value.size.height,
                            child: VideoPlayer(ctrl),
                          ),
                        ),
                      )
                    : AspectRatio(
                        aspectRatio: ctrl.value.aspectRatio > 0
                            ? ctrl.value.aspectRatio
                            : 16 / 9,
                        child: VideoPlayer(ctrl),
                      ),
              )
            else if (_isInitializing)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.netflixRed),
                    const SizedBox(height: 16),
                    Text(
                      _useHls
                          ? 'Menyiapkan Stream HLS Universal...'
                          : 'Memuat Film dari Hallsem Cinema...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (_playerError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.netflixRed,
                        size: 52,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Gagal Memutar Film',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _playerError!,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.netflixRed,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _switchStreamMode(!_useHls),
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: Text(
                              _useHls ? 'Coba Direct Stream' : 'Coba Mode HLS',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Kembali'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Netflix Cinema OSD Overlay
            if (_showControls)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.78),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.movie.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5,
                                    ),
                                  ),
                                  Text(
                                    '${widget.movie.displaySubtitle} • ${_useHls ? "HLS Stream" : "Direct Play"}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _switchStreamMode(!_useHls),
                              icon: const Icon(
                                Icons.hd_outlined,
                                color: AppColors.neonCyan,
                                size: 18,
                              ),
                              label: Text(
                                _useHls ? 'HLS' : 'DIRECT',
                                style: const TextStyle(
                                  color: AppColors.neonCyan,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Rasio Layar (Fit / Zoom)',
                              icon: Icon(
                                _isZoomCrop
                                    ? Icons.fit_screen_rounded
                                    : Icons.aspect_ratio_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  setState(() => _isZoomCrop = !_isZoomCrop),
                            ),
                            IconButton(
                              tooltip: 'Putar Orientasi Layar',
                              icon: const Icon(
                                Icons.screen_rotation_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _enterCinemaFullscreen(
                                    landscape: !_isLandscapeLocked,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      // Center Transport Controls (-10s, Play/Pause, +10s)
                      if (ctrl != null && ctrl.value.isInitialized)
                        ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: ctrl,
                          builder: (_, val, _) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  iconSize: 40,
                                  icon: const Icon(
                                    Icons.replay_10_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => _skipRelative(
                                    const Duration(seconds: -10),
                                  ),
                                ),
                                const SizedBox(width: 28),
                                GestureDetector(
                                  onTap: () {
                                    if (val.isPlaying) {
                                      ctrl.pause();
                                    } else {
                                      ctrl.play();
                                      _scheduleHideControls();
                                    }
                                  },
                                  child: Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.netflixRed
                                          .withValues(alpha: 0.9),
                                    ),
                                    alignment: Alignment.center,
                                    child: val.isBuffering
                                        ? const SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            val.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 42,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 28),
                                IconButton(
                                  iconSize: 40,
                                  icon: const Icon(
                                    Icons.forward_10_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => _skipRelative(
                                    const Duration(seconds: 10),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                      // Bottom Seek Bar & Speed Control
                      if (ctrl != null && ctrl.value.isInitialized)
                        ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: ctrl,
                          builder: (_, val, _) {
                            final durMs = val.duration.inMilliseconds > 0
                                ? val.duration.inMilliseconds.toDouble()
                                : (widget.movie.duration?.inMilliseconds
                                        .toDouble() ??
                                    1.0);
                            final posMs = val.position.inMilliseconds
                                .toDouble()
                                .clamp(0.0, durMs);

                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: AppColors.netflixRed,
                                      thumbColor: AppColors.netflixRed,
                                    ),
                                    child: Slider(
                                      value: posMs,
                                      min: 0.0,
                                      max: durMs > 0 ? durMs : 1.0,
                                      onChanged: durMs > 1.0
                                          ? (v) {
                                              ctrl.seekTo(
                                                Duration(
                                                  milliseconds: v.round(),
                                                ),
                                              );
                                              _scheduleHideControls();
                                            }
                                          : null,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${_formatTime(val.position)} / ${_formatTime(Duration(milliseconds: durMs.round()))}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      PopupMenuButton<double>(
                                        tooltip: 'Kecepatan Putar Film',
                                        onSelected: (spd) async {
                                          setState(() => _playbackSpeed = spd);
                                          await ctrl.setPlaybackSpeed(spd);
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 0.75,
                                            child: Text('0.75x'),
                                          ),
                                          PopupMenuItem(
                                            value: 1.0,
                                            child: Text('1.0x (Normal)'),
                                          ),
                                          PopupMenuItem(
                                            value: 1.25,
                                            child: Text('1.25x'),
                                          ),
                                          PopupMenuItem(
                                            value: 1.5,
                                            child: Text('1.5x'),
                                          ),
                                          PopupMenuItem(
                                            value: 2.0,
                                            child: Text('2.0x'),
                                          ),
                                        ],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.speed_rounded,
                                                color: Colors.white70,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${_playbackSpeed}x',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      else
                        const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
