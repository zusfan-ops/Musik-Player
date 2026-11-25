import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../services/lyrics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/equalizer_sheet.dart';
import 'm3u_video_player_screen.dart';

class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NowPlayingSheet(),
    );
  }

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  bool _showLyrics = false;
  String? _loadedLyricsTrackId;
  List<LyricLine> _lyrics = const [];
  bool _loadingLyrics = false;
  int _lastActiveLyricIdx = -1;
  final ScrollController _lyricsScrollController = ScrollController();

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _ensureLyricsLoaded(TrackItem track) {
    if (_loadedLyricsTrackId == track.id) return;
    _loadedLyricsTrackId = track.id;
    _lastActiveLyricIdx = -1;
    _loadingLyrics = true;
    unawaited(
      LyricsService.loadLyricsForTrack(track).then((lines) {
        if (!mounted || _loadedLyricsTrackId != track.id) return;
        setState(() {
          _lyrics = lines;
          _loadingLyrics = false;
        });
      }),
    );
  }

  void _scrollToLyricIndex(int index) {
    if (!_lyricsScrollController.hasClients || index < 0) return;
    final targetOffset = (index * 44.0 - 70.0).clamp(
      0.0,
      _lyricsScrollController.position.maxScrollExtent,
    );
    _lyricsScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final track = provider.currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    _ensureLyricsLoaded(track);

    final maxMs = provider.duration.inMilliseconds > 0
        ? provider.duration.inMilliseconds.toDouble()
        : 1.0;
    final isFav = provider.isFavorite(track.id);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF16243B),
            Color(0xFF0E1320),
            Color(0xFF090B10),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final availH = constraints.maxHeight;
            final availW = constraints.maxWidth;
            final artSize = math
                .min(availW * 0.68, availH * 0.36)
                .clamp(120.0, 300.0);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0.0, availH - 30),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top drag handle & header
                    Column(
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 30,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    track.playlistId != null
                                        ? 'MEMUTAR DARI PLAYLIST M3U'
                                        : 'MEMUTAR DARI DIREKTORI',
                                    style: const TextStyle(
                                      color: AppColors.neonCyan,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.directoryName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: provider.isCastConnected
                                  ? 'Terhubung ke ${provider.castDeviceName ?? 'Cast'}'
                                  : 'Putar ke Chromecast / Google Nest',
                              icon: Icon(
                                provider.isCastConnected
                                    ? Icons.cast_connected_rounded
                                    : Icons.cast_rounded,
                                color: provider.isCastConnected
                                    ? AppColors.spotifyGreen
                                    : Colors.white,
                              ),
                              onPressed: () {
                                if (provider.isCastConnected) {
                                  showDialog<void>(
                                    context: context,
                                    builder: (dCtx) => AlertDialog(
                                      backgroundColor: AppColors.surface,
                                      title: const Text('Google Cast / Speaker'),
                                      content: Text(
                                        'Audio sedang diputar ke "${provider.castDeviceName ?? 'Perangkat Cast'}".',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dCtx),
                                          child: const Text('Tutup'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(dCtx);
                                            provider.disconnectCast();
                                          },
                                          child: const Text(
                                            'Putuskan',
                                            style: TextStyle(color: AppColors.netflixRed),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  provider.openCastPicker();
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Lirik Lagu (.lrc)',
                              icon: Icon(
                                Icons.lyrics_rounded,
                                color: _showLyrics
                                    ? AppColors.spotifyGreen
                                    : (_lyrics.isNotEmpty
                                        ? AppColors.neonCyan
                                        : AppColors.textSecondary),
                              ),
                              onPressed: () =>
                                  setState(() => _showLyrics = !_showLyrics),
                            ),
                            IconButton(
                              tooltip: 'Antrean Putar',
                              icon: const Icon(Icons.queue_music_rounded),
                              onPressed: () => _showQueueSheet(context),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Centerpiece: Synchronized LRC Lyrics OR Artwork
                    if (_showLyrics)
                      Container(
                        width: double.infinity,
                        height: artSize,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: _loadingLyrics
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.spotifyGreen,
                                ),
                              )
                            : _lyrics.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.lyrics_outlined,
                                          size: 40,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          'File lirik (.lrc) tidak ditemukan',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Letakkan file .lrc dengan nama yang sama di folder lagu untuk lirik sinkron otomatis.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: AppColors.textSecondary
                                                .withValues(alpha: 0.85),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ValueListenableBuilder<Duration>(
                                    valueListenable: provider.positionListenable,
                                    builder: (_, pos, _) {
                                      final activeIdx =
                                          LyricsService.activeLineIndex(
                                        _lyrics,
                                        pos,
                                      );
                                      if (activeIdx != _lastActiveLyricIdx &&
                                          activeIdx >= 0) {
                                        _lastActiveLyricIdx = activeIdx;
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            _scrollToLyricIndex(activeIdx);
                                          }
                                        });
                                      }
                                      return ListView.builder(
                                        controller: _lyricsScrollController,
                                        itemCount: _lyrics.length,
                                        itemBuilder: (_, i) {
                                          final line = _lyrics[i];
                                          final isActive = i == activeIdx;
                                          return InkWell(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            onTap: () =>
                                                provider.seekTo(line.timestamp),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 8,
                                                horizontal: 6,
                                              ),
                                              child: Text(
                                                line.text,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: isActive
                                                      ? AppColors.spotifyGreen
                                                      : AppColors.textSecondary
                                                          .withValues(
                                                              alpha: 0.72),
                                                  fontSize: isActive ? 17 : 14,
                                                  fontWeight: isActive
                                                      ? FontWeight.w900
                                                      : FontWeight.w500,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                      )
                    else if (track.hasValidNetworkArtwork)
                      Container(
                        width: artSize,
                        height: artSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.neonCyan.withValues(alpha: 0.25),
                              blurRadius: 36,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: Image.network(
                            track.artworkUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => AppLogo(
                              size: artSize,
                              borderRadius: 26,
                              showGlow: true,
                            ),
                          ),
                        ),
                      )
                    else
                      AppLogo(
                        size: artSize,
                        borderRadius: 28,
                        showGlow: true,
                      ),

                    const SizedBox(height: 16),

                    // Bottom controls section
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: track.isOfflineReady
                                              ? AppColors.spotifyGreen
                                                  .withValues(alpha: 0.18)
                                              : AppColors.neonCyan
                                                  .withValues(alpha: 0.18),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          track.isOfflineReady
                                              ? 'OFFLINE READY'
                                              : 'LIVE LINK',
                                          style: TextStyle(
                                            color: track.isOfflineReady
                                                ? AppColors.spotifyGreen
                                                : AppColors.neonCyan,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          track.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              iconSize: 28,
                              icon: Icon(
                                isFav
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: isFav
                                    ? AppColors.spotifyGreen
                                    : AppColors.textSecondary,
                              ),
                              onPressed: () => provider.toggleFavorite(track),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Decoupled high-frequency Slider + Timestamp listener
                        ValueListenableBuilder<Duration>(
                          valueListenable: provider.positionListenable,
                          builder: (_, pos, _) {
                            final currentMs = pos.inMilliseconds
                                .toDouble()
                                .clamp(0.0, maxMs);
                            return Column(
                              children: [
                                Slider(
                                  value: currentMs,
                                  min: 0.0,
                                  max: maxMs,
                                  onChanged:
                                      provider.duration.inMilliseconds > 0
                                          ? (val) => provider.seekTo(
                                                Duration(
                                                  milliseconds: val.round(),
                                                ),
                                              )
                                          : null,
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(pos),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        provider.duration.inMilliseconds > 0
                                            ? _formatDuration(provider.duration)
                                            : (track.durationSeconds != null &&
                                                    track.durationSeconds! > 0
                                                ? _formatDuration(
                                                    Duration(
                                                      seconds: track
                                                          .durationSeconds!,
                                                    ),
                                                  )
                                                : 'LIVE'),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 10),

                        // Main Spotify Transport Controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              tooltip: 'Acak (Shuffle)',
                              iconSize: 24,
                              icon: Icon(
                                Icons.shuffle_rounded,
                                color: provider.shuffleEnabled
                                    ? AppColors.spotifyGreen
                                    : AppColors.textSecondary,
                              ),
                              onPressed: provider.toggleShuffle,
                            ),
                            IconButton(
                              iconSize: 38,
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: Colors.white,
                              ),
                              onPressed: provider.playPrevious,
                            ),
                            GestureDetector(
                              onTap: provider.togglePlayPause,
                              child: Container(
                                width: 66,
                                height: 66,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.spotifyGreen,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.spotifyGreen
                                          .withValues(alpha: 0.42),
                                      blurRadius: 22,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: provider.isBuffering
                                    ? const SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Colors.black,
                                        ),
                                      )
                                    : Icon(
                                        provider.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.black,
                                        size: 38,
                                      ),
                              ),
                            ),
                            IconButton(
                              iconSize: 38,
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: Colors.white,
                              ),
                              onPressed: provider.playNext,
                            ),
                            IconButton(
                              tooltip: 'Mode Ulang (Repeat)',
                              iconSize: 24,
                              icon: Icon(
                                provider.repeatMode == RepeatCycleMode.one
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                color:
                                    provider.repeatMode != RepeatCycleMode.off
                                        ? AppColors.spotifyGreen
                                        : AppColors.textSecondary,
                              ),
                              onPressed: provider.cycleRepeatMode,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Bottom Utility Bar (Speed, Sleep Timer, Offline Download, Queue)
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => EqualizerSheet.show(context),
                              icon: Icon(
                                Icons.equalizer_rounded,
                                size: 18,
                                color: provider.equalizerEnabled
                                    ? AppColors.spotifyGreen
                                    : AppColors.textSecondary,
                              ),
                              label: Text(
                                provider.equalizerEnabled ? 'EQ On' : 'EQ',
                                style: TextStyle(
                                  color: provider.equalizerEnabled
                                      ? AppColors.spotifyGreen
                                      : AppColors.textSecondary,
                                  fontWeight: provider.equalizerEnabled
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  _showSpeedDialog(context, provider),
                              icon: const Icon(
                                Icons.speed_rounded,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              label: Text(
                                '${provider.playbackSpeed}x',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  _showSleepTimerDialog(context, provider),
                              icon: Icon(
                                Icons.bedtime_outlined,
                                size: 18,
                                color: provider.sleepTimerRemaining != null
                                    ? AppColors.neonCyan
                                    : AppColors.textSecondary,
                              ),
                              label: Text(
                                provider.sleepTimerRemaining != null
                                    ? '${provider.sleepTimerRemaining!.inMinutes + 1}m'
                                    : 'Timer',
                                style: TextStyle(
                                  color: provider.sleepTimerRemaining != null
                                      ? AppColors.neonCyan
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                final q = provider.queue.isNotEmpty
                                    ? provider.queue
                                    : [track];
                                final idx = provider.currentIndex >= 0
                                    ? provider.currentIndex
                                    : 0;
                                Navigator.pop(context);
                                M3uPlaybackLauncher.playItemList(
                                  context,
                                  q,
                                  initialIndex: idx,
                                  forceVideoPlayer: true,
                                );
                              },
                              icon: const Icon(
                                Icons.live_tv_rounded,
                                size: 18,
                                color: AppColors.netflixRed,
                              ),
                              label: const Text(
                                'Layar Video',
                                style: TextStyle(
                                  color: AppColors.netflixRed,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (!track.isVideo &&
                                !track.isLocalFile &&
                                !track.hasOfflineCache &&
                                !(track.durationSeconds != null &&
                                    track.durationSeconds! < 0))
                              TextButton.icon(
                                onPressed: provider.isTrackDownloading(track.id)
                                    ? null
                                    : () => provider.downloadTrackOffline(track),
                                icon: const Icon(
                                  Icons.download_rounded,
                                  size: 18,
                                  color: AppColors.neonCyan,
                                ),
                                label: const Text(
                                  'Simpan Offline',
                                  style: TextStyle(color: AppColors.neonCyan),
                                ),
                              )
                            else
                              TextButton.icon(
                                onPressed: () => _showQueueSheet(context),
                                icon: const Icon(
                                  Icons.playlist_play_rounded,
                                  size: 20,
                                  color: AppColors.textSecondary,
                                ),
                                label: Text(
                                  'Antrean (${provider.queue.length})',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context, MusicProvider provider) {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Kecepatan Pemutaran',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            for (final s in speeds)
              ListTile(
                title: Text('${s}x'),
                trailing: provider.playbackSpeed == s
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppColors.spotifyGreen,
                      )
                    : null,
                onTap: () {
                  provider.setPlaybackSpeed(s);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerDialog(BuildContext context, MusicProvider provider) {
    final options = <({String label, Duration? dur})>[
      (label: 'Matikan Timer', dur: null),
      (label: '15 Menit', dur: const Duration(minutes: 15)),
      (label: '30 Menit', dur: const Duration(minutes: 30)),
      (label: '45 Menit', dur: const Duration(minutes: 45)),
      (label: '60 Menit', dur: const Duration(minutes: 60)),
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sleep Timer Otomatis',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            for (final opt in options)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(opt.label),
                onTap: () {
                  provider.setSleepTimer(opt.dur);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showQueueSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            final provider = ctx.watch<MusicProvider>();
            final List<TrackItem> q = provider.queue;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Antrean Aktif (${q.length} Lagu)',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.surfaceHighlight),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: q.length,
                    itemBuilder: (_, idx) {
                      final item = q[idx];
                      final active = idx == provider.currentIndex;
                      return ListTile(
                        leading: active
                            ? const Icon(
                                Icons.equalizer_rounded,
                                color: AppColors.spotifyGreen,
                              )
                            : Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active
                                ? AppColors.spotifyGreen
                                : AppColors.textPrimary,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${item.artist} • ${item.directoryName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => provider.jumpToQueueIndex(idx),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
