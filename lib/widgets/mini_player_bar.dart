import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../screens/now_playing_sheet.dart';
import '../theme/app_theme.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final track = provider.currentTrack;
    if (!provider.isMiniPlayerVisible || track == null) {
      return const SizedBox.shrink();
    }

    final totalMs = provider.duration.inMilliseconds;

    return Dismissible(
      key: ValueKey('mini_player_${track.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => provider.hideMiniPlayer(),
      child: GestureDetector(
        onTap: () => NowPlayingSheet.show(context),
        child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1B1918),
              Color(0xFF141312),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Row(
                  children: [
                    const AppLogo(size: 42, borderRadius: 10),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                track.isOfflineReady
                                    ? Icons.offline_bolt_rounded
                                    : Icons.wifi_tethering_rounded,
                                size: 12,
                                color: AppColors.spotifyGreen,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${track.artist} • ${track.directoryName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        provider.isFavorite(track.id)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: provider.isFavorite(track.id)
                            ? AppColors.spotifyGreen
                            : AppColors.textSecondary,
                        size: 21,
                      ),
                      onPressed: () => provider.toggleFavorite(track),
                    ),
                    provider.isBuffering
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                                color: AppColors.spotifyGreen,
                              ),
                            ),
                          )
                        : IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              provider.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: provider.togglePlayPause,
                          ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                      onPressed: provider.playNext,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Sembunyikan Play Bar',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: provider.hideMiniPlayer,
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<Duration>(
                valueListenable: provider.positionListenable,
                builder: (_, pos, _) {
                  final progress = totalMs > 0
                      ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                      : 0.0;
                  return LinearProgressIndicator(
                    value: progress,
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.spotifyGreen,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
