import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../theme/app_theme.dart';

/// Helper that routes M3U / media tracks automatically to Video Player when `isVideo == true`,
/// or Audio Player when `isVideo == false`.
class M3uPlaybackLauncher {
  static final Random _random = Random();

  static Future<void> playItemList(
    BuildContext context,
    List<TrackItem> items, {
    int initialIndex = 0,
    bool shuffle = false,
    bool forceVideoPlayer = false,
  }) async {
    if (items.isEmpty) return;

    int targetIdx = initialIndex.clamp(0, items.length - 1);
    if (shuffle && initialIndex == 0 && items.length > 1) {
      targetIdx = _random.nextInt(items.length);
    }

    final selected = items[targetIdx];

    if (forceVideoPlayer || selected.isVideo) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => M3uVideoPlayerScreen(
            playlistItems: items,
            initialIndex: targetIdx,
          ),
        ),
      );
      return;
    }

    await context.read<MusicProvider>().playTrackList(
          items,
          initialIndex: targetIdx,
          shuffle: shuffle,
        );
  }
}

class M3uVideoPlayerScreen extends StatefulWidget {
  final List<TrackItem> playlistItems;
  final int initialIndex;

  const M3uVideoPlayerScreen({
    super.key,
    required this.playlistItems,
    this.initialIndex = 0,
  });

  @override
  State<M3uVideoPlayerScreen> createState() => _M3uVideoPlayerScreenState();
}

class _M3uVideoPlayerScreenState extends State<M3uVideoPlayerScreen> {
  VideoPlayerController? _controller;
  VoidCallback? _controllerListener;
  Timer? _hideControlsTimer;
  final TextEditingController _channelSearchCtrl = TextEditingController();

  int _initToken = 0;
  late int _currentIndex;
  bool _isInitializing = true;
  bool _showControls = true;
  bool _isFullscreenLandscape = false;
  bool _isZoomCrop = false;
  double _playbackSpeed = 1.0;
  String? _errorMessage;
  String _channelFilter = '';

  TrackItem get _currentItem => widget.playlistItems[_currentIndex];

  bool get _isLiveStream {
    final item = _currentItem;
    if (item.durationSeconds != null && item.durationSeconds! < 0) return true;
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      final dur = ctrl.value.duration;
      if (dur <= Duration.zero || dur.inHours > 12) return true;
      if (item.pathOrUrl.toLowerCase().contains('.m3u8') &&
          dur.inSeconds <= 90) {
        return true;
      }
    }
    return item.pathOrUrl.toLowerCase().contains('.m3u8') &&
        item.durationSeconds == null;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex =
        widget.initialIndex.clamp(0, widget.playlistItems.length - 1);

    // Pause background audio player immediately so music and video never overlap
    final music = context.read<MusicProvider>();
    if (music.isPlaying) {
      unawaited(music.pause());
    }

    unawaited(_loadChannelAtIndex(_currentIndex));
  }

  void _setFullscreenMode(bool fullscreenLandscape) {
    _isFullscreenLandscape = fullscreenLandscape;
    if (fullscreenLandscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _restoreDefaultSystemUi() {
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

  Future<void> _loadChannelAtIndex(int index) async {
    if (index < 0 || index >= widget.playlistItems.length) return;
    final int token = ++_initToken;

    if (mounted) {
      setState(() {
        _currentIndex = index;
        _isInitializing = true;
        _errorMessage = null;
        _showControls = true;
      });
    }

    await _disposeActiveController();
    if (!mounted || token != _initToken) return;

    final item = widget.playlistItems[index];
    VideoPlayerController? nextCtrl;
    VoidCallback? attachedListener;

    try {
      if (item.playsFromLocalFile) {
        final f = File(item.playableSource);
        if (!await f.exists()) {
          throw FileSystemException(
            'File video lokal tidak ditemukan',
            item.playableSource,
          );
        }
        nextCtrl = VideoPlayerController.file(f);
      } else {
        final headers = <String, String>{
          'User-Agent': item.httpHeaders?['User-Agent'] ??
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Safari/537.36',
          if (item.httpHeaders != null) ...item.httpHeaders!,
        };
        nextCtrl = VideoPlayerController.networkUrl(
          Uri.parse(item.playableSource),
          httpHeaders: headers,
        );
      }

      await nextCtrl.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || token != _initToken) {
        await nextCtrl.dispose();
        return;
      }

      final activeRef = nextCtrl;
      void listener() {
        if (!mounted || token != _initToken) return;
        final val = activeRef.value;
        if (val.hasError) {
          setState(() {
            _isInitializing = false;
            _errorMessage =
                val.errorDescription ?? 'Stream video tidak dapat diputar.';
          });
        }
      }

      attachedListener = listener;
      nextCtrl.addListener(listener);

      if (!_isLiveStream && _playbackSpeed != 1.0) {
        await nextCtrl.setPlaybackSpeed(_playbackSpeed);
      }
      await nextCtrl.play();

      if (!mounted || token != _initToken) {
        nextCtrl.removeListener(listener);
        await nextCtrl.dispose();
        return;
      }

      _controllerListener = listener;
      _controller = nextCtrl;
      setState(() => _isInitializing = false);
      _scheduleHideControls();
    } catch (e) {
      if (nextCtrl != null) {
        if (attachedListener != null) {
          nextCtrl.removeListener(attachedListener);
        }
        await nextCtrl.dispose();
      }
      await _disposeActiveController();
      if (!mounted || token != _initToken) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Gagal memuat stream video "${item.title}": $e';
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

  void _playPreviousChannel() {
    if (widget.playlistItems.length <= 1) return;
    final prev = (_currentIndex - 1 + widget.playlistItems.length) %
        widget.playlistItems.length;
    unawaited(_loadChannelAtIndex(prev));
  }

  void _playNextChannel() {
    if (widget.playlistItems.length <= 1) return;
    final next = (_currentIndex + 1) % widget.playlistItems.length;
    unawaited(_loadChannelAtIndex(next));
  }

  Future<void> _switchToAudioOnlyMode() async {
    final music = context.read<MusicProvider>();
    final items = widget.playlistItems;
    final idx = _currentIndex;
    Navigator.pop(context);
    await music.playTrackList(items, initialIndex: idx);
  }

  String _formatDuration(Duration d) {
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
    _channelSearchCtrl.dispose();
    final ctrl = _controller;
    final listener = _controllerListener;
    if (ctrl != null) {
      if (listener != null) {
        ctrl.removeListener(listener);
      }
      ctrl.dispose();
    }
    _restoreDefaultSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscapeScreen =
        MediaQuery.of(context).orientation == Orientation.landscape ||
            _isFullscreenLandscape;

    final Widget scaffoldContent = isLandscapeScreen
        ? Scaffold(
            backgroundColor: Colors.black,
            endDrawer: Drawer(
              backgroundColor: AppColors.surface,
              child: SafeArea(child: _buildChannelListPanel()),
            ),
            body: _buildVideoViewport(fullscreenMode: true),
          )
        : Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildVideoViewport(fullscreenMode: false),
                  ),
                  _buildNowWatchingInfoStrip(),
                  const Divider(height: 1, color: AppColors.surfaceHighlight),
                  Expanded(
                    child: _buildChannelListPanel(),
                  ),
                ],
              ),
            ),
          );

    return PopScope(
      canPop: !_isFullscreenLandscape,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreenLandscape) {
          setState(() => _setFullscreenMode(false));
        }
      },
      child: scaffoldContent,
    );
  }

  Widget _buildVideoViewport({required bool fullscreenMode}) {
    final ctrl = _controller;
    final item = _currentItem;

    return Builder(
      builder: (scaffoldCtx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Video Surface (or artwork fallback if stream is audio-only HLS)
              if (ctrl != null && ctrl.value.isInitialized)
                ctrl.value.size.width > 0 && ctrl.value.size.height > 0
                    ? Center(
                        child: _isZoomCrop
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
                    : Center(
                        child: item.hasValidNetworkArtwork
                            ? Image.network(
                                item.artworkUrl!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const AppLogo(size: 96),
                              )
                            : const AppLogo(size: 96),
                      )
              else if (_isInitializing)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: AppColors.netflixRed,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Memuat Video "${item.title}"...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_errorMessage != null)
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tv_off_rounded,
                          color: AppColors.netflixRed,
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.netflixRed,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () =>
                                  _loadChannelAtIndex(_currentIndex),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Muat Ulang'),
                            ),
                            if (widget.playlistItems.length > 1)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _playNextChannel,
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  size: 16,
                                ),
                                label: const Text('Channel Berikutnya'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // 2. Interactive OSD Controls
              if (_showControls)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.76),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.80),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: SafeArea(
                    top: fullscreenMode,
                    bottom: fullscreenMode,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top OSD Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  if (_isFullscreenLandscape) {
                                    setState(() => _setFullscreenMode(false));
                                  } else {
                                    Navigator.pop(context);
                                  }
                                },
                              ),
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Muat Ulang Stream',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    _loadChannelAtIndex(_currentIndex),
                              ),
                              IconButton(
                                tooltip: 'Rasio Layar (Fit / Zoom)',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  _isZoomCrop
                                      ? Icons.fit_screen_rounded
                                      : Icons.aspect_ratio_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _isZoomCrop = !_isZoomCrop),
                              ),
                              if (fullscreenMode &&
                                  widget.playlistItems.length > 1)
                                IconButton(
                                  tooltip: 'Daftar Channel M3U',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.playlist_play_rounded,
                                    color: AppColors.neonCyan,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    Scaffold.of(scaffoldCtx).openEndDrawer();
                                  },
                                ),
                            ],
                          ),
                        ),

                        // Center Transport Controls (Prev Channel, Play/Pause, Next Channel)
                        if (ctrl != null && ctrl.value.isInitialized)
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: ctrl,
                            builder: (_, val, _) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (widget.playlistItems.length > 1)
                                    IconButton(
                                      tooltip: 'Channel Sebelumnya',
                                      iconSize: fullscreenMode ? 38 : 30,
                                      icon: const Icon(
                                        Icons.skip_previous_rounded,
                                        color: Colors.white,
                                      ),
                                      onPressed: _playPreviousChannel,
                                    ),
                                  const SizedBox(width: 18),
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
                                      width: fullscreenMode ? 62 : 50,
                                      height: fullscreenMode ? 62 : 50,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.netflixRed
                                            .withValues(alpha: 0.9),
                                      ),
                                      alignment: Alignment.center,
                                      child: val.isBuffering
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Icon(
                                              val.isPlaying
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                              color: Colors.white,
                                              size: fullscreenMode ? 36 : 30,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  if (widget.playlistItems.length > 1)
                                    IconButton(
                                      tooltip: 'Channel Berikutnya',
                                      iconSize: fullscreenMode ? 38 : 30,
                                      icon: const Icon(
                                        Icons.skip_next_rounded,
                                        color: Colors.white,
                                      ),
                                      onPressed: _playNextChannel,
                                    ),
                                ],
                              );
                            },
                          ),

                        // Bottom OSD Bar (LIVE Badge OR VOD Seekbar + Speed + Fullscreen Toggle)
                        if (ctrl != null && ctrl.value.isInitialized)
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: ctrl,
                            builder: (_, val, _) {
                              final live = _isLiveStream;
                              final durMs =
                                  val.duration.inMilliseconds.toDouble();
                              final posMs = val.position.inMilliseconds
                                  .toDouble()
                                  .clamp(0.0, durMs > 0 ? durMs : 1.0);

                              return Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
                                child: Row(
                                  children: [
                                    if (live) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.netflixRed,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              size: 7,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 5),
                                            Text(
                                              'LIVE TV',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                    ] else ...[
                                      Text(
                                        _formatDuration(val.position),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context)
                                              .copyWith(
                                            activeTrackColor:
                                                AppColors.netflixRed,
                                            thumbColor: AppColors.netflixRed,
                                          ),
                                          child: Slider(
                                            value: posMs,
                                            min: 0.0,
                                            max: durMs > 0 ? durMs : 1.0,
                                            onChanged: durMs > 0
                                                ? (v) => ctrl.seekTo(
                                                      Duration(
                                                        milliseconds: v.round(),
                                                      ),
                                                    )
                                                : null,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(val.duration),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                      PopupMenuButton<double>(
                                        tooltip: 'Kecepatan Putar Video',
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
                                            child: Text('1.0x'),
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
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            '${_playbackSpeed}x',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    IconButton(
                                      tooltip: fullscreenMode
                                          ? 'Keluar Layar Penuh'
                                          : 'Layar Penuh (Landscape)',
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        fullscreenMode
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _setFullscreenMode(!fullscreenMode);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        else
                          const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNowWatchingInfoStrip() {
    final item = _currentItem;
    final provider = context.watch<MusicProvider>();
    final isFav = provider.isFavorite(item.id);

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          if (item.hasValidNetworkArtwork)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                item.artworkUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const AppLogo(size: 44),
              ),
            )
          else
            const AppLogo(size: 44, borderRadius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.groupTitle ?? item.directoryName} • Channel ${_currentIndex + 1}/${widget.playlistItems.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Mode Audio Saja',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.headphones_rounded,
              color: AppColors.textSecondary,
            ),
            onPressed: _switchToAudioOnlyMode,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppColors.spotifyGreen : AppColors.textSecondary,
            ),
            onPressed: () => provider.toggleFavorite(item),
          ),
          IconButton(
            tooltip: 'Layar Penuh',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.fullscreen_rounded,
              color: AppColors.spotifyGreen,
            ),
            onPressed: () => setState(() => _setFullscreenMode(true)),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelListPanel() {
    final q = _channelFilter.trim().toLowerCase();
    final indexedItems = <({int index, TrackItem item})>[];
    for (int i = 0; i < widget.playlistItems.length; i++) {
      final it = widget.playlistItems[i];
      if (q.isEmpty ||
          it.title.toLowerCase().contains(q) ||
          (it.groupTitle?.toLowerCase().contains(q) ?? false)) {
        indexedItems.add((index: i, item: it));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: TextField(
            controller: _channelSearchCtrl,
            onChanged: (v) => setState(() => _channelFilter = v),
            decoration: InputDecoration(
              hintText:
                  'Cari channel / video di playlist ini (${widget.playlistItems.length})...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: indexedItems.length,
            itemBuilder: (_, listIdx) {
              final entry = indexedItems[listIdx];
              final isPlayingThis = entry.index == _currentIndex;
              final ch = entry.item;

              return ListTile(
                dense: true,
                selected: isPlayingThis,
                selectedTileColor:
                    AppColors.netflixRed.withValues(alpha: 0.14),
                leading: ch.hasValidNetworkArtwork
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          ch.artworkUrl!,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const AppLogo(size: 38, borderRadius: 8),
                        ),
                      )
                    : const AppLogo(size: 38, borderRadius: 8),
                title: Text(
                  ch.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlayingThis
                        ? AppColors.netflixRed
                        : AppColors.textPrimary,
                    fontWeight:
                        isPlayingThis ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  ch.groupTitle ?? ch.directoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: isPlayingThis
                    ? const Icon(
                        Icons.live_tv_rounded,
                        color: AppColors.netflixRed,
                        size: 20,
                      )
                    : const Icon(
                        Icons.play_circle_outline_rounded,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                onTap: () {
                  if (Scaffold.maybeOf(context)?.isEndDrawerOpen == true) {
                    Navigator.pop(context);
                  }
                  unawaited(_loadChannelAtIndex(entry.index));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
