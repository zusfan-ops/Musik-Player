import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../screens/m3u_video_player_screen.dart';
import '../theme/app_theme.dart';

class TrackTile extends StatelessWidget {
  final TrackItem track;
  final VoidCallback onTap;
  final int? indexNumber;
  final bool showDirectoryBadge;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.indexNumber,
    this.showDirectoryBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final isCurrent = provider.currentTrack?.id == track.id;
    final isPlaying = isCurrent && provider.isPlaying;
    final isFav = provider.isFavorite(track.id);
    final isDownloading = provider.isTrackDownloading(track.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isCurrent
              ? AppColors.spotifyGreen.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isCurrent
              ? Border.all(
                  color: AppColors.spotifyGreen.withValues(alpha: 0.35),
                )
              : null,
        ),
        child: Row(
          children: [
            if (indexNumber != null)
              SizedBox(
                width: 28,
                child: isCurrent
                    ? Icon(
                        isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.pause_circle_filled_rounded,
                        color: AppColors.spotifyGreen,
                        size: 20,
                      )
                    : Text(
                        '$indexNumber',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
              ),
            _TrackArtworkThumb(track: track, isCurrent: isCurrent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent
                          ? AppColors.spotifyGreen
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _SourceBadge(track: track),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          showDirectoryBadge
                              ? '${track.artist} • ${track.directoryName}'
                              : track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (track.isVideo)
              IconButton(
                tooltip: 'Tonton di Video / TV Player',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.ondemand_video_rounded,
                  color: AppColors.netflixRed,
                  size: 21,
                ),
                onPressed: () => M3uPlaybackLauncher.playItemList(
                  context,
                  [track],
                  forceVideoPlayer: true,
                ),
              )
            else if (!track.isLocalFile &&
                !track.hasOfflineCache &&
                !(track.durationSeconds != null && track.durationSeconds! < 0) &&
                !track.pathOrUrl.toLowerCase().contains('.m3u8'))
              isDownloading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.neonCyan,
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Unduh untuk Offline',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.download_for_offline_outlined,
                        color: AppColors.neonCyan,
                        size: 21,
                      ),
                      onPressed: () async {
                        final ok = await provider.downloadTrackOffline(track);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? '"${track.title}" tersimpan untuk mode offline!'
                                    : (provider.lastError ??
                                        'Gagal mengunduh lagu.'),
                              ),
                            ),
                          );
                        }
                      },
                    ),
            IconButton(
              tooltip: isFav ? 'Hapus Favorit' : 'Tambah Favorit',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? AppColors.spotifyGreen : AppColors.textMuted,
                size: 20,
              ),
              onPressed: () => provider.toggleFavorite(track),
            ),
            IconButton(
              tooltip: 'Opsi Lagu',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
              onPressed: () => _showTrackOptions(context, provider, track),
            ),
          ],
        ),
      ),
    );
  }

  void _showTrackOptions(
    BuildContext context,
    MusicProvider provider,
    TrackItem track,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const AppLogo(size: 44),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    track.pathOrUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Divider(color: AppColors.surfaceHighlight),
                ListTile(
                  leading: const Icon(
                    Icons.play_circle_fill_rounded,
                    color: AppColors.spotifyGreen,
                  ),
                  title: Text(
                    track.isVideo ? 'Tonton Video / Live TV' : 'Putar Sekarang',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onTap();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.ondemand_video_rounded,
                    color: AppColors.netflixRed,
                  ),
                  title: const Text('Buka di Layar Video Player'),
                  onTap: () {
                    Navigator.pop(ctx);
                    M3uPlaybackLauncher.playItemList(
                      context,
                      [track],
                      forceVideoPlayer: true,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.queue_music_rounded,
                    color: AppColors.neonCyan,
                  ),
                  title: const Text('Tambahkan ke Antrean Putar'),
                  onTap: () {
                    Navigator.pop(ctx);
                    provider.addToQueue(track);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ditambahkan ke antrean: ${track.title}'),
                      ),
                    );
                  },
                ),
                if (!track.isVideo &&
                    !track.isLocalFile &&
                    !track.hasOfflineCache &&
                    !(track.durationSeconds != null &&
                        track.durationSeconds! < 0) &&
                    !track.pathOrUrl.toLowerCase().contains('.m3u8'))
                  ListTile(
                    leading: const Icon(
                      Icons.offline_pin_rounded,
                      color: AppColors.neonCyan,
                    ),
                    title: const Text('Simpan Audio untuk Mode Offline'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await provider.downloadTrackOffline(track);
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.textSecondary,
                  ),
                  title: const Text('Detail Lokasi & Direktori'),
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog<void>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: Text(track.title),
                        content: SelectableText(
                          'Artis / Grup: ${track.artist}\n'
                          'Direktori: ${track.directoryPath}\n'
                          'Tipe Sumber: ${track.isLocalFile ? "File Lokal Offline" : (track.hasOfflineCache ? "Link M3U (Tersimpan Offline)" : "Link Stream M3U")}\n'
                          'Lokasi Asli: ${track.pathOrUrl}'
                          '${track.offlineCachePath != null ? "\nCache Offline: ${track.offlineCachePath}" : ""}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx),
                            child: const Text('Tutup'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrackArtworkThumb extends StatelessWidget {
  final TrackItem track;
  final bool isCurrent;

  const _TrackArtworkThumb({
    required this.track,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    if (track.hasValidNetworkArtwork) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          track.artworkUrl!,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const AppLogo(size: 46, borderRadius: 10),
        ),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        const AppLogo(size: 46, borderRadius: 10),
        if (isCurrent)
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.equalizer_rounded,
              color: AppColors.spotifyGreen,
              size: 22,
            ),
          ),
      ],
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final TrackItem track;

  const _SourceBadge({required this.track});

  @override
  Widget build(BuildContext context) {
    final bool offlineReady = track.isOfflineReady;
    final Color badgeColor = track.isVideo
        ? AppColors.netflixRed
        : (offlineReady ? AppColors.spotifyGreen : AppColors.neonCyan);
    final String text = track.isVideo
        ? (track.isLocalFile ? 'VIDEO' : 'TV / VIDEO')
        : (track.isLocalFile
            ? track.fileExtension
            : (track.hasOfflineCache ? 'OFFLINE' : 'LINK'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: badgeColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
