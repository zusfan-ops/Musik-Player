import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/music_provider.dart';
import 'providers/profile_jellyfin_provider.dart';
import 'screens/directories_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jellyfin_movies_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/profile_settings_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/mini_player_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        home: const AppBootstrapGate(),
      ),
    );
  }
}

/// Branded Splash Screen using `logo2.png` while library & settings initialize.
class AppBootstrapGate extends StatefulWidget {
  const AppBootstrapGate({super.key});

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
                'Offline Music • Multi-M3U • Jellyfin Cinema',
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
    return const MainNavigationShell();
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _selectedIndex = 0;

  void _switchTab(int index) {
    setState(() => _selectedIndex = index.clamp(0, 4));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(onNavigateTab: _switchTab),
      const DirectoriesScreen(),
      const PlaylistsScreen(),
      JellyfinMoviesScreen(onOpenSettings: () => _switchTab(4)),
      ProfileSettingsScreen(onOpenMoviesTab: () => _switchTab(3)),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayerBar(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        child: NavigationBar(
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          backgroundColor: AppColors.background,
          indicatorColor: AppColors.spotifyGreen.withValues(alpha: 0.18),
          selectedIndex: _selectedIndex,
          onDestinationSelected: _switchTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(
                Icons.home_filled,
                color: AppColors.spotifyGreen,
              ),
              label: 'Beranda',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(
                Icons.folder_rounded,
                color: AppColors.spotifyGreen,
              ),
              label: 'Direktori',
            ),
            NavigationDestination(
              icon: Icon(Icons.queue_music_outlined),
              selectedIcon: Icon(
                Icons.queue_music_rounded,
                color: AppColors.spotifyGreen,
              ),
              label: 'M3U',
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              selectedIcon: Icon(
                Icons.movie_rounded,
                color: AppColors.netflixRed,
              ),
              label: 'Film',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(
                Icons.person_rounded,
                color: AppColors.spotifyGreen,
              ),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}
