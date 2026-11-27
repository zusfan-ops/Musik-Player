import 'package:flutter/material.dart';

import '../models/jellyfin_profile_models.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../theme/app_theme.dart';
import 'm3u_video_player_screen.dart';

enum JellyfinSection { film, musik, tv }

/// Sliver list of Jellyfin Music tracks or Live TV channels for Hallsem Cinema.
class JellyfinMediaListSliver extends StatelessWidget {
  final JellyfinProviderAccess access;
  const JellyfinMediaListSliver({super.key, required this.access});

  @override
  Widget build(BuildContext context) {
    final jf = access.jf;
    final isMusic = access.section == JellyfinSection.musik;
    final loading = isMusic ? jf.isLoadingMusic : jf.isLoadingTv;
    final loaded = isMusic ? jf.musicLoaded : jf.tvLoaded;
    final error = isMusic ? jf.musicError : jf.tvError;
    final all = isMusic ? jf.musicTracks : jf.tvChannels;

    final q = access.query.trim().toLowerCase();
    final entries = all.where((e) {
      if (q.isEmpty) return true;
      return e.name.toLowerCase().contains(q) ||
          (e.artist?.toLowerCase().contains(q) ?? false) ||
          (e.album?.toLowerCase().contains(q) ?? false) ||
          (e.currentProgram?.toLowerCase().contains(q) ?? false);
    }).toList();

    if (loading && all.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.netflixRed),
        ),
      );
    }

    if (entries.isEmpty) {
      final String message;
      if (error != null) {
        message = error;
      } else if (!loaded) {
        message = 'Memuat daftar...';
      } else if (all.isEmpty) {
        message = isMusic
            ? 'Belum ada musik di server Hallsem Cinema.'
            : 'Belum ada channel TV di server Hallsem Cinema.\n'
                'Channel muncul jika Live TV (tuner / playlist M3U) sudah '
                'dikonfigurasi di server Jellyfin.';
      } else {
        message = 'Tidak ada hasil yang cocok dengan pencarian.';
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.subtext(context)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: isMusic ? jf.refreshMusic : jf.refreshTvChannels,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Muat Ulang'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 120),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, idx) {
            final entry = entries[idx];
            return _MediaEntryTile(
              entry: entry,
              jf: jf,
              isMusic: isMusic,
              onTap: () {
                if (isMusic) {
                  M3uPlaybackLauncher.playItemList(
                    ctx,
                    entries.map(jf.musicEntryToTrack).toList(),
                    initialIndex: idx,
                  );
                } else {
                  M3uPlaybackLauncher.playItemList(
                    ctx,
                    entries.map(jf.tvEntryToTrack).toList(),
                    initialIndex: idx,
                    forceVideoPlayer: true,
                  );
                }
              },
            );
          },
          childCount: entries.length,
        ),
      ),
    );
  }
}

class JellyfinProviderAccess {
  final ProfileJellyfinProvider jf;
  final JellyfinSection section;
  final String query;
  const JellyfinProviderAccess({
    required this.jf,
    required this.section,
    required this.query,
  });
}

class _MediaEntryTile extends StatelessWidget {
  final JellyfinMediaEntry entry;
  final ProfileJellyfinProvider jf;
  final bool isMusic;
  final VoidCallback onTap;

  const _MediaEntryTile({
    required this.entry,
    required this.jf,
    required this.isMusic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = isMusic
        ? [
            if (entry.artist != null && entry.artist!.isNotEmpty) entry.artist!,
            if (entry.album != null && entry.album!.isNotEmpty) entry.album!,
          ].join(' • ')
        : [
            if (entry.channelNumber != null && entry.channelNumber!.isNotEmpty)
              'CH ${entry.channelNumber}',
            entry.currentProgram ?? 'Live TV',
          ].join(' • ');

    final fallbackIcon = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.elevated(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isMusic ? Icons.music_note_rounded : Icons.live_tv_rounded,
        color: AppColors.netflixRed,
      ),
    );

    return ListTile(
      onTap: onTap,
      leading: entry.hasPrimaryImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                jf.artworkUrlForEntry(entry),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallbackIcon,
              ),
            )
          : fallbackIcon,
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.text(context),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.subtext(context), fontSize: 12),
      ),
      trailing: Icon(
        Icons.play_circle_outline_rounded,
        color: AppColors.subtext(context),
      ),
    );
  }
}
