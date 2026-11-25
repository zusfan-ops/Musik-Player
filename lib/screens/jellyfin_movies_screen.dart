import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/jellyfin_profile_models.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar_widget.dart';
import 'jellyfin_movie_player_screen.dart';

class JellyfinMoviesScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;

  const JellyfinMoviesScreen({
    super.key,
    required this.onOpenSettings,
  });

  @override
  State<JellyfinMoviesScreen> createState() => _JellyfinMoviesScreenState();
}

class _JellyfinMoviesScreenState extends State<JellyfinMoviesScreen> {
  String _searchQuery = '';
  String _selectedType = 'Semua'; // Semua | Movie | Episode | Video

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();

    if (!jf.hasCredentials) {
      return Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              AppLogo(size: 30, borderRadius: 8),
              SizedBox(width: 10),
              Text('Hallsem Cinema'),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: UserAvatarWidget(
                size: 32,
                onTap: widget.onOpenSettings,
              ),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF281118), Color(0xFF121622)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 80, borderRadius: 20, showGlow: true),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.netflixRed,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'HALLSEM CINEMA',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tonton Koleksi Film di Hallsem Cinema',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Koleksi film Hallsem Cinema terhubung otomatis. Tekan tombol di bawah jika katalog belum termuat.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.netflixRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => jf.connectAndSyncBuiltInJellyfin(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(
                        'Muat Ulang Katalog Film',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final q = _searchQuery.trim().toLowerCase();
    final filteredMovies = jf.movies.where((m) {
      if (_selectedType != 'Semua' && m.itemType != _selectedType) {
        return false;
      }
      if (q.isEmpty) return true;
      return m.name.toLowerCase().contains(q) ||
          (m.overview?.toLowerCase().contains(q) ?? false) ||
          m.genres.any((g) => g.toLowerCase().contains(q));
    }).toList();

    final featured = filteredMovies.isNotEmpty
        ? filteredMovies.first
        : (jf.movies.isNotEmpty ? jf.movies.first : null);
    final continueWatching = jf.continueWatchingMovies;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(size: 30, borderRadius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hallsem Cinema',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  if (jf.serverName.isNotEmpty)
                    Text(
                      jf.serverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.spotifyGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang Film',
            icon: jf.isLoadingMovies
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.netflixRed,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: jf.isLoadingMovies ? null : () => jf.refreshMovies(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 4),
            child: UserAvatarWidget(
              size: 32,
              onTap: widget.onOpenSettings,
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (jf.errorMessage != null)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.netflixRed.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.netflixRed.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.netflixRed,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        jf.errorMessage!,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () => jf.connectAndSyncBuiltInJellyfin(),
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            ),

          // Netflix Cinema Featured Movie Billboard
          if (featured != null && _searchQuery.isEmpty)
            SliverToBoxAdapter(
              child: _MovieHeroBanner(movie: featured),
            ),

          // Continue Watching Row
          if (continueWatching.isNotEmpty && _searchQuery.isEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Text(
                  'Lanjutkan Menonton Film',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 146,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: continueWatching.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (ctx, idx) {
                    final m = continueWatching[idx];
                    return JellyfinContinueWatchingCard(
                      movie: m,
                      progress: jf.movieProgressRatio(m),
                    );
                  },
                ),
              ),
            ),
          ],

          // Search & Filter Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Cari judul film, genre, atau sinopsis...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in const [
                          (val: 'Semua', label: 'Semua'),
                          (val: 'Movie', label: 'Film Layar Lebar'),
                          (val: 'Episode', label: 'Episode Serial'),
                          (val: 'Video', label: 'Video Lainnya'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(item.label),
                              selected: _selectedType == item.val,
                              onSelected: (_) =>
                                  setState(() => _selectedType = item.val),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (jf.isLoadingMovies && jf.movies.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.netflixRed),
              ),
            )
          else if (filteredMovies.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    jf.movies.isEmpty
                        ? 'Belum ada koleksi film di Hallsem Cinema.'
                        : 'Tidak ada film yang cocok dengan filter pencarian.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, idx) {
                    final movie = filteredMovies[idx];
                    return JellyfinPosterCard(movie: movie);
                  },
                  childCount: filteredMovies.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MovieHeroBanner extends StatelessWidget {
  final JellyfinMovieItem movie;

  const _MovieHeroBanner({required this.movie});

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      height: 285,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (movie.hasBackdropImage || movie.hasPrimaryImage)
              Image.network(
                jf.backdropUrlFor(movie),
                headers: jf.authHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _heroFallback(),
              )
            else
              _heroFallback(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.black.withValues(alpha: 0.65),
                    AppColors.background.withValues(alpha: 0.96),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
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
                          'HALLSEM CINEMA',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (movie.communityRating != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFBBF24),
                              size: 16,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              movie.communityRating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    movie.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      movie.displaySubtitle,
                      if (movie.genres.isNotEmpty)
                        movie.genres.take(2).join(', '),
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    JellyfinMoviePlayerScreen(movie: movie),
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_arrow_rounded, size: 24),
                          label: const Text(
                            'Putar Film',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              AppColors.surfaceElevated.withValues(alpha: 0.8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () =>
                            JellyfinMovieDetailSheet.show(context, movie),
                        icon: const Icon(Icons.info_outline_rounded, size: 20),
                        label: const Text('Detail'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.spotifyHeroGradient,
      ),
      alignment: Alignment.center,
      child: const AppLogo(size: 90, borderRadius: 22),
    );
  }
}

class JellyfinContinueWatchingCard extends StatelessWidget {
  final JellyfinMovieItem movie;
  final double? progress;

  const JellyfinContinueWatchingCard({
    super.key,
    required this.movie,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();
    final effectiveProgress = progress ?? jf.movieProgressRatio(movie);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => JellyfinMoviePlayerScreen(movie: movie),
          ),
        );
      },
      child: Container(
        width: 210,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (movie.hasBackdropImage || movie.hasPrimaryImage)
                      Image.network(
                        jf.backdropUrlFor(movie),
                        headers: jf.authHeaders,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _cwFallback(),
                      )
                    else
                      _cwFallback(),
                    Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.68),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: effectiveProgress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.netflixRed,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                child: Text(
                  movie.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cwFallback() {
    return Container(
      color: AppColors.surfaceElevated,
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_creation_outlined,
        size: 32,
        color: AppColors.textMuted,
      ),
    );
  }
}

class JellyfinPosterCard extends StatelessWidget {
  final JellyfinMovieItem movie;
  final double? fixedWidth;

  const JellyfinPosterCard({
    super.key,
    required this.movie,
    this.fixedWidth,
  });

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();

    return GestureDetector(
      onTap: () => JellyfinMovieDetailSheet.show(context, movie),
      child: SizedBox(
        width: fixedWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (movie.hasPrimaryImage)
                        Image.network(
                          jf.posterUrlFor(movie),
                          headers: jf.authHeaders,
                          cacheWidth:
                              (140 * MediaQuery.devicePixelRatioOf(context))
                                  .round()
                                  .clamp(120, 600),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _posterFallback(),
                        )
                      else
                        _posterFallback(),
                      if (movie.communityRating != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFFBBF24),
                                  size: 12,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  movie.communityRating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            Text(
              movie.productionYear != null
                  ? '${movie.productionYear} • ${movie.formattedDuration}'
                  : movie.formattedDuration,
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
    );
  }

  Widget _posterFallback() {
    return Container(
      color: AppColors.surfaceElevated,
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_movies_rounded,
        color: AppColors.netflixRed,
        size: 36,
      ),
    );
  }
}

class JellyfinMovieDetailSheet extends StatelessWidget {
  final JellyfinMovieItem movie;

  const JellyfinMovieDetailSheet({super.key, required this.movie});

  static void show(BuildContext context, JellyfinMovieItem movie) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => JellyfinMovieDetailSheet(movie: movie),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SizedBox(
              height: 210,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (movie.hasBackdropImage || movie.hasPrimaryImage)
                    Image.network(
                      jf.backdropUrlFor(movie),
                      headers: jf.authHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.surfaceElevated,
                        alignment: Alignment.center,
                        child: const AppLogo(size: 72),
                      ),
                    )
                  else
                    Container(
                      color: AppColors.surfaceElevated,
                      alignment: Alignment.center,
                      child: const AppLogo(size: 72),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.surface.withValues(alpha: 0.95),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movie.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (movie.productionYear != null)
                      Text(
                        '${movie.productionYear}',
                        style: const TextStyle(
                          color: AppColors.spotifyGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (movie.officialRating != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white38),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          movie.officialRating!,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    Text(
                      movie.formattedDuration,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    if (movie.communityRating != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFBBF24),
                            size: 16,
                          ),
                          const SizedBox(width: 3),
                          Text(movie.communityRating!.toStringAsFixed(1)),
                        ],
                      ),
                  ],
                ),
                if (movie.genres.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in movie.genres)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            g,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.neonCyan,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.netflixRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => JellyfinMoviePlayerScreen(
                                movie: movie,
                                initialUseHls: false,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(
                          'Putar Film',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => JellyfinMoviePlayerScreen(
                              movie: movie,
                              initialUseHls: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.hd_outlined,
                        color: AppColors.neonCyan,
                      ),
                      label: const Text('Mode HLS'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Consumer<ProfileJellyfinProvider>(
                  builder: (ctx, jfWatch, _) {
                    final isOffline = jfWatch.isMovieOfflineReady(movie.id);
                    final isDownloading = jfWatch.isMovieDownloading(movie.id);
                    final dlProgress = jfWatch.movieDownloadProgress(movie.id);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isDownloading) ...[
                          LinearProgressIndicator(
                            value: dlProgress > 0 ? dlProgress : null,
                            color: AppColors.spotifyGreen,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Mengunduh film offline (${(dlProgress * 100).round()}%)...',
                            style: const TextStyle(
                              color: AppColors.spotifyGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else if (isOffline)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.spotifyGreen,
                              side: BorderSide(
                                color: AppColors.spotifyGreen
                                    .withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () async {
                              await jfWatch.removeOfflineMovie(movie.id);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Film offline dihapus dari penyimpanan.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.offline_pin_rounded),
                            label: const Text('Tersimpan Offline (Ketuk Hapus)'),
                          )
                        else
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.neonCyan,
                              side: BorderSide(
                                color: AppColors.neonCyan
                                    .withValues(alpha: 0.45),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              jfWatch.downloadMovieOffline(movie);
                            },
                            icon: const Icon(Icons.download_for_offline_rounded),
                            label: const Text('Unduh Film untuk Nonton Offline'),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  (movie.overview != null && movie.overview!.trim().isNotEmpty)
                      ? movie.overview!
                      : 'Tidak ada sinopsis untuk film ini.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
