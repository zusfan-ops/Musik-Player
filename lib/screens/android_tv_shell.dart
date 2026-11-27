import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/jellyfin_profile_models.dart';
import '../providers/music_provider.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar_widget.dart';
import 'android_tv_tabs.dart';
import 'jellyfin_movie_player_screen.dart';
import 'jellyfin_movies_screen.dart';
import 'm3u_video_player_screen.dart';

/// Shared D-pad focusable card for Apple TV-style 10-foot UI.
class TvFocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final bool autofocus;
  final double focusScale;
  final Color? focusBorderColor;

  const TvFocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.autofocus = false,
    this.focusScale = 1.05,
    this.focusBorderColor,
  });

  @override
  State<TvFocusCard> createState() => _TvFocusCardState();
}

class _TvFocusCardState extends State<TvFocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.focusBorderColor ?? Colors.white;
    return AnimatedScale(
      scale: _focused ? widget.focusScale : 1.0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: widget.borderRadius,
          onFocusChange: (f) => setState(() => _focused = f),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _focused
                    ? borderColor
                    : Colors.white.withValues(alpha: 0.10),
                width: _focused ? 2.6 : 1.0,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: borderColor.withValues(alpha: 0.28),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple TV-inspired 10-foot Android TV shell (no POS or Keuangan).
class AndroidTvShell extends StatefulWidget {
  final bool autoCheckUpdates;

  const AndroidTvShell({super.key, this.autoCheckUpdates = true});

  @override
  State<AndroidTvShell> createState() => _AndroidTvShellState();
}

class _AndroidTvShellState extends State<AndroidTvShell> {
  int _selectedTab = 0; // 0: Beranda, 1: Film, 2: TV, 3: YouTube, 4: Musik, 5: Setting
  String? _selectedTvPlaylistId;

  static const List<({IconData icon, String label})> _navItems = [
    (icon: Icons.home_rounded, label: 'Beranda'),
    (icon: Icons.movie_rounded, label: 'Film'),
    (icon: Icons.live_tv_rounded, label: 'TV & CCTV'),
    (icon: Icons.smart_display_rounded, label: 'YouTube'),
    (icon: Icons.music_note_rounded, label: 'Musik'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<MusicProvider>().importBundledCctvAssets());
      if (widget.autoCheckUpdates) {
        unawaited(_checkUpdates());
      }
    });
  }

  Future<void> _checkUpdates() async {
    await UpdateCheckerService.instance.checkAndShowUpdateDialog(context);
  }

  void _openTvTab({String? playlistId}) {
    setState(() {
      _selectedTvPlaylistId = playlistId;
      _selectedTab = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedTab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedTab != 0) {
          setState(() => _selectedTab = 0);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090B10),
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.0, -0.85),
              radius: 1.35,
              colors: [
                Color(0xFF1A2033),
                Color(0xFF090B10),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildAppleTvTopBar(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      _TvHomeTab(
                        onOpenTab: (t) => setState(() => _selectedTab = t),
                        onOpenTvPlaylist: (id) => _openTvTab(playlistId: id),
                      ),
                      const TvMoviesTab(),
                      TvLiveChannelsTab(
                        selectedPlaylistId: _selectedTvPlaylistId,
                        onSelectPlaylist: (id) =>
                            setState(() => _selectedTvPlaylistId = id),
                      ),
                      const TvYouTubeTab(),
                      const TvMusicTab(),
                      const TvSettingsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppleTvTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 10),
      child: Row(
        children: [
          const AppLogo(size: 38, borderRadius: 10),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MediaCenter',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                'ANDROID TV',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < _navItems.length; i++)
                      _TopNavPill(
                        icon: _navItems[i].icon,
                        label: _navItems[i].label,
                        selected: _selectedTab == i,
                        autofocus: i == 0 && _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = i),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          TvFocusCard(
            borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => _selectedTab = 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _selectedTab == 5
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const UserAvatarWidget(size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'Setting',
                    style: TextStyle(
                      color: _selectedTab == 5 ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopNavPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const _TopNavPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_TopNavPill> createState() => _TopNavPillState();
}

class _TopNavPillState extends State<_TopNavPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(22),
          onFocusChange: (f) => setState(() => _focused = f),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: widget.selected
                  ? Colors.white
                  : (_focused
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(22),
              border: _focused && !widget.selected
                  ? Border.all(color: Colors.white, width: 1.5)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.selected ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.selected ? Colors.black : Colors.white,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvHomeTab extends StatelessWidget {
  final ValueChanged<int> onOpenTab;
  final ValueChanged<String> onOpenTvPlaylist;

  const _TvHomeTab({
    required this.onOpenTab,
    required this.onOpenTvPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();
    final music = context.watch<MusicProvider>();
    final featured = jf.movies.isNotEmpty ? jf.movies.first : null;
    final continueList = jf.continueWatchingMovies;
    final tvPlaylists = music.playlists;

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 10, 32, 36),
      children: [
        _buildHeroBillboard(context, jf, featured, music),
        if (continueList.isNotEmpty) ...[
          const _TvSectionTitle('Lanjutkan Menonton'),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: continueList.length.clamp(0, 15),
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (ctx, i) {
                final m = continueList[i];
                return _TvMovieWideCard(
                  movie: m,
                  jf: jf,
                  progress: jf.movieProgressRatio(m),
                );
              },
            ),
          ),
        ],
        if (tvPlaylists.isNotEmpty) ...[
          const _TvSectionTitle('TV & CCTV Per Kota'),
          SizedBox(
            height: 126,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tvPlaylists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final pl = tvPlaylists[i];
                return SizedBox(
                  width: 230,
                  child: TvFocusCard(
                    onTap: () => onOpenTvPlaylist(pl.id),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1E2538),
                            const Color(0xFF141824),
                          ],
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
                              Icon(
                                pl.name.toLowerCase().contains('cctv')
                                    ? Icons.location_city_rounded
                                    : Icons.live_tv_rounded,
                                color: AppColors.netflixRed,
                                size: 24,
                              ),
                              const Spacer(),
                              Text(
                                '${pl.tracks.length} ch',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            pl.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (jf.movies.isNotEmpty) ...[
          const _TvSectionTitle('Hallsem Cinema • Film Terbaru'),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: jf.movies.length.clamp(0, 20),
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (_, i) {
                final m = jf.movies[i];
                return TvMoviePosterCard(movie: m, jf: jf);
              },
            ),
          ),
        ],
        if (music.allTracks.isNotEmpty) ...[
          const _TvSectionTitle('Musik Pilihan'),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: music.allTracks.length.clamp(0, 20),
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (ctx, i) {
                final t = music.allTracks[i];
                return SizedBox(
                  width: 240,
                  child: TvFocusCard(
                    onTap: () {
                      unawaited(
                        music.playTrackList(
                          music.allTracks,
                          initialIndex: i,
                        ),
                      );
                      onOpenTab(4);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      color: const Color(0xFF161A26),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.spotifyGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: AppColors.spotifyGreen,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeroBillboard(
    BuildContext context,
    ProfileJellyfinProvider jf,
    JellyfinMovieItem? featured,
    MusicProvider music,
  ) {
    final title = featured?.name ?? 'MediaCenter TV';
    final subtitle = featured != null
        ? featured.displaySubtitle
        : '${music.playlists.length} Playlist TV & CCTV • ${music.allTracks.length} Lagu';
    final overview = featured?.overview ??
        'Nikmati Film Hallsem Cinema, Live TV & CCTV Per Kota, YouTube, dan Musik dalam tampilan layar lebar.';

    return Container(
      height: 310,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF141824),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (featured != null)
            Image.network(
              jf.backdropUrlFor(featured),
              headers: jf.authHeaders,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF090B10).withValues(alpha: 0.96),
                  const Color(0xFF090B10).withValues(alpha: 0.72),
                  Colors.transparent,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.netflixRed,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    featured != null ? 'HALLSEM CINEMA' : 'LIVE TV & MEDIA',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 560,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      height: 1.12,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 520,
                  child: Text(
                    overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    TvFocusCard(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if (featured != null) {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  JellyfinMoviePlayerScreen(movie: featured),
                            ),
                          );
                        } else if (music.playlists.isNotEmpty &&
                            music.playlists.first.tracks.isNotEmpty) {
                          M3uPlaybackLauncher.playItemList(
                            context,
                            music.playlists.first.tracks,
                            forceVideoPlayer: true,
                          );
                        } else {
                          onOpenTab(2);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        color: Colors.white,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: Colors.black),
                            SizedBox(width: 8),
                            Text(
                              'Putar Sekarang',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (featured != null) ...[
                      const SizedBox(width: 14),
                      TvFocusCard(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => JellyfinMovieDetailSheet.show(
                          context,
                          featured,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          color: Colors.white.withValues(alpha: 0.14),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Detail Film',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _TvSectionTitle extends StatelessWidget {
  final String title;
  const _TvSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _TvMovieWideCard extends StatelessWidget {
  final JellyfinMovieItem movie;
  final ProfileJellyfinProvider jf;
  final double progress;

  const _TvMovieWideCard({
    required this.movie,
    required this.jf,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: TvFocusCard(
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => JellyfinMoviePlayerScreen(movie: movie),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              jf.backdropUrlFor(movie),
              headers: jf.authHeaders,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: const Color(0xFF181D2B)),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.88)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.netflixRed,
                      ),
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

class TvMoviePosterCard extends StatelessWidget {
  final JellyfinMovieItem movie;
  final ProfileJellyfinProvider jf;

  const TvMoviePosterCard({super.key, required this.movie, required this.jf});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      child: TvFocusCard(
        onTap: () => JellyfinMovieDetailSheet.show(context, movie),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              jf.posterUrlFor(movie),
              headers: jf.authHeaders,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFF181D2B),
                child: const Icon(Icons.movie_rounded, color: Colors.white38, size: 40),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Text(
                  movie.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
