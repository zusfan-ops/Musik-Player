import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/jellyfin_profile_models.dart';
import '../providers/music_provider.dart';
import '../providers/profile_jellyfin_provider.dart';
import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';
import '../widgets/backend_cloud_section.dart';
import '../widgets/user_avatar_widget.dart';
import 'driving_mode_screen.dart';
import 'onboarding_screen.dart';

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
              gradient: LinearGradient(
                colors: [
                  AppColors.elevated(context),
                  AppColors.card(context),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.isDark(context)
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
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
                Text(
                  'Pilih Karakter Avatar Preset',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppColors.text(context),
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
                    fillColor: AppColors.card(context),
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
                    fillColor: AppColors.card(context),
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
                      foregroundColor: Colors.white,
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
                label: 'TV',
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
              gradient: LinearGradient(
                colors: [
                  AppColors.elevated(context),
                  AppColors.card(context),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.isDark(context)
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
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

          // ==================== PANDUAN PENGGUNAAN (ONBOARDING) ====================
          Material(
            color: AppColors.card(context),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.spotifyGreen.withValues(alpha: 0.25)),
            ),
            child: ListTile(
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.spotifyGreen.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.spotifyGreen,
                ),
              ),
              title: const Text(
                'Panduan Penggunaan Aplikasi',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              subtitle: const Text(
                'Cara scan musik, import TV, Hallsem Cinema & Widget',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => OnboardingScreen.show(context),
            ),
          ),

          const SizedBox(height: 18),

          const BackendCloudSection(),

          const SizedBox(height: 18),

          // ==================== 4. INFORMASI DEVELOPER (zusfan.hallosemarang.com) ====================
          Material(
            color: AppColors.card(context),
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
            color: AppColors.card(context),
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
                      'Segarkan pengelompokan folder lokal & deteksi playlist TV',
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
                      Icons.storage_rounded,
                      color: AppColors.spotifyGreen,
                    ),
                    title: const Text(
                      'Penyimpanan Musik Offline',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: FutureBuilder<
                        ({
                          int totalBytes,
                          int fileCount,
                          List<
                              ({
                                String name,
                                String path,
                                int fileCount,
                                int totalBytes,
                              })> folders,
                        })>(
                      future: music.getOfflineStorageSummary(),
                      builder: (_, snap) {
                        if (!snap.hasData) {
                          return const Text('Menghitung ukuran penyimpanan...');
                        }
                        final data = snap.data!;
                        final mb = (data.totalBytes / (1024 * 1024))
                            .toStringAsFixed(1);
                        return Text(
                          '${data.fileCount} lagu • $mb MB terpakai (${data.folders.length} folder)',
                        );
                      },
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showOfflineStorageManager(context, music),
                  ),
                  const Divider(height: 1, color: AppColors.surfaceHighlight),
                  ListTile(
                    leading: const Icon(
                      Icons.alarm_rounded,
                      color: AppColors.spotifyGreen,
                    ),
                    title: const Text(
                      'Alarm Musik',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      music.alarmEnabled
                          ? 'Aktif pukul ${music.alarmHour.toString().padLeft(2, '0')}:${music.alarmMinute.toString().padLeft(2, '0')} (Fade-In otomatis)'
                          : 'Putar musik otomatis pada jam tertentu',
                    ),
                    trailing: Switch(
                      value: music.alarmEnabled,
                      activeThumbColor: AppColors.spotifyGreen,
                      onChanged: (val) => music.setMusicAlarm(enabled: val),
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: music.alarmHour,
                          minute: music.alarmMinute,
                        ),
                      );
                      if (picked != null && context.mounted) {
                        await music.setMusicAlarm(
                          enabled: true,
                          hour: picked.hour,
                          minute: picked.minute,
                        );
                      }
                    },
                  ),
                  const Divider(height: 1, color: AppColors.surfaceHighlight),
                  ListTile(
                    leading: const Icon(
                      Icons.graphic_eq_rounded,
                      color: AppColors.neonCyan,
                    ),
                    title: const Text(
                      'Crossfade & Gapless Playback',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      music.crossfadeSeconds > 0
                          ? 'Transisi halus ${music.crossfadeSeconds} detik antar lagu'
                          : 'Gapless aktif (tanpa jeda, crossfade mati)',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showCrossfadePicker(context, music),
                  ),
                  const Divider(height: 1, color: AppColors.surfaceHighlight),
                  ListTile(
                    leading: const Icon(
                      Icons.directions_car_rounded,
                      color: AppColors.neonPurple,
                    ),
                    title: const Text(
                      'Driving Mode (Car UI)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Tampilan kontrol ekstra besar saat berkendara',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => DrivingModeScreen.show(context),
                  ),
                  const Divider(height: 1, color: AppColors.surfaceHighlight),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: AppThemeController.modeNotifier,
                    builder: (_, mode, _) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.dark_mode_rounded,
                                  color: AppColors.spotifyGreen,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Tema Tampilan',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final opt in const [
                                  (ThemeMode.light, 'Terang'),
                                  (ThemeMode.dark, 'Gelap'),
                                  (ThemeMode.system, 'Sistem'),
                                ])
                                  ChoiceChip(
                                    label: Text(
                                      opt.$2,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: mode == opt.$1
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: mode == opt.$1
                                            ? Colors.white
                                            : (Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? const Color(0xFFF3F4F6)
                                                : AppColors.textPrimary),
                                      ),
                                    ),
                                    selected: mode == opt.$1,
                                    onSelected: (_) =>
                                        AppThemeController.setMode(opt.$1),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
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
                                  color: Colors.white,
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
                      'MediaCenter & Hallsem Cinema',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Musik Offline, Direktori, TV & IPTV, dan Hallsem Cinema',
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

  Future<void> _showCrossfadePicker(
    BuildContext context,
    MusicProvider music,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.elevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        const options = [
          (0, 'Gapless Murni (Crossfade Mati)'),
          (3, 'Halus (3 detik)'),
          (5, 'Seimbang (5 detik)'),
          (8, 'Panjang (8 detik)'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crossfade & Gapless Playback',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                for (final opt in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      music.crossfadeSeconds == opt.$1
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: music.crossfadeSeconds == opt.$1
                          ? AppColors.spotifyGreen
                          : AppColors.textSecondary,
                    ),
                    title: Text(
                      opt.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () async {
                      await music.setCrossfadeSeconds(opt.$1);
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showOfflineStorageManager(
    BuildContext context,
    MusicProvider music,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: FutureBuilder<
                    ({
                      int totalBytes,
                      int fileCount,
                      List<
                          ({
                            String name,
                            String path,
                            int fileCount,
                            int totalBytes,
                          })> folders,
                    })>(
                  future: music.getOfflineStorageSummary(),
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return const SizedBox(
                        height: 180,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.spotifyGreen,
                          ),
                        ),
                      );
                    }
                    final data = snap.data!;
                    final totalMb =
                        (data.totalBytes / (1024 * 1024)).toStringAsFixed(1);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.storage_rounded,
                              color: AppColors.spotifyGreen,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Manajemen Musik Offline',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              '$totalMb MB',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.spotifyGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${data.fileCount} file audio offline di ${data.folders.length} folder',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: AppColors.spotifyGreen,
                          title: const Text(
                            'Mode Hemat Kuota (Auto-Cache YouTube)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: const Text(
                            'Simpan audio YouTube otomatis (maks. 500 MB) agar putar ulang tidak memakai paket data.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                          value: music.ytAutoCacheEnabled,
                          onChanged: (val) async {
                            await music.setYtAutoCacheEnabled(val);
                            if (ctx.mounted) setSheetState(() {});
                            if (mounted) setState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        if (data.folders.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text(
                                'Belum ada musik YouTube yang diunduh.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 280),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: data.folders.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final f = data.folders[i];
                                final mb = (f.totalBytes / (1024 * 1024))
                                    .toStringAsFixed(1);
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.folder_rounded,
                                    color: AppColors.spotifyGreen,
                                  ),
                                  title: Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text('${f.fileCount} lagu • $mb MB'),
                                  trailing: IconButton(
                                    tooltip: 'Hapus Folder',
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppColors.netflixRed,
                                    ),
                                    onPressed: () async {
                                      await music.deleteOfflineFolder(f.path);
                                      if (ctx.mounted) setSheetState(() {});
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        if (data.folders.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.netflixRed,
                                side: const BorderSide(
                                  color: AppColors.netflixRed,
                                ),
                              ),
                              onPressed: () async {
                                await music.clearAllYouTubeOfflineCache();
                                if (ctx.mounted) setSheetState(() {});
                                if (mounted) setState(() {});
                              },
                              icon: const Icon(Icons.delete_sweep_rounded),
                              label: const Text(
                                'Hapus Semua Cache Musik Offline',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
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
        style: TextStyle(
          color: AppColors.text(context),
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
        color: AppColors.card(context),
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
