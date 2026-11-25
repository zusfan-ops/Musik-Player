import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../services/newtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player_bar.dart';
import 'm3u_video_player_screen.dart';

class NewTubeScreen extends StatefulWidget {
  const NewTubeScreen({super.key});

  @override
  State<NewTubeScreen> createState() => _NewTubeScreenState();
}

class _NewTubeScreenState extends State<NewTubeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<NewTubeItem> _results = const [];
  bool _isSearching = false;
  String? _loadingItemId;
  String? _error;

  static const List<String> _quickQueries = [
    'Musik Pop Indonesia Terbaru',
    'Lo-Fi Chill Beats',
    'Rock Classic Hits',
    'Acoustic Cover',
    'Podcast Teknologi Indonesia',
  ];

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
      final items = await NewTubeService.searchVideos(q);
      if (!mounted) return;
      setState(() {
        _results = items;
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

  Future<void> _playItem(NewTubeItem item, {required bool asVideo}) async {
    if (_loadingItemId != null) return;
    setState(() => _loadingItemId = item.videoId);

    try {
      final url = asVideo
          ? await NewTubeService.resolveVideoStreamUrl(item.videoId)
          : await NewTubeService.resolveAudioStreamUrl(item.videoId);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stream tidak tersedia untuk video ini.'),
          ),
        );
        return;
      }

      final track = item.toTrackItem(streamUrl: url, asVideo: asVideo);
      if (asVideo) {
        await M3uPlaybackLauncher.playItemList(
          context,
          [track],
          forceVideoPlayer: true,
        );
      } else {
        await context.read<MusicProvider>().playSingleTrack(track);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Memutar audio background: ${item.title}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
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
    return Scaffold(
      bottomNavigationBar: const SafeArea(child: MiniPlayerBar()),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(
              Icons.smart_display_rounded,
              color: AppColors.netflixRed,
              size: 26,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'NewTube • Background Play',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _runSearch,
              decoration: InputDecoration(
                hintText: 'Cari lagu, artis, atau video YouTube...',
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
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _quickQueries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final q = _quickQueries[i];
                return ActionChip(
                  label: Text(q, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _searchCtrl.text = q;
                    _runSearch(q);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_isSearching)
            const LinearProgressIndicator(color: AppColors.netflixRed),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.netflixRed,
                  fontSize: 12.5,
                ),
              ),
            ),
          Expanded(
            child: _results.isEmpty && !_isSearching
                ? const Center(
                    child: Text(
                      'Ketik judul lagu atau video untuk mulai mencari.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final item = _results[i];
                      final isLoadingThis = _loadingItemId == item.videoId;
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
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
                                        color: Colors.black.withValues(alpha: 0.8),
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
                                    Row(
                                      children: [
                                        InkWell(
                                          onTap: () =>
                                              _playItem(item, asVideo: false),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.spotifyGreen
                                                  .withValues(alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.headphones_rounded,
                                                  size: 14,
                                                  color: AppColors.spotifyGreen,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Audio',
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.spotifyGreen,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () =>
                                              _playItem(item, asVideo: true),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.netflixRed
                                                  .withValues(alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.ondemand_video_rounded,
                                                  size: 14,
                                                  color: AppColors.netflixRed,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Video',
                                                  style: TextStyle(
                                                    color: AppColors.netflixRed,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
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
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
