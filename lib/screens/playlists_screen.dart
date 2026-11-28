import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_models.dart';
import '../providers/music_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';
import 'm3u_video_player_screen.dart';

/// Derives a city name from a channel group title,
/// e.g. `CCTV Kota Yogyakarta - UMBULHARJO` -> `Yogyakarta`,
/// `DINAS PERHUBUNGAN KOTA SEMARANG` -> `Semarang`, `CCTV DKI Jakarta` -> `Jakarta`.
String cityFromGroupTitle(String rawGroup) {
  const noise = {
    'cctv',
    'tv',
    'kota',
    'kab',
    'kab.',
    'kabupaten',
    'live',
    'streaming',
    'pemkot',
    'pemkab',
    'dki',
    'dinas',
    'perhubungan',
    'diskominfo',
    'dishub',
    'dpu',
    'dan',
  };
  final base = rawGroup
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .split(' - ')
      .first
      .replaceAll(RegExp(r'\.(m3u8?|txt)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[_\-]+'), ' ');
  final words = base
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !noise.contains(w.toLowerCase()))
      .toList();
  if (words.isEmpty) return 'CCTV Lainnya';
  final city = words
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
  return 'CCTV $city';
}

/// Area / district part of a group title (text after ` - `), or the group itself.
String areaFromGroupTitle(String rawGroup) {
  final parts = rawGroup.split(' - ');
  final area = parts.length > 1 ? parts.sublist(1).join(' - ').trim() : '';
  if (area.isNotEmpty && area.toLowerCase() != 'none') {
    return area
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }
  return rawGroup.replaceAll(RegExp(r'\s+-\s*$'), '').trim();
}

bool _looksLikeCityGroup(String? group) {
  if (group == null) return false;
  final g = group.toLowerCase();
  return g.contains('cctv') ||
      g.contains('kota ') ||
      g.contains('kabupaten') ||
      g.contains('dinas ') ||
      g.contains('diskominfo');
}

/// A playlist is a "city playlist" when most of its channels belong to city groups.
bool isCityPlaylist(M3uPlaylist pl) {
  if (pl.tracks.isEmpty) return false;
  final hits = pl.tracks.where((t) => _looksLikeCityGroup(t.groupTitle)).length;
  return hits * 2 >= pl.tracks.length ||
      pl.name.toLowerCase().contains('cctv');
}

class _CityGroup {
  final String city;
  final List<TrackItem> tracks;
  const _CityGroup(this.city, this.tracks);
}

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  String _filterType = 'Kota'; // Kota | Semua | File | Link
  static bool _bundledCctvLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBundledCctv());
  }

  Future<void> _loadBundledCctv() async {
    if (_bundledCctvLoaded || !mounted) return;
    _bundledCctvLoaded = true;
    await context.read<MusicProvider>().syncGithubM3uDirectory();
  }

  Future<void> _pickAndImportFolder() async {
    final provider = context.read<MusicProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickDirectory(
      dialogTitle: 'Pilih folder berisi file M3U',
    );
    final dir = picked?.path;
    if (dir == null || dir.isEmpty) return;
    final count = await provider.importM3uFolder(dir);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? '$count playlist TV dari folder berhasil dimuat!'
              : 'Tidak ada file .m3u / .m3u8 di folder tersebut.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final pendingNotice = provider.pendingGithubM3uNotice;
    if (pendingNotice != null) {
      provider.clearGithubM3uNotice();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(
                  Icons.cloud_done_rounded,
                  color: AppColors.spotifyGreen,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(pendingNotice)),
              ],
            ),
          ),
        );
      });
    }
    final allPlaylists = provider.playlists;
    final filtered = allPlaylists.where((pl) {
      if (_filterType == 'File') return !pl.isUrlSource;
      if (_filterType == 'Link') return pl.isUrlSource;
      return true;
    }).toList();

    // Rows: _CityGroup (expandable, channels grouped by city), String header,
    // and M3uPlaylist cards (non-city playlists / other filters).
    final List<Object> rows = [];
    int cityCount = 0;
    if (_filterType == 'Kota') {
      final byCity = <String, List<TrackItem>>{};
      final seenUrls = <String, Set<String>>{};
      final others = <M3uPlaylist>[];
      for (final pl in filtered) {
        if (!isCityPlaylist(pl)) {
          others.add(pl);
          continue;
        }
        final city = cityFromGroupTitle(pl.name);
        final seen = seenUrls.putIfAbsent(city, () => <String>{});
        final bucket = byCity.putIfAbsent(city, () => []);
        for (final t in pl.tracks) {
          if (!seen.add(t.pathOrUrl)) continue;
          bucket.add(t);
        }
      }
      final cities = byCity.keys.toList()
        ..sort((a, b) {
          if (a == 'CCTV Lainnya' || a == 'Lainnya') return 1;
          if (b == 'CCTV Lainnya' || b == 'Lainnya') return -1;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
      cityCount = cities.length;
      for (final city in cities) {
        rows.add(_CityGroup(city, byCity[city]!));
      }
      if (others.isNotEmpty) {
        rows.add('TV Lainnya');
        rows.addAll(others);
      }
    } else {
      rows.addAll(filtered);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 30, borderRadius: 8),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'TV & IPTV (File & Link)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cek Update M3U GitHub',
            icon: provider.isSyncingGithubM3u
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_rounded),
            onPressed: provider.isSyncingGithubM3u
                ? null
                : () => provider.syncGithubM3uDirectory(
                      showNoChangeNotice: true,
                    ),
          ),
          IconButton(
            tooltip: 'Impor Folder M3U',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: _pickAndImportFolder,
          ),
          IconButton(
            tooltip: 'Tambah Playlist TV',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => AddM3uBottomSheet.show(context),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Dual Source Action Cards (File TV + Link URL TV)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _QuickM3uSourceButton(
                          icon: Icons.upload_file_rounded,
                          title: 'Impor File TV',
                          subtitle: 'Bisa pilih banyak file',
                          color: AppColors.spotifyGreen,
                          onTap: () async {
                            final count =
                                await provider.pickAndImportM3uFiles();
                            if (context.mounted && count > 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$count file playlist TV berhasil ditambahkan!',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickM3uSourceButton(
                          icon: Icons.add_link_rounded,
                          title: 'Tambah Link TV',
                          subtitle: 'Satu / banyak URL',
                          color: AppColors.neonPurple,
                          onTap: () => AddM3uBottomSheet.show(
                            context,
                            startWithUrlTab: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final tab in const ['Kota', 'Semua', 'Link'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                tab == 'Kota'
                                    ? (cityCount > 0 ? 'Per Kota ($cityCount)' : 'Per Kota')
                                    : tab == 'Semua'
                                        ? 'Semua (${allPlaylists.length})'
                                        : 'Alamat Link (${allPlaylists.where((p) => p.isUrlSource).length})',
                                style: TextStyle(
                                  fontWeight: _filterType == tab
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: _filterType == tab
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              selected: _filterType == tab,
                              onSelected: (_) =>
                                  setState(() => _filterType = tab),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (provider.isImportingM3u)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: LinearProgressIndicator(color: AppColors.neonCyan),
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
                      const AppLogo(size: 76, borderRadius: 18, showGlow: true),
                      const SizedBox(height: 16),
                      const Text(
                        'Kelola Banyak Playlist M3U Sekaligus',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tambahkan satu atau banyak file .m3u / .m3u8 untuk mode offline maupun alamat link URL. Semua playlist tersimpan otomatis dan bisa diunduh offline.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.spotifyGreen,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => AddM3uBottomSheet.show(context),
                        icon: const Icon(Icons.playlist_add_rounded),
                        label: const Text(
                          'Tambah Playlist M3U Pertama',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, idx) {
                    final row = rows[idx];
                    if (row is _CityGroup) {
                      return _CityExpansionCard(group: row);
                    }
                    if (row is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
                        child: Text(
                          row,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text(ctx),
                          ),
                        ),
                      );
                    }
                    return _PlaylistCardItem(playlist: row as M3uPlaylist);
                  },
                  childCount: rows.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CityExpansionCard extends StatelessWidget {
  final _CityGroup group;
  const _CityExpansionCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.isDark(context)
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(
            Icons.location_city_rounded,
            color: AppColors.netflixRed,
          ),
          title: Text(
            group.city,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.text(context),
            ),
          ),
          subtitle: Text(
            '${group.tracks.length} channel',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.subtext(context),
            ),
          ),
          iconColor: AppColors.text(context),
          collapsedIconColor: AppColors.subtext(context),
          children: [
            for (int i = 0; i < group.tracks.length; i++)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.videocam_rounded,
                  color: AppColors.subtext(context),
                  size: 20,
                ),
                title: Text(
                  group.tracks[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  areaFromGroupTitle(group.tracks[i].groupTitle ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.subtext(context),
                    fontSize: 11.5,
                  ),
                ),
                trailing: Icon(
                  Icons.play_circle_outline_rounded,
                  color: AppColors.subtext(context),
                ),
                onTap: () => M3uPlaybackLauncher.playItemList(
                  context,
                  group.tracks,
                  initialIndex: i,
                  forceVideoPlayer: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickM3uSourceButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickM3uSourceButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    subtitle,
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

class _PlaylistCardItem extends StatelessWidget {
  final M3uPlaylist playlist;

  const _PlaylistCardItem({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicProvider>();
    final isLink = playlist.isUrlSource;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.isDark(context)
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: const AppLogo(size: 52, borderRadius: 12),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isLink
                    ? AppColors.neonPurple.withValues(alpha: 0.22)
                    : AppColors.spotifyGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                isLink ? 'LINK' : 'FILE',
                style: TextStyle(
                  color: isLink ? AppColors.neonPurple : AppColors.spotifyGreen,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  decoration:
                      playlist.isEnabled ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                playlist.videoTrackCount > 0
                    ? '${playlist.tracks.length} item • ${playlist.videoTrackCount} video/TV'
                    : '${playlist.tracks.length} lagu • ${playlist.offlineTrackCount} siap offline',
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                playlist.sourceLocation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Putar Playlist',
              icon: const Icon(
                Icons.play_circle_fill_rounded,
                color: AppColors.spotifyGreen,
                size: 32,
              ),
              onPressed: playlist.tracks.isEmpty
                  ? null
                  : () => M3uPlaybackLauncher.playItemList(
                        context,
                        playlist.tracks,
                      ),
            ),
            PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'toggle') {
                  await provider.togglePlaylistEnabled(playlist.id);
                } else if (action == 'refresh') {
                  try {
                    await provider.refreshM3uPlaylist(playlist.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Playlist "${playlist.name}" diperbarui!'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal memperbarui: $e')),
                      );
                    }
                  }
                } else if (action == 'download_all') {
                  final saved =
                      await provider.downloadEntirePlaylistOffline(playlist.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '$saved/${playlist.tracks.length} lagu siap diputar offline!',
                        ),
                      ),
                    );
                  }
                } else if (action == 'rename') {
                  showDialog<void>(
                    context: context,
                    builder: (_) => _RenamePlaylistDialog(
                      playlist: playlist,
                      provider: provider,
                    ),
                  );
                } else if (action == 'delete') {
                  await provider.deletePlaylist(playlist.id);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    playlist.isEnabled
                        ? 'Nonaktifkan Sementara'
                        : 'Aktifkan Playlist',
                  ),
                ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: Text('Muat Ulang / Sinkronkan M3U'),
                ),
                if (isLink)
                  const PopupMenuItem(
                    value: 'download_all',
                    child: Text('Simpan Semua Lagu ke Offline'),
                  ),
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('Ubah Nama Playlist'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Hapus Playlist',
                    style: TextStyle(color: AppColors.netflixRed),
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
            ),
          );
        },
      ),
    );
  }
}

class _RenamePlaylistDialog extends StatefulWidget {
  final M3uPlaylist playlist;
  final MusicProvider provider;

  const _RenamePlaylistDialog({
    required this.playlist,
    required this.provider,
  });

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.playlist.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ubah Nama Playlist M3U'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Nama Playlist'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.provider.renamePlaylist(widget.playlist.id, _controller.text);
            Navigator.pop(context);
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  String _search = '';
  String _selectedGroup = 'Semua';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final idx = provider.playlists.indexWhere((p) => p.id == widget.playlistId);
    if (idx < 0) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Playlist tidak ditemukan.')),
      );
    }

    final playlist = provider.playlists[idx];
    final deadInPlaylist = playlist.tracks
        .where((t) => provider.isTrackDead(t.id))
        .length;
    final favInPlaylist = playlist.tracks
        .where((t) => provider.isFavorite(t.id))
        .length;
    final groups = <String>{
      'Semua',
      if (favInPlaylist > 0) 'Favorit',
      ...playlist.tracks
          .map((t) => t.groupTitle)
          .whereType<String>()
          .where((g) => g.isNotEmpty),
    }.toList();

    final effectiveGroup =
        groups.contains(_selectedGroup) ? _selectedGroup : 'Semua';

    final tracks = playlist.tracks.where((t) {
      if (provider.hideDeadLinks && provider.isTrackDead(t.id)) {
        return false;
      }
      if (effectiveGroup == 'Favorit') {
        if (!provider.isFavorite(t.id)) return false;
      } else if (effectiveGroup != 'Semua' && t.groupTitle != effectiveGroup) {
        return false;
      }
      if (_search.trim().isEmpty) return true;
      final q = _search.toLowerCase();
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          (t.groupTitle?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: AppColors.card(context),
            actions: [
              IconButton(
                tooltip: 'Cek Kesehatan Link M3U (Auto-Hide Link Mati)',
                icon: provider.isCheckingLinks
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.spotifyGreen,
                        ),
                      )
                    : const Icon(
                        Icons.health_and_safety_rounded,
                        color: AppColors.spotifyGreen,
                      ),
                onPressed: provider.isCheckingLinks
                    ? null
                    : () async {
                        final res =
                            await provider.checkPlaylistLinks(playlist.id);
                        if (!provider.hideDeadLinks && res.deadCount > 0) {
                          await provider.setHideDeadLinks(true);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Selesai cek ${res.totalChecked} link: '
                                '${res.onlineCount} aktif, '
                                '${res.deadCount} mati (otomatis disembunyikan).',
                              ),
                            ),
                          );
                        }
                      },
              ),
              if (playlist.isUrlSource)
                IconButton(
                  tooltip: 'Unduh Semua Lagu untuk Offline',
                  icon: const Icon(
                    Icons.offline_pin_outlined,
                    color: AppColors.neonCyan,
                  ),
                  onPressed: () async {
                    final count = await provider
                        .downloadEntirePlaylistOffline(playlist.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '$count/${playlist.tracks.length} lagu siap offline!',
                          ),
                        ),
                      );
                    }
                  },
                ),
              IconButton(
                tooltip: 'Sinkronkan Ulang M3U',
                icon: const Icon(Icons.sync_rounded),
                onPressed: provider.isImportingM3u
                    ? null
                    : () async {
                        try {
                          await provider.refreshM3uPlaylist(playlist.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Playlist "${playlist.name}" berhasil disinkronkan!',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Gagal menyinkronkan: $e'),
                              ),
                            );
                          }
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
                          Text(
                            playlist.isUrlSource
                                ? 'PLAYLIST M3U DARI LINK URL'
                                : 'PLAYLIST M3U FILE OFFLINE',
                            style: const TextStyle(
                              color: AppColors.neonCyan,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            playlist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${playlist.tracks.length} lagu • ${playlist.offlineTrackCount} siap offline',
                            style: const TextStyle(
                              color: AppColors.spotifyGreen,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            playlist.sourceLocation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
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

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v),
                          decoration: InputDecoration(
                            hintText: 'Cari channel IPTV, lagu, atau grup...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: AppColors.card(context),
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
                        tooltip: 'Acak Playlist',
                        onPressed: tracks.isEmpty
                            ? null
                            : () => M3uPlaybackLauncher.playItemList(
                                  context,
                                  tracks,
                                  shuffle: true,
                                ),
                        icon: const Icon(Icons.shuffle_rounded),
                      ),
                      const SizedBox(width: 6),
                      FloatingActionButton.small(
                        heroTag: 'play_m3u_${playlist.id}',
                        backgroundColor: AppColors.spotifyGreen,
                        foregroundColor: Colors.white,
                        onPressed: tracks.isEmpty
                            ? null
                            : () => M3uPlaybackLauncher.playItemList(
                                  context,
                                  tracks,
                                ),
                        child: const Icon(Icons.play_arrow_rounded, size: 26),
                      ),
                    ],
                  ),
                  if (provider.isCheckingLinks) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: provider.linkCheckTotal > 0
                          ? provider.linkCheckDone / provider.linkCheckTotal
                          : null,
                      color: AppColors.spotifyGreen,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Memeriksa kesehatan link (${provider.linkCheckDone}/${provider.linkCheckTotal})...',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  if (deadInPlaylist > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.highlight(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            provider.hideDeadLinks
                                ? Icons.visibility_off_rounded
                                : Icons.warning_amber_rounded,
                            size: 16,
                            color: provider.hideDeadLinks
                                ? AppColors.neonCyan
                                : Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              provider.hideDeadLinks
                                  ? '$deadInPlaylist link mati otomatis disembunyikan'
                                  : '$deadInPlaylist link mati sedang ditampilkan',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () => provider
                                .setHideDeadLinks(!provider.hideDeadLinks),
                            child: Text(
                              provider.hideDeadLinks
                                  ? 'Tampilkan'
                                  : 'Sembunyikan',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (groups.length > 1) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: groups.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, gIdx) {
                          final g = groups[gIdx];
                          return ChoiceChip(
                            label: Text(g),
                            selected: _selectedGroup == g,
                            onSelected: (_) =>
                                setState(() => _selectedGroup = g),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, tIdx) {
                final track = tracks[tIdx];
                return TrackTile(
                  track: track,
                  indexNumber: tIdx + 1,
                  onTap: () => M3uPlaybackLauncher.playItemList(
                    context,
                    tracks,
                    initialIndex: tIdx,
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

/// Modal Bottom Sheet for adding M3U playlists from File(s), URL Link(s), or creating a new offline M3U.
class AddM3uBottomSheet extends StatefulWidget {
  final bool startWithUrlTab;

  const AddM3uBottomSheet({
    super.key,
    this.startWithUrlTab = false,
  });

  static void show(BuildContext context, {bool startWithUrlTab = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddM3uBottomSheet(startWithUrlTab: startWithUrlTab),
    );
  }

  @override
  State<AddM3uBottomSheet> createState() => _AddM3uBottomSheetState();
}

class _AddM3uBottomSheetState extends State<AddM3uBottomSheet> {
  late int _mode; // 0 = File, 1 = Link URL, 2 = Buat Offline M3U Baru
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.startWithUrlTab ? 1 : 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AppLogo(size: 36, borderRadius: 9),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tambah Playlist M3U',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.insert_drive_file_outlined),
                  label: Text('File M3U'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.link_rounded),
                  label: Text('Alamat Link'),
                ),
                ButtonSegment(
                  value: 2,
                  icon: Icon(Icons.library_add_rounded),
                  label: Text('Buat Baru'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 18),

            if (_mode == 0) ...[
              const Text(
                'Impor File Playlist M3U / M3U8 Offline',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Anda dapat memilih satu atau beberapa file .m3u / .m3u8 sekaligus dari penyimpanan HP. Path relatif maupun absolut otomatis dipetakan untuk pemutaran offline.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.spotifyGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _submitting
                      ? null
                      : () async {
                          setState(() => _submitting = true);
                          try {
                            final count =
                                await provider.pickAndImportM3uFiles();
                            if (context.mounted) {
                              Navigator.pop(context);
                              if (count > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '$count file playlist M3U berhasil diimpor!',
                                    ),
                                  ),
                                );
                              } else if (provider.lastError != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(provider.lastError!)),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gagal mengimpor: $e')),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _submitting = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text(
                    'Pilih File .M3U / .M3U8 (Bisa Lebih dari Satu)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ] else if (_mode == 1) ...[
              const Text(
                'Tambah Playlist M3U dari Alamat Link URL',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Masukkan satu atau beberapa alamat link M3U/M3U8 (pisahkan dengan baris baru jika lebih dari satu link). Daftar lagu otomatis di-cache dan audio dapat disimpan untuk offline.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nama Playlist (Opsional)',
                  hintText: 'Contoh: Lagu Santai / Radio Musik',
                  filled: true,
                  fillColor: AppColors.elevated(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: 'Alamat Link TV (.m3u / .m3u8, satu per baris)',
                  hintText:
                      'https://iptv-org.github.io/iptv/countries/id.m3u\nhttps://server.com/playlist2.m3u8',
                  filled: true,
                  fillColor: AppColors.elevated(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _submitting
                      ? null
                      : () async {
                          setState(() => _submitting = true);
                          try {
                            final added = await provider.addM3uFromUrls(
                              rawUrlsInput: _urlController.text,
                              customName: _nameController.text,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$added link playlist TV berhasil ditambahkan!',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _submitting = false);
                            }
                          }
                        },
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_download_rounded),
                  label: Text(
                    _submitting ? 'Mengimpor Link TV...' : 'Simpan Link TV',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ] else ...[
              const Text(
                'Buat File Playlist TV Offline dari Koleksi Lokal',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                'Buat playlist .m3u8 offline baru dari lagu yang sudah terdeteksi di direktori (${provider.allTracks.length} lagu tersedia).',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nama Playlist TV Offline',
                  hintText: 'Contoh: Favorit Perjalanan Offline',
                  filled: true,
                  fillColor: AppColors.elevated(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.spotifyGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: provider.allTracks.isEmpty || _submitting
                      ? null
                      : () async {
                          final title = _nameController.text.trim().isEmpty
                              ? 'Koleksi Offline ${provider.playlists.length + 1}'
                              : _nameController.text.trim();
                          setState(() => _submitting = true);
                          try {
                            await provider.createOfflinePlaylistFromTracks(
                              name: title,
                              tracks: provider.allTracks,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Playlist TV offline "$title" berhasil dibuat!',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Gagal membuat playlist: $e'),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _submitting = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text(
                    'Buat & Simpan File TV Offline',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
