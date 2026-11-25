import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/jellyfin_profile_models.dart';
import '../providers/music_provider.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../services/update_checker_service.dart';
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
  bool _controllersSeeded = false;

  @override
  void initState() {
    super.initState();
    final jf = context.read<ProfileJellyfinProvider>();
    _nameCtrl = TextEditingController(text: jf.displayName);
    _bioCtrl = TextEditingController(text: jf.bioSubtitle);
    _controllersSeeded = jf.initialized;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final jf = context.watch<ProfileJellyfinProvider>();
    if (!_controllersSeeded && jf.initialized) {
      _nameCtrl.text = jf.displayName;
      _bioCtrl.text = jf.bioSubtitle;
      _controllersSeeded = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
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
                                    'Avatar Hallsem',
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
                TextField(
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
                label: 'Cinema',
                color: AppColors.netflixRed,
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ==================== 3. STATUS HALLSEM CINEMA TERINTEGRASI ====================
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
                color: AppColors.spotifyGreen.withValues(alpha: 0.35),
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
                            'Hallsem Cinema Terintegrasi',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${jf.serverName} • Akun: ${jf.activeUsername} (${jf.movies.length} film)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.spotifyGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.netflixRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: widget.onOpenMoviesTab,
                        icon: const Icon(Icons.movie_filter_rounded),
                        label: const Text(
                          'Buka Hallsem Cinema',
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
                      onPressed: jf.isLoadingMovies
                          ? null
                          : () => jf.connectAndSyncBuiltInJellyfin(),
                      icon: jf.isLoadingMovies
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: const Text('Sinkron'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ==================== 4. INFORMASI DEVELOPER (zusfan.hallosemarang.com) ====================
          Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: AppColors.neonCyan.withValues(alpha: 0.28)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.code_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'INFORMASI DEVELOPER',
                              style: TextStyle(
                                color: AppColors.neonCyan,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Zusfan Mashuri',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Marketing Strategist • IT Builder • Public Service Innovator',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.surfaceHighlight),
                  _DeveloperLinkRow(
                    icon: Icons.badge_outlined,
                    label: 'Digital Card',
                    value: 'https://zusfan.hallosemarang.com',
                    onCopy: () => _copyValue(
                      context,
                      'https://zusfan.hallosemarang.com',
                      'Link profil developer disalin!',
                    ),
                  ),
                  _DeveloperLinkRow(
                    icon: Icons.public_rounded,
                    label: 'Website',
                    value: 'https://www.hallosemarang.com',
                    onCopy: () => _copyValue(
                      context,
                      'https://www.hallosemarang.com',
                      'Alamat website disalin!',
                    ),
                  ),
                  _DeveloperLinkRow(
                    icon: Icons.chat_outlined,
                    label: 'WhatsApp',
                    value: '+62 899-8813-000',
                    onCopy: () => _copyValue(
                      context,
                      'https://wa.me/628998813000',
                      'Link WhatsApp developer disalin!',
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // ==================== 5. PENGATURAN PEMUTAR & PENYIMPANAN ====================
          Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
                    leading: const Icon(
                      Icons.system_update_rounded,
                      color: AppColors.spotifyGreen,
                    ),
                    title: const Text(
                      'Cek Pembaruan Aplikasi',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Versi terpasang: ${UpdateCheckerService.instance.fullVersionString}',
                    ),
                    trailing: ValueListenableBuilder<AppRelease?>(
                      valueListenable:
                          UpdateCheckerService.instance.availableUpdateNotifier,
                      builder: (_, rel, _) => rel != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.spotifyGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'v${rel.versionClean}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                    ),
                    onTap: () => UpdateCheckerService.instance
                        .checkAndShowUpdateDialog(context, isManualCheck: true),
                  ),
                  const Divider(height: 1, color: AppColors.surfaceHighlight),
                  const ListTile(
                    leading: AppLogo(size: 36, borderRadius: 9),
                    title: Text(
                      'M3U Musik & Hallsem Cinema',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Offline M3U, Direktori, IPTV Video & Hallsem Cinema',
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

  Future<void> _copyValue(
    BuildContext context,
    String text,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
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

class _DeveloperLinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onCopy;

  const _DeveloperLinkRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.textSecondary, size: 20),
      title: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11.5,
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: IconButton(
        tooltip: 'Salin $label',
        icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.neonCyan),
        onPressed: onCopy,
      ),
      onTap: onCopy,
    );
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
