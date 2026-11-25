import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../services/newtube_service.dart';
import '../theme/app_theme.dart';
import 'm3u_video_player_screen.dart';

class NewTubeScreen extends StatefulWidget {
  const NewTubeScreen({super.key});

  @override
  State<NewTubeScreen> createState() => _NewTubeScreenState();
}

class _NewTubeScreenState extends State<NewTubeScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  List<NewTubeItem> _results = const [];
  List<NewTubePlaylistItem> _playlists = const [];
  bool _isSearching = false;
  bool _defaultVideoMode = false;
  String _activeTab = 'Semua'; // Semua | Video | Playlist
  String? _loadingItemId;
  String? _error;

  static const List<String> _quickQueries = [
    'Musik Pop Indonesia Terbaru',
    'Metallica',
    'Lo-Fi Chill Beats',
    'Rock Classic Hits',
    'Acoustic Cover',
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _runSearch(_quickQueries.first);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        NewTubeService.searchVideos(q),
        NewTubeService.searchPlaylists(q),
      ]);
      if (!mounted) return;
      setState(() {
        _results = results[0] as List<NewTubeItem>;
        _playlists = results[1] as List<NewTubePlaylistItem>;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat pencarian YouTube: $e';
        _isSearching = false;
      });
    }
  }

  Future<void> _openPlaylist(NewTubePlaylistItem pl) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _YouTubePlaylistSheet(
        playlist: pl,
        defaultVideoMode: _defaultVideoMode,
      ),
    );
  }

  Future<void> _playItem(
    NewTubeItem item, {
    required bool asVideo,
    bool queueOnly = false,
    int? itemIndex,
  }) async {
    if (_loadingItemId != null) return;
    setState(() => _loadingItemId = item.videoId);

    try {
      if (!asVideo && !queueOnly) {
        final music = context.read<MusicProvider>();
        final idx = itemIndex ?? _results.indexOf(item);
        final ok = await music.playNewTubePlaylist(
          _results.isNotEmpty ? _results : [item],
          initialIndex: idx >= 0 ? idx : 0,
        );
        if (!mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Stream audio video ini tidak dapat diakses saat ini. Coba video lain.',
              ),
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Memutar audio background + antrean: ${item.title}'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      final resolved = asVideo
          ? await NewTubeService.resolveVideoStream(item.videoId)
          : await NewTubeService.resolveAudioStream(item.videoId);
      if (!mounted) return;
      if (resolved == null || resolved.url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stream video ini tidak dapat diakses saat ini. Coba video lain.',
            ),
          ),
        );
        return;
      }

      final track = item.toTrackItem(
        streamUrl: resolved.url,
        httpHeaders: resolved.headers,
        asVideo: asVideo,
      );
      if (queueOnly) {
        await context.read<MusicProvider>().addToQueue(track);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ditambahkan ke antrean: ${item.title}')),
          );
        }
        return;
      }

      await M3uPlaybackLauncher.playItemList(
        context,
        [track],
        forceVideoPlayer: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memutar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingItemId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final showPlaylists = _activeTab == 'Semua' || _activeTab == 'Playlist';
    final showVideos = _activeTab == 'Semua' || _activeTab == 'Video';

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(
              Icons.smart_display_rounded,
              color: AppColors.netflixRed,
              size: 24,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'NewTube',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<bool>(
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.headphones_rounded, size: 15),
                  label: Text('Audio', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.ondemand_video_rounded, size: 15),
                  label: Text('Video', style: TextStyle(fontSize: 11)),
                ),
              ],
              selected: {_defaultVideoMode},
              onSelectionChanged: (s) {
                setState(() => _defaultVideoMode = s.first);
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _runSearch,
              decoration: InputDecoration(
                hintText: 'Cari lagu, band, playlist, atau link YouTube...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.spotifyGreen,
                  ),
                  onPressed: () => _runSearch(_searchCtrl.text),
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _quickQueries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final q = _quickQueries[i];
                return ActionChip(
                  label: Text(q, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () {
                    _searchCtrl.text = q;
                    _runSearch(q);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final tab in [
                  ('Semua', 'Semua'),
                  ('Video', 'Lagu & Video (${_results.length})'),
                  ('Playlist', 'Playlist (${_playlists.length})'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        tab.$2,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      selected: _activeTab == tab.$1,
                      onSelected: (_) => setState(() => _activeTab = tab.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_isSearching)
            const LinearProgressIndicator(color: AppColors.netflixRed),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.netflixRed,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _runSearch(
                      _searchCtrl.text.trim().isEmpty
                          ? _quickQueries.first
                          : _searchCtrl.text,
                    ),
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _results.isEmpty && _playlists.isEmpty && !_isSearching
                ? const Center(
                    child: Text(
                      'Ketik judul lagu, artis, atau playlist YouTube.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                    children: [
                      if (showPlaylists && _playlists.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Playlist YouTube',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (_activeTab == 'Semua')
                          SizedBox(
                            height: 152,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _playlists.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, idx) => _PlaylistCompactCard(
                                playlist: _playlists[idx],
                                onTap: () => _openPlaylist(_playlists[idx]),
                              ),
                            ),
                          )
                        else
                          for (final pl in _playlists)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _PlaylistListTile(
                                playlist: pl,
                                onTap: () => _openPlaylist(pl),
                              ),
                            ),
                        const SizedBox(height: 14),
                      ],
                      if (showVideos && _results.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Lagu & Video',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        for (int i = 0; i < _results.length; i++) ...[
                          _buildVideoCard(_results[i], i),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCard(NewTubeItem item, int index) {
    final isLoadingThis = _loadingItemId == item.videoId;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _playItem(
        item,
        asVideo: _defaultVideoMode,
        itemIndex: index,
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Image.network(
                    item.thumbnailUrl,
                    width: 112,
                    height: 66,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 112,
                      height: 66,
                      color: AppColors.surfaceElevated,
                      child: const Icon(
                        Icons.smart_display_rounded,
                        color: AppColors.netflixRed,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.formattedDuration,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (isLoadingThis)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.spotifyGreen,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _NewTubeChipBtn(
                          icon: Icons.headphones_rounded,
                          label: 'Audio BG',
                          color: AppColors.spotifyGreen,
                          onTap: () => _playItem(
                            item,
                            asVideo: false,
                            itemIndex: index,
                          ),
                        ),
                        _NewTubeChipBtn(
                          icon: Icons.ondemand_video_rounded,
                          label: 'Video PiP',
                          color: AppColors.netflixRed,
                          onTap: () => _playItem(item, asVideo: true),
                        ),
                        _NewTubeChipBtn(
                          icon: Icons.playlist_add_rounded,
                          label: 'Antre',
                          color: AppColors.neonCyan,
                          onTap: () => _playItem(
                            item,
                            asVideo: false,
                            queueOnly: true,
                          ),
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
}

class _PlaylistCompactCard extends StatelessWidget {
  final NewTubePlaylistItem playlist;
  final VoidCallback onTap;

  const _PlaylistCompactCard({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Stack(
                children: [
                  if (playlist.thumbnailUrl.isNotEmpty)
                    Image.network(
                      playlist.thumbnailUrl,
                      width: 168,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _plFallback(),
                    )
                  else
                    _plFallback(),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.playlist_play_rounded,
                            size: 14,
                            color: AppColors.spotifyGreen,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            playlist.videoCountText,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlist.author,
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

  Widget _plFallback() {
    return Container(
      width: 168,
      height: 88,
      color: AppColors.surfaceElevated,
      child: const Icon(
        Icons.queue_music_rounded,
        color: AppColors.spotifyGreen,
        size: 32,
      ),
    );
  }
}

class _PlaylistListTile extends StatelessWidget {
  final NewTubePlaylistItem playlist;
  final VoidCallback onTap;

  const _PlaylistListTile({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: playlist.thumbnailUrl.isNotEmpty
                  ? Image.network(
                      playlist.thumbnailUrl,
                      width: 96,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 96,
                        height: 60,
                        color: AppColors.surfaceElevated,
                        child: const Icon(Icons.queue_music_rounded),
                      ),
                    )
                  : Container(
                      width: 96,
                      height: 60,
                      color: AppColors.surfaceElevated,
                      child: const Icon(Icons.queue_music_rounded),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${playlist.author} • ${playlist.videoCountText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _YouTubePlaylistSheet extends StatefulWidget {
  final NewTubePlaylistItem playlist;
  final bool defaultVideoMode;

  const _YouTubePlaylistSheet({
    required this.playlist,
    required this.defaultVideoMode,
  });

  @override
  State<_YouTubePlaylistSheet> createState() => _YouTubePlaylistSheetState();
}

class _YouTubePlaylistSheetState extends State<_YouTubePlaylistSheet> {
  List<NewTubeItem> _items = const [];
  bool _loading = true;
  bool _isStartingPlay = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list =
          await NewTubeService.fetchPlaylistVideos(widget.playlist.playlistId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat playlist: $e';
        _loading = false;
      });
    }
  }

  Future<void> _playFromPlaylist(int index, {required bool asVideo}) async {
    if (_isStartingPlay || index < 0 || index >= _items.length) return;
    setState(() => _isStartingPlay = true);
    try {
      final item = _items[index];
      if (!asVideo) {
        final ok = await context
            .read<MusicProvider>()
            .playNewTubePlaylist(_items, initialIndex: index);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Memutar playlist: ${widget.playlist.title}'
                  : 'Gagal memutar stream dari playlist ini.',
            ),
          ),
        );
      } else {
        final resolved = await NewTubeService.resolveVideoStream(item.videoId);
        if (!mounted) return;
        if (resolved == null) return;
        final track = item.toTrackItem(
          streamUrl: resolved.url,
          httpHeaders: resolved.headers,
          asVideo: true,
        );
        Navigator.pop(context);
        await M3uPlaybackLauncher.playItemList(
          context,
          [track],
          forceVideoPlayer: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingPlay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.94,
      minChildSize: 0.45,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
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
                          widget.playlist.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.playlist.author} • ${_items.length} lagu',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.spotifyGreen,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _items.isEmpty || _isStartingPlay
                        ? null
                        : () => _playFromPlaylist(0, asVideo: false),
                    icon: _isStartingPlay
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded),
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
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.spotifyGreen,
                      ),
                    )
                  : _error != null
                      ? Center(child: Text(_error!))
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  item.thumbnailUrl,
                                  width: 64,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 64,
                                    height: 44,
                                    color: AppColors.surfaceElevated,
                                    child: const Icon(Icons.music_note_rounded),
                                  ),
                                ),
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: Text(
                                '${item.author} • ${item.formattedDuration}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11.5,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.ondemand_video_rounded,
                                  color: AppColors.netflixRed,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    _playFromPlaylist(i, asVideo: true),
                              ),
                              onTap: () => _playFromPlaylist(
                                i,
                                asVideo: widget.defaultVideoMode,
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _NewTubeChipBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NewTubeChipBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
