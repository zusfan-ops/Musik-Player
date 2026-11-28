import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../services/newtube_service.dart';
import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar_widget.dart';
import 'android_tv_shell.dart';
import 'm3u_video_player_screen.dart';
import 'onboarding_screen.dart';

class TvMoviesTab extends StatefulWidget {
  const TvMoviesTab({super.key});

  @override
  State<TvMoviesTab> createState() => _TvMoviesTabState();
}

class _TvMoviesTabState extends State<TvMoviesTab> {
  String _filter = 'Semua';

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();
    final items = jf.movies.where((m) {
      if (_filter == 'Semua') return true;
      return m.itemType == _filter;
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final f in const ['Semua', 'Movie', 'Episode', 'Video'])
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: TvFocusCard(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: _filter == f
                          ? AppColors.netflixRed
                          : Colors.white.withValues(alpha: 0.08),
                      child: Text(
                        f == 'Semua'
                            ? 'Semua (${jf.movies.length})'
                            : f == 'Movie'
                                ? 'Film'
                                : f == 'Episode'
                                    ? 'Serial'
                                    : 'Video',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              TvFocusCard(
                borderRadius: BorderRadius.circular(20),
                onTap: () => jf.refreshMovies(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.white.withValues(alpha: 0.08),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Muat Ulang',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      jf.isLoadingMovies
                          ? 'Memuat katalog Hallsem Cinema...'
                          : 'Belum ada film di kategori ini.',
                      style: const TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                      childAspectRatio: 0.66,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => TvMoviePosterCard(
                      movie: items[i],
                      jf: jf,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class TvLiveChannelsTab extends StatelessWidget {
  final String? selectedPlaylistId;
  final ValueChanged<String> onSelectPlaylist;

  const TvLiveChannelsTab({
    super.key,
    required this.selectedPlaylistId,
    required this.onSelectPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<MusicProvider>().playlists;
    if (playlists.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada playlist TV / CCTV.',
          style: TextStyle(color: Colors.white60, fontSize: 16),
        ),
      );
    }

    final active = playlists.firstWhere(
      (p) => p.id == selectedPlaylistId,
      orElse: () => playlists.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: ListView.separated(
              itemCount: playlists.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final pl = playlists[i];
                final isSelected = pl.id == active.id;
                return TvFocusCard(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelectPlaylist(pl.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    color: isSelected
                        ? AppColors.netflixRed
                        : Colors.white.withValues(alpha: 0.07),
                    child: Row(
                      children: [
                        Icon(
                          pl.name.toLowerCase().contains('cctv')
                              ? Icons.location_city_rounded
                              : Icons.live_tv_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pl.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${pl.tracks.length} channel',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.75,
              ),
              itemCount: active.tracks.length,
              itemBuilder: (ctx, i) {
                final ch = active.tracks[i];
                return TvFocusCard(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => M3uPlaybackLauncher.playItemList(
                    ctx,
                    active.tracks,
                    initialIndex: i,
                    forceVideoPlayer: true,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1A2030), Color(0xFF121622)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.videocam_rounded,
                              color: AppColors.netflixRed,
                              size: 22,
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.play_circle_filled_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ch.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            if (ch.groupTitle != null && ch.groupTitle!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  ch.groupTitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11.5,
                                  ),
                                ),
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
        ],
      ),
    );
  }
}

class TvYouTubeTab extends StatefulWidget {
  const TvYouTubeTab({super.key});

  @override
  State<TvYouTubeTab> createState() => _TvYouTubeTabState();
}

class _TvYouTubeTabState extends State<TvYouTubeTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<NewTubeItem> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initPersonalizedTvFeed());
  }

  Future<void> _initPersonalizedTvFeed() async {
    final q = await YouTubeRecommendationPrefs.getInitialQuery();
    if (!mounted) return;
    await _search(q, recordHistory: false);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q, {bool recordHistory = true}) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    if (recordHistory) {
      unawaited(YouTubeRecommendationPrefs.recordSearch(trimmed));
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await NewTubeService.searchVideos(trimmed);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: 'Cari video YouTube...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.09),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              for (final preset in const ['Berita Live', 'Lo-Fi Beats', 'Rock Hits'])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TvFocusCard(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      _searchCtrl.text = preset;
                      unawaited(_search(preset));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      color: Colors.white.withValues(alpha: 0.08),
                      child: Text(
                        preset,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.netflixRed),
                  )
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.25,
                        ),
                        itemCount: _results.length,
                        itemBuilder: (ctx, i) {
                          final item = _results[i];
                          return TvFocusCard(
                            onTap: () {
                              final tracks = _results
                                  .map(
                                    (r) => r.toTrackItem(
                                      streamUrl:
                                          'https://www.youtube.com/watch?v=${r.videoId}',
                                      asVideo: true,
                                    ),
                                  )
                                  .toList();
                              M3uPlaybackLauncher.playItemList(
                                ctx,
                                tracks,
                                initialIndex: i,
                                forceVideoPlayer: true,
                              );
                            },
                            child: Container(
                              color: const Color(0xFF141824),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Image.network(
                                      item.thumbnailUrl,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: const Color(0xFF1F2638),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class TvMusicTab extends StatelessWidget {
  const TvMusicTab({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicProvider>();
    final tracks = music.allTracks;
    final current = music.currentTrack;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      child: Row(
        children: [
          Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppColors.spotifyGreen.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: AppColors.spotifyGreen,
                    size: 84,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  current?.title ?? 'Pilih Lagu dari Daftar',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  current?.artist ?? '${tracks.length} lagu tersedia',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TvFocusCard(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => music.playPrevious(),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(width: 14),
                    TvFocusCard(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () => music.togglePlayPause(),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        color: AppColors.spotifyGreen,
                        child: Icon(
                          music.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    TvFocusCard(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => music.playNext(),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: tracks.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada lagu lokal ditemukan.',
                      style: TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  )
                : ListView.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final TrackItem t = tracks[i];
                      final isPlaying = current?.id == t.id;
                      return TvFocusCard(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => music.playTrackList(tracks, initialIndex: i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: isPlaying
                              ? AppColors.spotifyGreen.withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.05),
                          child: Row(
                            children: [
                              Icon(
                                isPlaying
                                    ? Icons.graphic_eq_rounded
                                    : Icons.music_note_rounded,
                                color: isPlaying
                                    ? AppColors.spotifyGreen
                                    : Colors.white60,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      '${t.artist} • ${t.album}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class TvSettingsTab extends StatelessWidget {
  const TvSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const UserAvatarWidget(size: 64),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jf.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hallsem Cinema: ${jf.serverName} (${jf.movies.length} film)',
                      style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: TvFocusCard(
                onTap: () => jf.connectAndSyncBuiltInJellyfin(),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  color: Colors.white.withValues(alpha: 0.07),
                  child: const Row(
                    children: [
                      Icon(Icons.sync_rounded, color: AppColors.spotifyGreen),
                      SizedBox(width: 12),
                      Text(
                        'Sinkronisasi Hallsem Cinema',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TvFocusCard(
                onTap: () => UpdateCheckerService.instance.checkAndShowUpdateDialog(
                  context,
                  isManualCheck: true,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  color: Colors.white.withValues(alpha: 0.07),
                  child: const Row(
                    children: [
                      Icon(Icons.system_update_rounded, color: Color(0xFF64B5F6)),
                      SizedBox(width: 12),
                      Text(
                        'Cek Pembaruan Aplikasi',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TvFocusCard(
                onTap: () => OnboardingScreen.show(context),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  color: Colors.white.withValues(alpha: 0.07),
                  child: const Row(
                    children: [
                      Icon(Icons.menu_book_rounded, color: Colors.white70),
                      SizedBox(width: 12),
                      Text(
                        'Panduan Penggunaan',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
