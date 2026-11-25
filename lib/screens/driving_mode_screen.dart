import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../theme/app_theme.dart';

/// High-contrast, extra-large-button Driving Mode (Car UI) for safe playback control on the road.
class DrivingModeScreen extends StatelessWidget {
  const DrivingModeScreen({super.key});

  static void show(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const DrivingModeScreen(),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final track = provider.currentTrack;
    final offlineTracks = provider.allOfflineMusicTracks;

    return Scaffold(
      backgroundColor: const Color(0xFF101113),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: [
              // Top bar
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.spotifyGreen.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.spotifyGreen.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.directions_car_rounded,
                          color: AppColors.spotifyGreen,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'DRIVING MODE',
                          style: TextStyle(
                            color: AppColors.spotifyGreen,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: const Text(
                      'Keluar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Track info
              Icon(
                track != null ? Icons.graphic_eq_rounded : Icons.library_music_rounded,
                size: 54,
                color: AppColors.spotifyGreen,
              ),
              const SizedBox(height: 18),
              Text(
                track?.title ?? 'Tidak Ada Lagu Diputar',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                track != null
                    ? '${track.artist} • ${track.directoryName}'
                    : (offlineTracks.isNotEmpty
                        ? '${offlineTracks.length} lagu offline siap diputar'
                        : 'Ketuk Putar Offline atau pilih lagu'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 24),

              // Progress bar
              ValueListenableBuilder<Duration>(
                valueListenable: provider.positionListenable,
                builder: (_, pos, _) {
                  final dur = provider.duration;
                  final ratio = dur.inMilliseconds > 0
                      ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0;
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.spotifyGreen,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(pos),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _formatDuration(dur),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              const Spacer(),

              // Extra-large Car Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CarCircleBtn(
                    icon: Icons.skip_previous_rounded,
                    size: 76,
                    iconSize: 42,
                    bgColor: Colors.white.withValues(alpha: 0.12),
                    onTap: track != null ? provider.playPrevious : null,
                  ),
                  _CarCircleBtn(
                    icon: provider.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 104,
                    iconSize: 56,
                    bgColor: AppColors.spotifyGreen,
                    onTap: () {
                      if (track != null) {
                        provider.togglePlayPause();
                      } else if (offlineTracks.isNotEmpty) {
                        provider.playTrackList(offlineTracks);
                      }
                    },
                  ),
                  _CarCircleBtn(
                    icon: Icons.skip_next_rounded,
                    size: 76,
                    iconSize: 42,
                    bgColor: Colors.white.withValues(alpha: 0.12),
                    onTap: track != null ? provider.playNext : null,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Bottom quick toggles
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CarActionPill(
                    icon: Icons.shuffle_rounded,
                    label: provider.shuffleEnabled ? 'Acak: ON' : 'Acak: OFF',
                    active: provider.shuffleEnabled,
                    onTap: provider.toggleShuffle,
                  ),
                  _CarActionPill(
                    icon: Icons.offline_pin_rounded,
                    label: 'Putar Offline',
                    active: false,
                    onTap: offlineTracks.isNotEmpty
                        ? () => provider.playTrackList(offlineTracks)
                        : null,
                  ),
                  _CarActionPill(
                    icon: provider.repeatMode == RepeatCycleMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    label: provider.repeatMode == RepeatCycleMode.off
                        ? 'Ulang: OFF'
                        : (provider.repeatMode == RepeatCycleMode.one
                            ? 'Ulang: 1'
                            : 'Ulang: Semua'),
                    active: provider.repeatMode != RepeatCycleMode.off,
                    onTap: provider.cycleRepeatMode,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarCircleBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color bgColor;
  final VoidCallback? onTap;

  const _CarCircleBtn({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap != null ? bgColor : Colors.white.withValues(alpha: 0.05),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: onTap != null ? Colors.white : Colors.white30,
          ),
        ),
      ),
    );
  }
}

class _CarActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _CarActionPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? AppColors.spotifyGreen : Colors.white,
        backgroundColor: active
            ? AppColors.spotifyGreen.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.06),
        side: BorderSide(
          color: active
              ? AppColors.spotifyGreen
              : Colors.white.withValues(alpha: 0.16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}
