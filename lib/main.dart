import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'providers/music_provider.dart';
import 'providers/profile_jellyfin_provider.dart';
import 'screens/directories_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jellyfin_movies_screen.dart';
import 'screens/newtube_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/playlists_screen.dart';
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
    );
  } catch (_) {
    // Safe fallback if native audio background service is unavailable (e.g. tests)
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
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
      ],
      child: MaterialApp(
        title: 'M3U Musik',
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
                'M3U MUSIK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Offline Music • Multi-M3U • Hallsem Cinema',
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
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.netflixRed,
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
        ),
      ),
    );
  }
}

class _ModernBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _ModernBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const List<({
    IconData icon,
    IconData selectedIcon,
    String label,
    Color accent,
  })> _items = [
    (
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Beranda',
      accent: AppColors.spotifyGreen,
    ),
    (
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
      label: 'Folder',
      accent: AppColors.spotifyGreen,
    ),
    (
      icon: Icons.queue_music_outlined,
      selectedIcon: Icons.queue_music_rounded,
      label: 'M3U',
      accent: AppColors.neonCyan,
    ),
    (
      icon: Icons.smart_display_outlined,
      selectedIcon: Icons.smart_display_rounded,
      label: 'YouTube',
      accent: AppColors.netflixRed,
    ),
    (
      icon: Icons.movie_outlined,
      selectedIcon: Icons.movie_rounded,
      label: 'Film',
      accent: AppColors.netflixRed,
    ),
    (
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Profil',
      accent: AppColors.spotifyGreen,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (i) {
            final item = _items[i];
            final selected = i == selectedIndex;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? item.accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected ? item.selectedIcon : item.icon,
                        size: 20,
                        color: selected ? item.accent : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          style: TextStyle(
                            color: selected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 10.5,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
