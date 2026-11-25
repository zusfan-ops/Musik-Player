import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';
import '../widgets/user_avatar_widget.dart';
import 'directories_screen.dart';
import 'jellyfin_movies_screen.dart';
import 'library_search_screen.dart';
import 'm3u_video_player_screen.dart';
import 'playlists_screen.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onNavigateTab;

  const HomeScreen({
    super.key,
    required this.onNavigateTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedChip = 'Semua';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final jfProvider = context.watch<ProfileJellyfinProvider>();
    final directories = provider.combinedDirectoryGroups;
    final playlists = provider.playlists;
    final recents = provider.recentTracks;
    final topTracks = provider.topPlayedTracks;
    final allTracks = provider.allTracks;

    final List<TrackItem> previewTracks = switch (_selectedChip) {
      'Offline Ready' => allTracks.where((t) => t.isOfflineReady).toList(),
      'Direktori' => [for (final g in directories) ...g.tracks],
      'TV' => [
          for (final pl in playlists)
            if (pl.isEnabled) ...pl.tracks,
        ],
      _ => allTracks,
    };
    final int previewCount =
        previewTracks.length > 15 ? 15 : previewTracks.length;

    return CustomScrollView(
      slivers: [
        // Sticky Translucent Netflix + Spotify Header
        SliverAppBar(
          pinned: true,
          backgroundColor: AppColors.background.withValues(alpha: 0.97),
          titleSpacing: 16,
          title: const Row(
            children: [
              AppLogo(size: 32, borderRadius: 9),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'MediaCenter',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Cari Lagu & Koleksi Favorit',
              icon: const Icon(Icons.search_rounded),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const LibrarySearchScreen(),
                  ),
                );
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Tambah Playlist TV (File / Link)',
              icon: const Icon(Icons.playlist_add_circle_outlined),
              onPressed: () => AddM3uBottomSheet.show(context),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Pilih / Scan Direktori Musik',
              icon: provider.isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.spotifyGreen,
                      ),
                    )
                  : const Icon(Icons.create_new_folder_outlined),
              onPressed: provider.isScanning
                  ? null
                  : () => provider.pickAndAddDirectory(),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 2),
              child: UserAvatarWidget(
                size: 30,
                onTap: () => widget.onNavigateTab(5),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  for (final label in const [
                    'Semua',
                    'Direktori',
                    'TV',
                    'Offline Ready',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterPill(
                        label: label,
                        selected: _selectedChip == label,
                        onTap: () => setState(() => _selectedChip = label),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Error Banner if any
        if (provider.lastError != null)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.netflixRed.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.netflixRed.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.netflixRed,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      provider.lastError!,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: provider.clearError,
                  ),
                ],
              ),
            ),
          ),

        // In-App GitHub Release Update Banner (when newer APK exists)
        SliverToBoxAdapter(
          child: ValueListenableBuilder<AppRelease?>(
            valueListenable:
                UpdateCheckerService.instance.availableUpdateNotifier,
            builder: (ctx, rel, _) {
              if (rel == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.spotifyGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.spotifyGreen.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.system_update_rounded,
                      color: AppColors.spotifyGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Update v${rel.versionClean} tersedia!',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => UpdateCheckerService.instance
                          .checkAndShowUpdateDialog(ctx, isManualCheck: true),
                      child: const Text(
                        'Unduh',
                        style: TextStyle(
                          color: AppColors.spotifyGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // 1. NETFLIX CINEMA HERO BILLBOARD
        SliverToBoxAdapter(
          child: _NetflixHeroBillboard(
            allTracks: allTracks,
            playlists: playlists,
            directories: directories,
            onNavigateTab: widget.onNavigateTab,
          ),
        ),

        // 2. SPOTIFY SIGNATURE 2x3 QUICK-ACCESS GRID
        SliverToBoxAdapter(
          child: _SpotifyQuickGrid(
            directories: directories,
            playlists: playlists,
            onNavigateTab: widget.onNavigateTab,
          ),
        ),

        // 2-bis. MUSIK OFFLINE CARD WITH PLAY CONTROLS
        if (_selectedChip == 'Semua' ||
            _selectedChip == 'Direktori' ||
            _selectedChip == 'Offline Ready')
          SliverToBoxAdapter(
            child: _OfflineMusicPlayerCard(
              directoriesCount: directories.length,
              onOpenDirectories: () => widget.onNavigateTab(1),
              onOpenYouTube: () => widget.onNavigateTab(3),
            ),
          ),

        // 2-ter. YOUTUBE OFFLINE DOWNLOADS CARD / SWIMLANE
        if (_selectedChip == 'Semua' ||
            _selectedChip == 'Direktori' ||
            _selectedChip == 'Offline Ready')
          SliverToBoxAdapter(
            child: _YouTubeOfflineSection(
              onOpenYouTube: () => widget.onNavigateTab(3),
            ),
          ),

        // 2a. CONTINUE WATCHING (HALLSEM CINEMA)
        if (jfProvider.continueWatchingMovies.isNotEmpty &&
            _selectedChip == 'Semua') ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'LANJUTKAN MENONTON',
              title: 'Lanjutkan Menonton Film',
              actionLabel: 'Buka Cinema',
              onAction: () => widget.onNavigateTab(4),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 158,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: jfProvider.continueWatchingMovies.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, idx) {
                  final movie = jfProvider.continueWatchingMovies[idx];
                  return JellyfinContinueWatchingCard(movie: movie);
                },
              ),
            ),
          ),
        ],

        // 2a-bis. M3U & CHANNEL FAVORIT ROW
        if (provider.favoriteTracks.any((t) => t.playlistId != null) &&
            (_selectedChip == 'Semua' || _selectedChip == 'TV')) ...[
          Builder(
            builder: (ctx) {
              final m3uFavs = provider.favoriteTracks
                  .where((t) => t.playlistId != null)
                  .toList();
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      badge: 'TV FAVORIT',
                      title: 'Favorit TV & Channel (${m3uFavs.length})',
                      actionLabel: 'Buka TV',
                      onAction: () => widget.onNavigateTab(2),
                    ),
                    SizedBox(
                      height: 112,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: m3uFavs.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, idx) {
                          final item = m3uFavs[idx];
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => M3uPlaybackLauncher.playItemList(
                              context,
                              m3uFavs,
                              initialIndex: idx,
                            ),
                            child: Container(
                              width: 175,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        item.isVideo
                                            ? Icons.live_tv_rounded
                                            : Icons.music_note_rounded,
                                        size: 18,
                                        color: item.isVideo
                                            ? AppColors.netflixRed
                                            : AppColors.spotifyGreen,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          item.groupTitle ?? item.directoryName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.neonCyan,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    item.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
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
            },
          ),
        ],

        // 2b. HALLSEM CINEMA MOVIES SWIMLANE
        if (jfProvider.movies.isNotEmpty && _selectedChip == 'Semua') ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'HALLSEM CINEMA',
              title: 'Film Hallsem Cinema (${jfProvider.movies.length})',
              actionLabel: 'Semua Film',
              onAction: () => widget.onNavigateTab(4),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 215,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: jfProvider.movies.length > 15
                    ? 15
                    : jfProvider.movies.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, idx) {
                  final movie = jfProvider.movies[idx];
                  return JellyfinPosterCard(
                    movie: movie,
                    fixedWidth: 122,
                  );
                },
              ),
            ),
          ),
        ],

        // 3. NETFLIX "CONTINUE LISTENING" HORIZONTAL ROW WITH PROGRESS BAR
        if (recents.isNotEmpty &&
            (_selectedChip == 'Semua' || _selectedChip == 'Offline Ready')) ...[
          const SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'NETFLIX ROW',
              title: 'Lanjutkan Mendengarkan',
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 168,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: recents.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (ctx, idx) {
                  final track = recents[idx];
                  final ratio = provider.savedProgressRatio(track);
                  return _ContinueListeningCard(
                    track: track,
                    progress: ratio > 0 ? ratio : 0.35,
                    onTap: () => M3uPlaybackLauncher.playItemList(
                      context,
                      recents,
                      initialIndex: idx,
                    ),
                  );
                },
              ),
            ),
          ),
        ],

        // 4. DIREKTORI MUSIK SWIMLANE (NETFLIX WIDE FOLDER CARDS)
        if (_selectedChip == 'Semua' ||
            _selectedChip == 'Direktori' ||
            _selectedChip == 'Offline Ready') ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'DIREKTORI',
              title: 'Musik Berdasarkan Direktori (${directories.length})',
              actionLabel: 'Lihat Semua',
              onAction: () => widget.onNavigateTab(1),
            ),
          ),
          if (directories.isEmpty)
            SliverToBoxAdapter(
              child: _EmptyCalloutCard(
                icon: Icons.folder_special_rounded,
                title: 'Belum Ada Direktori Musik Terdeteksi',
                subtitle:
                    'Izinkan akses penyimpanan atau pilih folder musik lokal agar lagu otomatis dikelompokkan per direktori.',
                primaryLabel: 'Pilih Folder Musik',
                onPrimary: provider.pickAndAddDirectory,
                secondaryLabel: 'Scan Penyimpanan',
                onSecondary: () => provider.refreshPermissionsAndScan(
                  requestInteractive: true,
                  requestAllFiles: true,
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: 190,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: directories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (ctx, idx) {
                    final group = directories[idx];
                    return _DirectoryPosterCard(
                      group: group,
                      onOpen: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => DirectoryDetailScreen(group: group),
                          ),
                        );
                      },
                      onPlay: () => provider.playTrackList(group.tracks),
                    );
                  },
                ),
              ),
            ),
        ],

        // 5. TV & IPTV PLAYLISTS SWIMLANE (FILE & LINK)
        if (_selectedChip == 'Semua' ||
            _selectedChip == 'TV' ||
            _selectedChip == 'Offline Ready') ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'PLAYLIST TV',
              title: 'TV File & Link (${playlists.length})',
              actionLabel: '+ Tambah TV',
              onAction: () => AddM3uBottomSheet.show(context),
            ),
          ),
          if (playlists.isEmpty)
            SliverToBoxAdapter(
              child: _EmptyCalloutCard(
                icon: Icons.live_tv_rounded,
                title: 'Tambahkan Banyak Playlist TV',
                subtitle:
                    'Dukung banyak file .m3u/.m3u8 offline maupun alamat link URL sekaligus.',
                primaryLabel: 'Impor File TV',
                onPrimary: provider.pickAndImportM3uFiles,
                secondaryLabel: 'Tambah Link TV',
                onSecondary: () =>
                    AddM3uBottomSheet.show(context, startWithUrlTab: true),
              ),
            )
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: 202,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (ctx, idx) {
                    final pl = playlists[idx];
                    return _M3uPosterCard(
                      playlist: pl,
                      onOpen: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PlaylistDetailScreen(playlistId: pl.id),
                          ),
                        );
                      },
                      onPlay: pl.tracks.isEmpty
                          ? null
                          : () => M3uPlaybackLauncher.playItemList(
                                context,
                                pl.tracks,
                              ),
                    );
                  },
                ),
              ),
            ),
        ],

        // 6. NETFLIX ICONIC "TOP 10" RANKED CAROUSEL
        if (topTracks.isNotEmpty && _selectedChip == 'Semua') ...[
          const SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'TOP 10',
              title: 'Top 10 Lagu Paling Sering Diputar',
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 175,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: topTracks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (ctx, idx) {
                  final t = topTracks[idx];
                  return _NetflixTop10Card(
                    rank: idx + 1,
                    track: t,
                    onTap: () => M3uPlaybackLauncher.playItemList(
                      context,
                      topTracks,
                      initialIndex: idx,
                    ),
                  );
                },
              ),
            ),
          ),
        ],

        // 7. SPOTIFY QUICK TRACKS LIST PREVIEW
        if (previewTracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'SPOTIFY MIX',
              title: 'Koleksi Musik (${previewTracks.length})',
              actionLabel: 'Acak Semua',
              onAction: () => M3uPlaybackLauncher.playItemList(
                context,
                previewTracks,
                shuffle: true,
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, idx) {
                final track = previewTracks[idx];
                return TrackTile(
                  track: track,
                  indexNumber: idx + 1,
                  onTap: () => M3uPlaybackLauncher.playItemList(
                    context,
                    previewTracks,
                    initialIndex: idx,
                  ),
                );
              },
              childCount: previewCount,
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.spotifyGreen : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.spotifyGreen
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _NetflixHeroBillboard extends StatelessWidget {
  final List<TrackItem> allTracks;
  final List<M3uPlaylist> playlists;
  final List<MusicDirectoryGroup> directories;
  final ValueChanged<int> onNavigateTab;

  const _NetflixHeroBillboard({
    required this.allTracks,
    required this.playlists,
    required this.directories,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final featuredTrack = provider.currentTrack ??
        (allTracks.isNotEmpty ? allTracks.first : null);

    final String heroTitle = featuredTrack?.title ?? 'MediaCenter & Direktori';
    final String heroSubtitle = featuredTrack != null
        ? '${featuredTrack.artist} • ${featuredTrack.directoryName}'
        : 'Pemutar Musik Offline, Pengelompokan Direktori & Multi-Playlist TV (File/Link)';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      height: 315,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: AppColors.spotifyHeroGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.spotifyGreen.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle oversized background artwork/logo watermark
          if (featuredTrack != null && featuredTrack.hasLocalArtwork)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Opacity(
                opacity: 0.24,
                child: Image.file(
                  File(featuredTrack.artworkUrl!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            )
          else if (featuredTrack != null && featuredTrack.hasValidNetworkArtwork)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Opacity(
                opacity: 0.24,
                child: Image.network(
                  featuredTrack.artworkUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            )
          else
            Positioned(
              right: -30,
              top: -20,
              child: Opacity(
                opacity: 0.16,
                child: const AppLogo(size: 230, borderRadius: 48),
              ),
            ),
          // Subtle warm gradient vignette at bottom for crisp text legibility
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.36),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.darkNav,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'FEATURED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${directories.length} Direktori • ${playlists.length} TV • ${allTracks.length} Lagu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (featuredTrack != null && featuredTrack.hasLocalArtwork)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.file(
                          File(featuredTrack.artworkUrl!),
                          width: 74,
                          height: 74,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const AppLogo(
                            size: 74,
                            borderRadius: 18,
                            showGlow: true,
                          ),
                        ),
                      )
                    else if (featuredTrack != null &&
                        featuredTrack.hasValidNetworkArtwork)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          featuredTrack.artworkUrl!,
                          width: 74,
                          height: 74,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const AppLogo(
                            size: 74,
                            borderRadius: 18,
                            showGlow: true,
                          ),
                        ),
                      )
                    else
                      const AppLogo(size: 74, borderRadius: 18, showGlow: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heroTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            heroSubtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.86),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Editorial Action Bar (Dark Pill Play Button + Translucent Pill)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.darkNav,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          if (allTracks.isNotEmpty) {
                            final idx = featuredTrack != null
                                ? allTracks.indexWhere(
                                    (t) => t.id == featuredTrack.id,
                                  )
                                : 0;
                            M3uPlaybackLauncher.playItemList(
                              context,
                              allTracks,
                              initialIndex: idx >= 0 ? idx : 0,
                            );
                          } else {
                            provider.pickAndAddDirectory();
                          }
                        },
                        icon: Icon(
                          allTracks.isNotEmpty
                              ? (featuredTrack?.isVideo == true
                                  ? Icons.ondemand_video_rounded
                                  : Icons.play_arrow_rounded)
                              : Icons.folder_open_rounded,
                          size: 24,
                        ),
                        label: Text(
                          allTracks.isNotEmpty
                              ? (featuredTrack?.isVideo == true
                                  ? 'Tonton Sekarang'
                                  : 'Putar Sekarang')
                              : 'Pilih Folder',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              AppColors.surfaceElevated.withValues(alpha: 0.94),
                          foregroundColor: AppColors.textPrimary,
                          side: BorderSide(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => AddM3uBottomSheet.show(context),
                        icon: const Icon(
                          Icons.live_tv_rounded,
                          color: AppColors.neonCyan,
                          size: 22,
                        ),
                        label: const Text(
                          '+ Playlist TV',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotifyQuickGrid extends StatelessWidget {
  final List<MusicDirectoryGroup> directories;
  final List<M3uPlaylist> playlists;
  final ValueChanged<int> onNavigateTab;

  const _SpotifyQuickGrid({
    required this.directories,
    required this.playlists,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final jf = context.watch<ProfileJellyfinProvider>();

    void openLibrary() {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const LibrarySearchScreen(),
        ),
      );
    }

    final m3uFavTracks = provider.favoriteTracks
        .where((t) => t.playlistId != null)
        .toList();

    final List<({String title, String subtitle, IconData icon, Color accent, VoidCallback onTap})>
        tiles = [
      (
        title: 'Lagu Disukai',
        subtitle: '${provider.favoriteTracks.length} favorit',
        icon: Icons.favorite_rounded,
        accent: AppColors.spotifyGreen,
        onTap: openLibrary,
      ),
      (
        title: 'TV Favorit',
        subtitle: '${m3uFavTracks.length} channel & lagu',
        icon: Icons.star_rounded,
        accent: AppColors.neonPurple,
        onTap: () {
          if (m3uFavTracks.isNotEmpty) {
            M3uPlaybackLauncher.playItemList(context, m3uFavTracks);
          } else {
            onNavigateTab(2);
          }
        },
      ),
      (
        title: 'Semua Direktori',
        subtitle: '${directories.length} folder musik',
        icon: Icons.folder_copy_rounded,
        accent: AppColors.neonCyan,
        onTap: () => onNavigateTab(1),
      ),
      (
        title: 'Playlist TV',
        subtitle: '${playlists.length} file & link',
        icon: Icons.live_tv_rounded,
        accent: AppColors.neonPurple,
        onTap: () => onNavigateTab(2),
      ),
      (
        title: 'NewTube',
        subtitle: 'YouTube Audio & Video',
        icon: Icons.smart_display_rounded,
        accent: AppColors.netflixRed,
        onTap: () => onNavigateTab(3),
      ),
      (
        title: 'Hallsem Cinema',
        subtitle: jf.movies.isNotEmpty
            ? '${jf.movies.length} film siap tonton'
            : 'Katalog Film & Video',
        icon: Icons.movie_filter_rounded,
        accent: AppColors.netflixRed,
        onTap: () => onNavigateTab(4),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tiles.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.95,
        ),
        itemBuilder: (_, idx) {
          final item = tiles[idx];
          return InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  item.accent.withValues(alpha: 0.11),
                  AppColors.surfaceElevated,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: item.accent.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: item.accent.withValues(alpha: 0.2),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(10),
                      ),
                    ),
                    child: Icon(item.icon, color: item.accent, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String badge;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.badge,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.netflixRed,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge,
                  style: const TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppColors.spotifyGreen,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContinueListeningCard extends StatelessWidget {
  final TrackItem track;
  final double progress;
  final VoidCallback onTap;

  const _ContinueListeningCard({
    required this.track,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 152,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(child: AppLogo(size: 72, borderRadius: 16)),
                  ),
                  Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.68),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.netflixRed,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.directoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
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
  }
}

class _DirectoryPosterCard extends StatelessWidget {
  final MusicDirectoryGroup group;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  const _DirectoryPosterCard({
    required this.group,
    required this.onOpen,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE9EFF5), Color(0xFFDDE5EE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.neonCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.folder_rounded,
                    color: AppColors.neonCyan,
                    size: 28,
                  ),
                ),
                GestureDetector(
                  onTap: onPlay,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.spotifyGreen,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              group.directoryName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${group.trackCount} lagu offline',
              style: const TextStyle(
                color: AppColors.spotifyGreen,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              group.directoryPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _M3uPosterCard extends StatelessWidget {
  final M3uPlaylist playlist;
  final VoidCallback onOpen;
  final VoidCallback? onPlay;

  const _M3uPosterCard({
    required this.playlist,
    required this.onOpen,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final isLink = playlist.isUrlSource;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLink
                ? const [Color(0xFFFBF0DA), Color(0xFFF3DFBA)]
                : const [Color(0xFFFBE7DC), Color(0xFFF4D5C4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (isLink ? AppColors.neonPurple : AppColors.spotifyGreen)
                .withValues(alpha: 0.24),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const AppLogo(size: 44, borderRadius: 11),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isLink
                        ? AppColors.neonPurple.withValues(alpha: 0.2)
                        : AppColors.spotifyGreen.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isLink ? 'LINK M3U' : 'FILE M3U',
                    style: TextStyle(
                      color: isLink
                          ? AppColors.neonPurple
                          : AppColors.spotifyGreen,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${playlist.tracks.length} lagu • ${playlist.offlineTrackCount} offline',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (onPlay != null)
                  GestureDetector(
                    onTap: onPlay,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.spotifyGreen,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 19,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NetflixTop10Card extends StatelessWidget {
  final int rank;
  final TrackItem track;
  final VoidCallback onTap;

  const _NetflixTop10Card({
    required this.rank,
    required this.track,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 158,
        child: Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Positioned(
              left: 0,
              bottom: -8,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 96,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 2.5
                    ..color = AppColors.textPrimary.withValues(alpha: 0.22),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 118,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: AppLogo(size: 68, borderRadius: 14)),
                    const Spacer(),
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
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

class _EmptyCalloutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const _EmptyCalloutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.neonCyan, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.spotifyGreen,
                  foregroundColor: Colors.black,
                ),
                onPressed: onPrimary,
                child: Text(
                  primaryLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfflineMusicPlayerCard extends StatelessWidget {
  final int directoriesCount;
  final VoidCallback onOpenDirectories;
  final VoidCallback onOpenYouTube;

  const _OfflineMusicPlayerCard({
    required this.directoriesCount,
    required this.onOpenDirectories,
    required this.onOpenYouTube,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final offlineTracks = provider.allOfflineMusicTracks;
    final activeTrack = provider.currentTrack;
    final bool isPlayingOffline =
        activeTrack != null && !activeTrack.isVideo && activeTrack.isOfflineReady;
    final bool isPlayingNow = isPlayingOffline && provider.isPlaying;

    final String titleText = isPlayingOffline
        ? activeTrack.title
        : (offlineTracks.isNotEmpty
            ? 'Musik Offline Siap Putar'
            : 'Belum Ada Musik Offline');
    final String subtitleText = isPlayingOffline
        ? '${activeTrack.artist} • ${activeTrack.directoryName}'
        : (offlineTracks.isNotEmpty
            ? '${offlineTracks.length} lagu offline di $directoriesCount direktori'
            : 'Unduh lagu/playlist YouTube atau scan direktori HP Anda');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.spotifyGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.offline_pin_rounded,
                      size: 13,
                      color: AppColors.spotifyGreen,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'MUSIK OFFLINE',
                      style: TextStyle(
                        color: AppColors.spotifyGreen,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onOpenDirectories,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Buka Direktori',
                    style: TextStyle(
                      color: AppColors.spotifyGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (provider.isDownloadingYouTube) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.spotifyGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.downloading_rounded,
                        size: 15,
                        color: AppColors.spotifyGreen,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Mengunduh: ${provider.ytDownloadLabel ?? 'Audio'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${(provider.ytDownloadProgress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.spotifyGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: provider.ytDownloadProgress > 0
                          ? provider.ytDownloadProgress
                          : null,
                      minHeight: 3.5,
                      backgroundColor: Colors.black.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.spotifyGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Builder(
                builder: (_) {
                  final artTrack = isPlayingOffline
                      ? activeTrack
                      : (offlineTracks.isNotEmpty ? offlineTracks.first : null);
                  if (artTrack != null && artTrack.hasLocalArtwork) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(artTrack.artworkUrl!),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _offlineDefaultThumb(),
                      ),
                    );
                  }
                  if (artTrack != null && artTrack.hasValidNetworkArtwork) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        artTrack.artworkUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _offlineDefaultThumb(),
                      ),
                    );
                  }
                  return _offlineDefaultThumb();
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: 'Lagu Sebelumnya',
                onPressed: isPlayingOffline ? provider.playPrevious : null,
                icon: const Icon(Icons.skip_previous_rounded, size: 26),
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  if (isPlayingOffline) {
                    provider.togglePlayPause();
                  } else if (offlineTracks.isNotEmpty) {
                    provider.playTrackList(offlineTracks);
                  } else {
                    onOpenYouTube();
                  }
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: AppColors.spotifyGreen,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlayingNow
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Lagu Berikutnya',
                onPressed: isPlayingOffline ? provider.playNext : null,
                icon: const Icon(Icons.skip_next_rounded, size: 26),
                color: AppColors.textPrimary,
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(
                    color: Colors.black.withValues(alpha: 0.14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: offlineTracks.isNotEmpty
                    ? () {
                        final shuffled = List<TrackItem>.from(offlineTracks)
                          ..shuffle();
                        provider.playTrackList(shuffled);
                      }
                    : onOpenYouTube,
                icon: Icon(
                  offlineTracks.isNotEmpty
                      ? Icons.shuffle_rounded
                      : Icons.download_rounded,
                  size: 16,
                  color: AppColors.spotifyGreen,
                ),
                label: Text(
                  offlineTracks.isNotEmpty ? 'Acak Offline' : 'Unduh YouTube',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _offlineDefaultThumb() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.spotifyGreen.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.library_music_rounded,
        color: AppColors.spotifyGreen,
        size: 26,
      ),
    );
  }
}

class _YouTubeOfflineSection extends StatelessWidget {
  final VoidCallback onOpenYouTube;

  const _YouTubeOfflineSection({required this.onOpenYouTube});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final ytFolders = provider.youTubeOfflineFolders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          badge: 'YOUTUBE OFFLINE',
          title: ytFolders.isNotEmpty
              ? 'Unduhan YouTube (${ytFolders.length} Folder)'
              : 'YouTube Offline',
          actionLabel: 'Buka YouTube',
          onAction: onOpenYouTube,
        ),
        if (ytFolders.isEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.netflixRed.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.smart_display_rounded,
                    color: AppColors.netflixRed,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Belum ada unduhan YouTube',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Unduh lagu single atau playlist YouTube agar muncul & bisa diputar offline di sini.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.spotifyGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: onOpenYouTube,
                  child: const Text(
                    'Unduh',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 158,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: ytFolders.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, idx) {
                final folder = ytFolders[idx];
                final firstTrack =
                    folder.tracks.isNotEmpty ? folder.tracks.first : null;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _showYouTubeOfflineFolderSheet(
                    context,
                    provider,
                    folder,
                  ),
                  child: Container(
                    width: 184,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE9EFF5), Color(0xFFDDE5EE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.neonCyan.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _buildFolderCover(firstTrack, size: 48),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () =>
                                  provider.playTrackList(folder.tracks),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: AppColors.spotifyGreen,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          folder.directoryName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${folder.trackCount} lagu • YouTube Offline',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.neonCyan,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
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
    );
  }

  Widget _buildFolderCover(TrackItem? track, {double size = 48}) {
    if (track != null && track.hasLocalArtwork) {
      return Image.file(
        File(track.artworkUrl!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackCover(size),
      );
    }
    if (track != null && track.hasValidNetworkArtwork) {
      return Image.network(
        track.artworkUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackCover(size),
      );
    }
    return _fallbackCover(size);
  }

  Widget _fallbackCover(double size) {
    return Container(
      width: size,
      height: size,
      color: AppColors.netflixRed.withValues(alpha: 0.14),
      child: const Icon(
        Icons.smart_display_rounded,
        color: AppColors.netflixRed,
        size: 24,
      ),
    );
  }

  void _showYouTubeOfflineFolderSheet(
    BuildContext context,
    MusicProvider provider,
    MusicDirectoryGroup folder,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              folder.directoryName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${folder.trackCount} lagu offline siap putar',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Hapus Folder Ini',
                        icon: const Icon(
                          Icons.delete_sweep_rounded,
                          color: AppColors.netflixRed,
                        ),
                        onPressed: () async {
                          await provider.deleteOfflineFolder(
                            folder.directoryPath,
                          );
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        },
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.spotifyGreen,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          provider.playTrackList(folder.tracks);
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(
                          'Putar Semua',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.surfaceHighlight),
                Expanded(
                  child: Consumer<MusicProvider>(
                    builder: (_, liveProv, _) {
                      final liveFolder = liveProv.youTubeOfflineFolders
                          .cast<MusicDirectoryGroup?>()
                          .firstWhere(
                            (g) => g?.directoryPath == folder.directoryPath,
                            orElse: () => null,
                          );
                      final list = liveFolder?.tracks ?? const [];
                      if (list.isEmpty) {
                        return const Center(
                          child: Text(
                            'Semua lagu di folder ini telah dihapus.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: scrollCtrl,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final t = list[i];
                          return Row(
                            children: [
                              Expanded(
                                child: TrackTile(
                                  track: t,
                                  indexNumber: i + 1,
                                  onTap: () {
                                    Navigator.pop(sheetCtx);
                                    liveProv.playTrackList(
                                      list,
                                      initialIndex: i,
                                    );
                                  },
                                ),
                              ),
                              IconButton(
                                tooltip: 'Hapus Lagu',
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.netflixRed,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    liveProv.deleteDownloadedTrack(t),
                              ),
                            ],
                          );
                        },
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
