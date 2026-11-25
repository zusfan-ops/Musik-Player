import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';
import 'directories_screen.dart';
import 'm3u_video_player_screen.dart';
import 'playlists_screen.dart';

class LibrarySearchScreen extends StatefulWidget {
  const LibrarySearchScreen({super.key});

  @override
  State<LibrarySearchScreen> createState() => _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends State<LibrarySearchScreen> {
  String _query = '';
  int _tab = 0; // 0 = Semua Lagu, 1 = Favorit, 2 = Offline Cache

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final List<TrackItem> sourceTracks = _tab == 1
        ? provider.favoriteTracks
        : _tab == 2
            ? provider.offlineDownloadedTracks
            : provider.allTracks;

    final q = _query.trim().toLowerCase();
    final filteredTracks = q.isEmpty
        ? sourceTracks
        : sourceTracks.where((t) {
            return t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q) ||
                t.directoryName.toLowerCase().contains(q);
          }).toList();

    final matchingDirs = q.isEmpty
        ? const <MusicDirectoryGroup>[]
        : provider.combinedDirectoryGroups
            .where((d) => d.directoryName.toLowerCase().contains(q))
            .toList();

    final matchingPlaylists = q.isEmpty
        ? const <M3uPlaylist>[]
        : provider.playlists
            .where((p) => p.name.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 30, borderRadius: 8),
            SizedBox(width: 10),
            Text('Cari & Koleksi'),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Cari judul lagu, artis, direktori, atau M3U...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      hintStyle: const TextStyle(color: Colors.black54),
                      prefixIconColor: Colors.black87,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _TabChip(
                          label: 'Semua (${provider.allTracks.length})',
                          active: _tab == 0,
                          onTap: () => setState(() => _tab = 0),
                        ),
                        const SizedBox(width: 8),
                        _TabChip(
                          label: 'Disukai (${provider.favoriteTracks.length})',
                          active: _tab == 1,
                          onTap: () => setState(() => _tab = 1),
                        ),
                        const SizedBox(width: 8),
                        _TabChip(
                          label:
                              'Unduhan M3U (${provider.offlineDownloadedTracks.length})',
                          active: _tab == 2,
                          onTap: () => setState(() => _tab = 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (matchingDirs.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Text(
                  'Direktori Cocok',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, idx) {
                  final d = matchingDirs[idx];
                  return ListTile(
                    leading: const Icon(
                      Icons.folder_rounded,
                      color: AppColors.neonCyan,
                    ),
                    title: Text(d.directoryName),
                    subtitle: Text('${d.trackCount} lagu • ${d.directoryPath}'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => DirectoryDetailScreen(group: d),
                      ),
                    ),
                  );
                },
                childCount: matchingDirs.length,
              ),
            ),
          ],

          if (matchingPlaylists.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Text(
                  'Playlist M3U Cocok',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, idx) {
                  final pl = matchingPlaylists[idx];
                  return ListTile(
                    leading: const AppLogo(size: 38, borderRadius: 8),
                    title: Text(pl.name),
                    subtitle: Text('${pl.tracks.length} lagu'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PlaylistDetailScreen(playlistId: pl.id),
                      ),
                    ),
                  );
                },
                childCount: matchingPlaylists.length,
              ),
            ),
          ],

          if (filteredTracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'Belum ada lagu yang cocok pada kategori ini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, idx) {
                  final track = filteredTracks[idx];
                  return TrackTile(
                    track: track,
                    indexNumber: idx + 1,
                    onTap: () => M3uPlaybackLauncher.playItemList(
                      context,
                      filteredTracks,
                      initialIndex: idx,
                    ),
                  );
                },
                childCount: filteredTracks.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.spotifyGreen : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
