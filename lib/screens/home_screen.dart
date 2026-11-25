import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../providers/profile_jellyfin_provider.dart';
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
      'Playlist M3U' => [
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
          backgroundColor: AppColors.background.withValues(alpha: 0.92),
          titleSpacing: 16,
          title: Row(
            children: [
              const AppLogo(size: 34, borderRadius: 9),
              const SizedBox(width: 10),
              const Text(
                'M3U Musik',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.netflixRed,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
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
              tooltip: 'Tambah Playlist M3U (File / Link)',
              icon: const Icon(Icons.playlist_add_circle_outlined),
              onPressed: () => AddM3uBottomSheet.show(context),
            ),
            IconButton(
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
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: UserAvatarWidget(
                size: 32,
                onTap: () => widget.onNavigateTab(4),
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
                    'Playlist M3U',
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

        // 2b. JELLYFIN CINEMA MOVIES SWIMLANE
        if (jfProvider.movies.isNotEmpty && _selectedChip == 'Semua') ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'JELLYFIN CINEMA',
              title: 'Film dari Server Jellyfin (${jfProvider.movies.length})',
              actionLabel: 'Semua Film',
              onAction: () => widget.onNavigateTab(3),
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

        // 5. MULTI-M3U PLAYLISTS SWIMLANE (FILE & LINK)
        if (_selectedChip == 'Semua' ||
            _selectedChip == 'Playlist M3U' ||
            _selectedChip == 'Offline Ready') ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              badge: 'MULTI M3U',
              title: 'Playlist M3U File & Link (${playlists.length})',
              actionLabel: '+ Tambah M3U',
              onAction: () => AddM3uBottomSheet.show(context),
            ),
          ),
          if (playlists.isEmpty)
            SliverToBoxAdapter(
              child: _EmptyCalloutCard(
                icon: Icons.queue_music_rounded,
                title: 'Tambahkan Banyak Playlist M3U',
                subtitle:
                    'Dukung banyak file .m3u/.m3u8 offline maupun alamat link URL sekaligus.',
                primaryLabel: 'Impor File M3U',
                onPrimary: provider.pickAndImportM3uFiles,
                secondaryLabel: 'Tambah Link M3U',
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

    final String heroTitle = featuredTrack?.title ?? 'M3U Musik & Direktori';
    final String heroSubtitle = featuredTrack != null
        ? '${featuredTrack.artist} • ${featuredTrack.directoryName}'
        : 'Pemutar Musik Offline, Pengelompokan Direktori & Multi-Playlist M3U (File/Link)';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      height: 315,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF172B47),
            Color(0xFF121829),
            Color(0xFF0B0E17),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle oversized background logo watermark
          Positioned(
            right: -30,
            top: -20,
            child: Opacity(
              opacity: 0.22,
              child: const AppLogo(size: 230, borderRadius: 48),
            ),
          ),
          // Cinema bottom gradient vignette
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.background.withValues(alpha: 0.65),
                  AppColors.background.withValues(alpha: 0.96),
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
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.netflixRed,
                        borderRadius: BorderRadius.circular(5),
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
                    Text(
                      '${directories.length} Direktori • ${playlists.length} M3U • ${allTracks.length} Lagu',
                      style: const TextStyle(
                        color: AppColors.neonCyan,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
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
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Netflix Action Bar (White Play Button + Secondary Dark Pill Buttons)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
                              AppColors.surfaceElevated.withValues(alpha: 0.85),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => AddM3uBottomSheet.show(context),
                        icon: const Icon(
                          Icons.playlist_add_rounded,
                          color: AppColors.neonCyan,
                          size: 22,
                        ),
                        label: const Text(
                          '+ Playlist M3U',
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
        title: 'Semua Direktori',
        subtitle: '${directories.length} folder musik',
        icon: Icons.folder_copy_rounded,
        accent: AppColors.neonCyan,
        onTap: () => onNavigateTab(1),
      ),
      (
        title: 'Playlist M3U',
        subtitle: '${playlists.length} file & link',
        icon: Icons.queue_music_rounded,
        accent: AppColors.neonPurple,
        onTap: () => onNavigateTab(2),
      ),
      (
        title: 'Film Jellyfin',
        subtitle: jf.isConnected
            ? '${jf.movies.length} film siap tonton'
            : 'Input API di Setting',
        icon: Icons.movie_filter_rounded,
        accent: AppColors.netflixRed,
        onTap: () => onNavigateTab(3),
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
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
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
            colors: [Color(0xFF1A2338), Color(0xFF111623)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                    color: AppColors.neonCyan.withValues(alpha: 0.14),
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
                      color: Colors.black,
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
                ? const [Color(0xFF23183C), Color(0xFF121524)]
                : const [Color(0xFF142C28), Color(0xFF111622)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                        ? AppColors.neonPurple.withValues(alpha: 0.25)
                        : AppColors.spotifyGreen.withValues(alpha: 0.22),
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
                    ..color = Colors.white.withValues(alpha: 0.45),
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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
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
