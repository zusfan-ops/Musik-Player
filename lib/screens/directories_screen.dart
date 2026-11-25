import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';

class DirectoriesScreen extends StatefulWidget {
  const DirectoriesScreen({super.key});

  @override
  State<DirectoriesScreen> createState() => _DirectoriesScreenState();
}

class _DirectoriesScreenState extends State<DirectoriesScreen> {
  String _searchQuery = '';
  bool _gridMode = true;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final allGroups = provider.combinedDirectoryGroups;
    final filtered = _searchQuery.trim().isEmpty
        ? allGroups
        : allGroups.where((g) {
            final q = _searchQuery.toLowerCase();
            return g.directoryName.toLowerCase().contains(q) ||
                g.directoryPath.toLowerCase().contains(q) ||
                g.tracks.any((t) => t.title.toLowerCase().contains(q));
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 30, borderRadius: 8),
            SizedBox(width: 10),
            Text('Direktori Musik'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _gridMode ? 'Tampilan Daftar' : 'Tampilan Grid Poster',
            icon: Icon(
              _gridMode ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
            onPressed: () => setState(() => _gridMode = !_gridMode),
          ),
          IconButton(
            tooltip: 'Scan Ulang Direktori',
            icon: provider.isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.spotifyGreen,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: provider.isScanning
                ? null
                : () => provider.refreshPermissionsAndScan(
                      requestInteractive: true,
                      requestAllFiles: true,
                    ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Action Bar + Search Input
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.spotifyGreen,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: provider.pickAndAddDirectory,
                          icon: const Icon(Icons.create_new_folder_rounded),
                          label: const Text(
                            'Tambah Direktori',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => provider.refreshPermissionsAndScan(
                          requestInteractive: true,
                          requestAllFiles: true,
                        ),
                        icon: const Icon(
                          Icons.sd_storage_rounded,
                          color: AppColors.neonCyan,
                        ),
                        label: const Text('Izin & Scan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Cari nama folder, path direktori, atau lagu...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!provider.hasStoragePermission)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.netflixRed.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.netflixRed.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_open_rounded,
                      color: AppColors.netflixRed,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Izinkan akses Musik & Audio agar seluruh folder musik di perangkat Anda terdeteksi otomatis.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => provider.refreshPermissionsAndScan(
                        requestInteractive: true,
                        requestAllFiles: false,
                      ),
                      child: const Text('Izinkan'),
                    ),
                  ],
                ),
              ),
            ),

          // Auto-discovered M3U files inside scanned folders!
          if (provider.discoveredM3uFiles.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.neonCyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.neonCyan.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.neonCyan,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ditemukan ${provider.discoveredM3uFiles.length} File M3U di Direktori!',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.neonCyan,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            int count = 0;
                            for (final f in provider.discoveredM3uFiles) {
                              try {
                                await provider.addM3uFromFilePath(f);
                                count++;
                              } catch (_) {}
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$count file M3U dari direktori berhasil diimpor!',
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text('Impor Semua'),
                        ),
                      ],
                    ),
                    Text(
                      provider.discoveredM3uFiles
                          .take(3)
                          .map(p.basename)
                          .join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Custom Added Directories Chips
          if (provider.customDirectories.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: provider.customDirectories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, idx) {
                    final dir = provider.customDirectories[idx];
                    return Chip(
                      backgroundColor: AppColors.surfaceElevated,
                      avatar: const Icon(
                        Icons.folder_open_rounded,
                        size: 16,
                        color: AppColors.spotifyGreen,
                      ),
                      label: Text(
                        p.basename(dir).isEmpty ? dir : p.basename(dir),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onDeleted: () => provider.removeCustomDirectory(dir),
                    );
                  },
                ),
              ),
            ),

          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.folder_off_rounded,
                        size: 62,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Belum Ada Direktori Musik',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tekan "Tambah Direktori" untuk memilih folder musik lokal di perangkat Anda. Semua lagu otomatis dikelompokkan berdasarkan direktorinya.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.spotifyGreen,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: provider.pickAndAddDirectory,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text(
                          'Pilih Direktori Sekarang',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_gridMode)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.96,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, idx) {
                    final group = filtered[idx];
                    return _DirectoryGridTile(group: group);
                  },
                  childCount: filtered.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 8, bottom: 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, idx) {
                    final group = filtered[idx];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          color: AppColors.neonCyan,
                        ),
                      ),
                      title: Text(
                        group.directoryName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${group.trackCount} lagu • ${group.directoryPath}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: AppColors.spotifyGreen,
                          size: 34,
                        ),
                        onPressed: () => provider.playTrackList(group.tracks),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => DirectoryDetailScreen(group: group),
                          ),
                        );
                      },
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DirectoryGridTile extends StatelessWidget {
  final MusicDirectoryGroup group;

  const _DirectoryGridTile({required this.group});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicProvider>();
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DirectoryDetailScreen(group: group),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2236), Color(0xFF111622)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
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
                    Icons.folder_copy_rounded,
                    color: AppColors.neonCyan,
                    size: 28,
                  ),
                ),
                GestureDetector(
                  onTap: () => provider.playTrackList(group.tracks),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.spotifyGreen,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (group.isCustomRoot)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.spotifyGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'FOLDER PILIHAN',
                  style: TextStyle(
                    color: AppColors.spotifyGreen,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Text(
              group.directoryName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${group.trackCount} Lagu Offline',
              style: const TextStyle(
                color: AppColors.neonCyan,
                fontWeight: FontWeight.w700,
                fontSize: 12,
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

class DirectoryDetailScreen extends StatefulWidget {
  final MusicDirectoryGroup group;

  const DirectoryDetailScreen({
    super.key,
    required this.group,
  });

  @override
  State<DirectoryDetailScreen> createState() => _DirectoryDetailScreenState();
}

class _DirectoryDetailScreenState extends State<DirectoryDetailScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final liveGroup = provider.combinedDirectoryGroups.firstWhere(
      (g) => g.directoryPath == widget.group.directoryPath,
      orElse: () => widget.group,
    );
    final tracks = _filter.trim().isEmpty
        ? liveGroup.tracks
        : liveGroup.tracks
            .where((t) =>
                t.title.toLowerCase().contains(_filter.toLowerCase()) ||
                t.artist.toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 245,
            pinned: true,
            backgroundColor: AppColors.surface,
            actions: [
              IconButton(
                tooltip: 'Jadikan Playlist M3U Offline',
                icon: const Icon(Icons.playlist_add_check_circle_outlined),
                onPressed: () async {
                  final pl = await provider.createOfflinePlaylistFromTracks(
                    name: 'Folder ${liveGroup.directoryName}',
                    tracks: liveGroup.tracks,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Playlist M3U "${pl.name}" berhasil dibuat!',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.spotifyHeroGradient,
                ),
                padding: const EdgeInsets.fromLTRB(20, 88, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const AppLogo(size: 92, borderRadius: 20, showGlow: true),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DIREKTORI LOKAL',
                            style: TextStyle(
                              color: AppColors.neonCyan,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            liveGroup.directoryName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            liveGroup.directoryPath,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
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
          ),

          // Spotify Action Strip
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _filter = v),
                      decoration: InputDecoration(
                        hintText:
                            'Cari di dalam folder (${liveGroup.trackCount} lagu)...',
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
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: 'Putar Acak Folder',
                    onPressed: tracks.isEmpty
                        ? null
                        : () => provider.playTrackList(tracks, shuffle: true),
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                  const SizedBox(width: 6),
                  FloatingActionButton.small(
                    heroTag: 'play_dir_${liveGroup.directoryPath}',
                    backgroundColor: AppColors.spotifyGreen,
                    foregroundColor: Colors.black,
                    onPressed: tracks.isEmpty
                        ? null
                        : () => provider.playTrackList(tracks),
                    child: const Icon(Icons.play_arrow_rounded, size: 26),
                  ),
                ],
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, idx) {
                final track = tracks[idx];
                return TrackTile(
                  track: track,
                  indexNumber: idx + 1,
                  showDirectoryBadge: false,
                  onTap: () => provider.playTrackList(
                    tracks,
                    initialIndex: idx,
                  ),
                );
              },
              childCount: tracks.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }
}
