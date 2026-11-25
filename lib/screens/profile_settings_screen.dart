import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/jellyfin_profile_models.dart';
import '../providers/music_provider.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar_widget.dart';

class ProfileSettingsScreen extends StatefulWidget {
  final VoidCallback? onOpenMoviesTab;

  const ProfileSettingsScreen({
    super.key,
    this.onOpenMoviesTab,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _serverUrlCtrl;
  final TextEditingController _apiCodeCtrl = TextEditingController();
  bool _obscureApiCode = true;
  bool _controllersSeeded = false;

  @override
  void initState() {
    super.initState();
    final jf = context.read<ProfileJellyfinProvider>();
    _nameCtrl = TextEditingController(text: jf.displayName);
    _bioCtrl = TextEditingController(text: jf.bioSubtitle);
    _serverUrlCtrl = TextEditingController(text: jf.serverUrl);
    _controllersSeeded = jf.initialized;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final jf = context.watch<ProfileJellyfinProvider>();
    if (!_controllersSeeded && jf.initialized) {
      _nameCtrl.text = jf.displayName;
      _bioCtrl.text = jf.bioSubtitle;
      _serverUrlCtrl.text = jf.serverUrl;
      _controllersSeeded = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _serverUrlCtrl.dispose();
    _apiCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jf = context.watch<ProfileJellyfinProvider>();
    final music = context.watch<MusicProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 30, borderRadius: 8),
            SizedBox(width: 10),
            Text('Profil & Setting'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 130),
        children: [
          // ==================== 1. PROFIL & ATUR AVATAR ====================
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E263B), Color(0xFF121622)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        UserAvatarWidget(
                          size: 82,
                          onTap: () => _pickAvatarPhoto(context, jf),
                        ),
                        GestureDetector(
                          onTap: () => _pickAvatarPhoto(context, jf),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.spotifyGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.background,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 15,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            jf.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            jf.bioSubtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _pickAvatarPhoto(context, jf),
                                icon: const Icon(
                                  Icons.photo_library_outlined,
                                  size: 16,
                                  color: AppColors.neonCyan,
                                ),
                                label: const Text(
                                  'Upload Foto',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              if (jf.jellyfinUserAvatarUrl != null)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: jf.useJellyfinAvatar,
                                  icon: const Icon(
                                    Icons.account_circle_outlined,
                                    size: 16,
                                    color: AppColors.neonPurple,
                                  ),
                                  label: const Text(
                                    'Avatar Jellyfin',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),
                const Text(
                  'Pilih Karakter Avatar Preset',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 74,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AvatarPresetStyle.presets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, idx) {
                      final style = AvatarPresetStyle.presets[idx];
                      final isSelected =
                          jf.avatarMode == AvatarSourceMode.preset &&
                              jf.avatarPresetIndex == idx;
                      return GestureDetector(
                        onTap: () => jf.selectPresetAvatar(idx),
                        child: Column(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: style.gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: isSelected
                                    ? Border.all(
                                        color: AppColors.spotifyGreen,
                                        width: 2.5,
                                      )
                                    : null,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    style.icon,
                                    color: Colors.white,
                                    size: 25,
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      right: 2,
                                      bottom: 2,
                                      child: Container(
                                        padding: const EdgeInsets.all(1.5),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.spotifyGreen,
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 11,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              style.label.split(' ').first,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isSelected
                                    ? AppColors.spotifyGreen
                                    : AppColors.textSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Nama Tampilan Profil',
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bioCtrl,
                  decoration: InputDecoration(
                    labelText: 'Bio / Tagline Profil',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.spotifyGreen,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      await jf.updateProfileInfo(
                        displayName: _nameCtrl.text,
                        bioSubtitle: _bioCtrl.text,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Profil berhasil disimpan!'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text(
                      'Simpan Profil',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ==================== 2. STATISTIK RINGKAS ====================
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
            children: [
              _StatMiniCard(
                value: '${music.allTracks.length}',
                label: 'Lagu',
                color: AppColors.spotifyGreen,
              ),
              _StatMiniCard(
                value: '${music.combinedDirectoryGroups.length}',
                label: 'Direktori',
                color: AppColors.neonCyan,
              ),
              _StatMiniCard(
                value: '${music.playlists.length}',
                label: 'M3U',
                color: AppColors.neonPurple,
              ),
              _StatMiniCard(
                value: '${jf.movies.length}',
                label: 'Film JF',
                color: AppColors.netflixRed,
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ==================== 3. SETTING JELLYFIN API CODE ====================
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF28121B), Color(0xFF121622)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: jf.isConnected
                    ? AppColors.spotifyGreen.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.netflixRed.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.live_tv_rounded,
                        color: AppColors.netflixRed,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Integrasi Server & API Code Jellyfin',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            jf.isConnected
                                ? 'Terhubung ke ${jf.serverName.isNotEmpty ? jf.serverName : jf.serverUrl} (${jf.movies.length} film)'
                                : 'Masukkan Server URL & API Code untuk memutar film Jellyfin',
                            style: TextStyle(
                              fontSize: 12,
                              color: jf.isConnected
                                  ? AppColors.spotifyGreen
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _serverUrlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Alamat Server Jellyfin',
                    hintText: 'Contoh: http://192.168.1.100:8096',
                    prefixIcon: const Icon(Icons.dns_outlined),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiCodeCtrl,
                  obscureText: _obscureApiCode,
                  decoration: InputDecoration(
                    labelText: jf.hasCredentials
                        ? 'API Code Jellyfin (${jf.maskedApiCode})'
                        : 'API Code / API Key Jellyfin',
                    hintText: jf.hasCredentials
                        ? 'Kosongkan jika tetap memakai API Code tersimpan'
                        : 'Tempel API Key dari Dashboard Jellyfin -> API Keys',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Tempel dari Clipboard',
                          icon: const Icon(Icons.content_paste_rounded, size: 19),
                          onPressed: () async {
                            final clip = await Clipboard.getData('text/plain');
                            if (clip?.text != null &&
                                clip!.text!.trim().isNotEmpty) {
                              setState(() {
                                _apiCodeCtrl.text = clip.text!.trim();
                              });
                            }
                          },
                        ),
                        IconButton(
                          tooltip: _obscureApiCode
                              ? 'Tampilkan API Code'
                              : 'Sembunyikan API Code',
                          icon: Icon(
                            _obscureApiCode
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 19,
                          ),
                          onPressed: () => setState(
                            () => _obscureApiCode = !_obscureApiCode,
                          ),
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tips: Buka Jellyfin Dashboard -> Administration -> Advanced -> API Keys -> klik (+) untuk membuat API Code baru.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),

                if (jf.errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.netflixRed.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      jf.errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],

                if (jf.availableUsers.length > 1) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Profil User Jellyfin Aktif:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final u in jf.availableUsers)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(u.name),
                              selected: jf.selectedUserId == u.id,
                              onSelected: (_) => jf.selectJellyfinUser(u.id),
                            ),
                          ),
                      ],
                    ),
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
                        onPressed: jf.isTestingConnection
                            ? null
                            : () async {
                                final ok = await jf.saveAndConnectJellyfin(
                                  rawServerUrl: _serverUrlCtrl.text,
                                  rawApiCode: _apiCodeCtrl.text,
                                );
                                if (ok) {
                                  _apiCodeCtrl.clear();
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? 'Terhubung ke Jellyfin "${jf.serverName}" (${jf.movies.length} film dimuat)!'
                                            : (jf.errorMessage ??
                                                'Gagal terhubung ke server Jellyfin.'),
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: jf.isTestingConnection
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.bolt_rounded),
                        label: Text(
                          jf.isTestingConnection
                              ? 'Menghubungkan...'
                              : 'Simpan & Hubungkan Jellyfin',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                if (jf.hasCredentials) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (widget.onOpenMoviesTab != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: widget.onOpenMoviesTab,
                            icon: const Icon(
                              Icons.movie_creation_outlined,
                              color: AppColors.spotifyGreen,
                            ),
                            label: const Text('Buka Katalog Film'),
                          ),
                        ),
                      if (widget.onOpenMoviesTab != null)
                        const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          await jf.disconnectJellyfin();
                          _serverUrlCtrl.clear();
                          _apiCodeCtrl.clear();
                        },
                        icon: const Icon(
                          Icons.link_off_rounded,
                          color: AppColors.netflixRed,
                        ),
                        label: const Text(
                          'Putuskan',
                          style: TextStyle(color: AppColors.netflixRed),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ==================== 4. PENGATURAN PEMUTAR & PENYIMPANAN ====================
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.sync_rounded,
                    color: AppColors.neonCyan,
                  ),
                  title: const Text(
                    'Pindai Ulang Semua Direktori Musik',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Segarkan pengelompokan folder lokal & deteksi M3U',
                  ),
                  trailing: music.isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: music.isScanning
                      ? null
                      : () => music.refreshPermissionsAndScan(
                            requestInteractive: true,
                            requestAllFiles: true,
                          ),
                ),
                const Divider(height: 1, color: AppColors.surfaceHighlight),
                ListTile(
                  leading: const AppLogo(size: 36, borderRadius: 9),
                  title: const Text(
                    'M3U Musik & Jellyfin Cinema',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Versi 1.1.0 • Offline M3U, Direktori & Pemutar Film Jellyfin',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatarPhoto(
    BuildContext context,
    ProfileJellyfinProvider jf,
  ) async {
    final ok = await jf.pickCustomAvatarImage();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto avatar profil berhasil diperbarui!')),
      );
    } else if (jf.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(jf.errorMessage!)),
      );
    }
  }
}

class _StatMiniCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatMiniCard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
