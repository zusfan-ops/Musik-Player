import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'providers/finance_provider.dart';
import 'providers/music_provider.dart';
import 'providers/pos_provider.dart';
import 'providers/profile_jellyfin_provider.dart';
import 'screens/directories_screen.dart';
import 'screens/driving_mode_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jellyfin_movies_screen.dart';
import 'screens/keuangan_screen.dart';
import 'screens/newtube_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/profile_settings_screen.dart';
import 'services/update_checker_service.dart';
import 'theme/app_theme.dart';
import 'widgets/mini_player_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.musikm3u.player.channel.audio',
      androidNotificationChannelName: 'Pemutaran Musik M3U',
      androidNotificationIcon: 'drawable/ic_stat_music',
      androidNotificationOngoing: false,
      preloadArtwork: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    );
  } catch (_) {
    // Safe fallback if native audio background service is unavailable (e.g. tests)
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MusikM3uApp());
}

class MusikM3uApp extends StatelessWidget {
  final bool autoScanOnInit;

  const MusikM3uApp({
    super.key,
    this.autoScanOnInit = true,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              MusicProvider(autoScanOnInit: autoScanOnInit)..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProfileJellyfinProvider(
            autoConnectOnInit: autoScanOnInit,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => PosProvider()..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => FinanceProvider()..initialize(),
        ),
      ],
      child: MaterialApp(
        title: 'MediaCenter',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: AppBootstrapGate(autoCheckUpdates: autoScanOnInit),
      ),
    );
  }
}

/// Branded Splash Screen using `logo2.png` while library & settings initialize.
class AppBootstrapGate extends StatefulWidget {
  final bool autoCheckUpdates;

  const AppBootstrapGate({
    super.key,
    this.autoCheckUpdates = true,
  });

  @override
  State<AppBootstrapGate> createState() => _AppBootstrapGateState();
}

class _AppBootstrapGateState extends State<AppBootstrapGate> {
  bool _minimumSplashDone = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 950), () {
      if (mounted) {
        setState(() => _minimumSplashDone = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final musicReady =
        context.select<MusicProvider, bool>((p) => p.initialized);
    final profileReady =
        context.select<ProfileJellyfinProvider, bool>((p) => p.initialized);

    if (!musicReady || !profileReady || !_minimumSplashDone) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 132, borderRadius: 32, showGlow: true),
              const SizedBox(height: 24),
              const Text(
                'MEDIACENTER',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Offline Music • TV & IPTV • Hallsem Cinema',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 140,
                child: LinearProgressIndicator(
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: AppColors.surfaceHighlight,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.spotifyGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return MainNavigationShell(autoCheckUpdates: widget.autoCheckUpdates);
  }
}

class MainNavigationShell extends StatefulWidget {
  final bool autoCheckUpdates;

  const MainNavigationShell({
    super.key,
    this.autoCheckUpdates = true,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  final GlobalKey<NavigatorState> _shellNavKey = GlobalKey<NavigatorState>();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoCheckUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final music = context.read<MusicProvider>();
        if (!music.hasSeenOnboarding) {
          await OnboardingScreen.show(context);
        }
        if (mounted) {
          UpdateCheckerService.instance.checkAndShowUpdateDialog(context);
        }
      });
    }
  }

  void _switchTab(int index) {
    _shellNavKey.currentState?.popUntil((route) => route.isFirst);
    setState(() => _selectedIndex = index.clamp(0, 5));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(onNavigateTab: _switchTab),
      const DirectoriesScreen(),
      const PlaylistsScreen(),
      const NewTubeScreen(),
      JellyfinMoviesScreen(onOpenSettings: () => _switchTab(5)),
      ProfileSettingsScreen(onOpenMoviesTab: () => _switchTab(4)),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _shellNavKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Navigator(
              key: _shellNavKey,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => IndexedStack(
                  index: _selectedIndex,
                  children: pages,
                ),
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: MiniPlayerBar(),
            ),
          ],
        ),
        bottomNavigationBar: _ModernBottomNavBar(
          key: const Key('modern_bottom_nav'),
          selectedIndex: _selectedIndex,
          onSelected: _switchTab,
          onOpenMore: () => _showMoreMenu(context),
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withValues(alpha: 0.9),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(26)),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        AppLogo(size: 28, borderRadius: 8),
                        SizedBox(width: 10),
                        Text(
                          'Menu Lainnya',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _MoreMenuTile(
                      icon: Icons.movie_rounded,
                      color: AppColors.netflixRed,
                      title: 'Hallsem Cinema (Film)',
                      subtitle: 'Nonton & unduh film offline',
                      selected: _selectedIndex == 4,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _switchTab(4);
                      },
                    ),
                    const SizedBox(height: 8),
                    _MoreMenuTile(
                      icon: Icons.person_rounded,
                      color: AppColors.spotifyGreen,
                      title: 'Profil & Setting',
                      subtitle: 'Avatar, Hallsem Cinema & Info Developer',
                      selected: _selectedIndex == 5,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _switchTab(5);
                      },
                    ),
                    const SizedBox(height: 8),
                    _MoreMenuTile(
                      icon: Icons.point_of_sale_rounded,
                      color: AppColors.spotifyGreen,
                      title: 'Kasir & POS Usaha',
                      subtitle: 'Coffeeshop, Roastery, Retail, Nota & Laporan PDF',
                      selected: false,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        PosScreen.show(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    _MoreMenuTile(
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppColors.neonCyan,
                      title: 'Keuangan & Buku Kas',
                      subtitle: 'Catat belanja, pemasukan, dompet & laporan PDF',
                      selected: false,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        KeuanganScreen.show(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    _MoreMenuTile(
                      icon: Icons.directions_car_rounded,
                      color: AppColors.neonPurple,
                      title: 'Driving Mode (Car UI)',
                      subtitle: 'Tombol ekstra besar & aman saat berkendara',
                      selected: false,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        DrivingModeScreen.show(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    _MoreMenuTile(
                      icon: Icons.menu_book_rounded,
                      color: AppColors.neonCyan,
                      title: 'Panduan Penggunaan',
                      subtitle: 'Cara pakai musik lokal, TV, YouTube & Widget',
                      selected: false,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        OnboardingScreen.show(context);
                      },
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MoreMenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _MoreMenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : AppColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenMore;

  const _ModernBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onOpenMore,
  });

  static const List<({
    IconData icon,
    IconData selectedIcon,
    String label,
  })> _items = [
    (
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Beranda',
    ),
    (
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
      label: 'Folder',
    ),
    (
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv_rounded,
      label: 'TV',
    ),
    (
      icon: Icons.smart_display_outlined,
      selectedIcon: Icons.smart_display_rounded,
      label: 'YouTube',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isMoreActive = selectedIndex >= 4;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.darkNav.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 1.1,
                  ),
                ),
                child: Row(
                children: [
                  for (int i = 0; i < _items.length; i++)
                    Expanded(
                      child: _GlassNavButton(
                        icon: i == selectedIndex
                            ? _items[i].selectedIcon
                            : _items[i].icon,
                        label: _items[i].label,
                        selected: i == selectedIndex,
                        onTap: () => onSelected(i),
                      ),
                    ),
                  Expanded(
                    child: _GlassNavButton(
                      icon: isMoreActive
                          ? Icons.grid_view_rounded
                          : Icons.grid_view_outlined,
                      label: 'Lainnya',
                      selected: isMoreActive,
                      onTap: onOpenMore,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _GlassNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GlassNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? AppColors.spotifyGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.spotifyGreen.withValues(alpha: 0.32),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? Colors.white : Colors.white70,
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
