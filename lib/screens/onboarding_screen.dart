import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const OnboardingScreen(),
      ),
    );
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_OnboardingSlide> _slides = [
    _OnboardingSlide(
      badge: 'LANGKAH 1 • MUSIK LOKAL',
      title: 'Putar Musik dari Folder HP',
      description:
          'Buka tab Direktori untuk memindai seluruh lagu di penyimpanan HP secara otomatis, atau ketuk "+ Tambah Folder" untuk memilih folder musik favorit Anda.\n\nFolder sistem seperti Ringtone, Alarms, dan Notifications otomatis disaring agar perpustakaan tetap rapi.',
      icon: Icons.folder_copy_rounded,
      accentColor: AppColors.spotifyGreen,
      tips: [
        'Ketuk lagu untuk langsung memutar dengan antrean otomatis.',
        'Gunakan ikon pencarian untuk menemukan lagu atau folder secara instan.',
      ],
    ),
    _OnboardingSlide(
      badge: 'LANGKAH 2 • PLAYLIST M3U',
      title: 'Import Playlist M3U & IPTV',
      description:
          'Masuk ke tab M3U lalu tempel URL playlist (.m3u / .m3u8) atau pilih file lokal dari perangkat Anda.\n\nLagu dari M3U dapat diunduh lewat tombol "Simpan Offline" agar tetap bisa diputar tanpa kuota internet.',
      icon: Icons.queue_music_rounded,
      accentColor: AppColors.neonCyan,
      tips: [
        'Saluran video/IPTV di dalam file M3U otomatis terdeteksi & diputar di pemutar video.',
        'Atur playlist aktif/nonaktif dengan mudah lewat tombol switch.',
      ],
    ),
    _OnboardingSlide(
      badge: 'LANGKAH 3 • HALLSEM CINEMA',
      title: 'Nonton Film di Tab Film',
      description:
          'Tab Film (Hallsem Cinema) sudah terintegrasi langsung tanpa perlu konfigurasi server atau API manual.\n\nCukup buka tab Film, pilih film atau serial yang tersedia, dan nikmati pemutaran video dengan kontrol penuh.',
      icon: Icons.movie_creation_rounded,
      accentColor: AppColors.netflixRed,
      tips: [
        'Jika daftar film belum muncul, ketuk tombol Sinkron di tab Film atau Profil.',
        'Progres tontonan tersimpan otomatis.',
      ],
    ),
    _OnboardingSlide(
      badge: 'LANGKAH 4 • KONTROL & WIDGET',
      title: 'Notifikasi, Widget & Play Bar',
      description:
          'Kontrol musik tetap tersedia di Notifikasi & Lockscreen saat layar mati. Anda juga bisa memasang Widget Layar Utama dalam 3 ukuran (2x1, 4x1, dan 4x2).\n\nAgar layar tidak tertutup, Play Bar di bawah akan hilang otomatis saat musik selesai — atau ketuk tombol (X) / geser ke samping untuk menyembunyikannya.',
      icon: Icons.widgets_rounded,
      accentColor: AppColors.spotifyGreen,
      tips: [
        'Tahan layar utama HP -> pilih Widget -> cari "MediaCenter".',
        'Panduan ini dapat dibuka kembali kapan saja di menu Profil & Setting.',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    await context.read<MusicProvider>().markOnboardingSeen();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentPage];
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 14, 8),
              child: Row(
                children: [
                  const AppLogo(size: 32, borderRadius: 9),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Panduan MediaCenter',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _finishOnboarding,
                    child: const Text(
                      'Lewati',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final item = _slides[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  item.accentColor.withValues(alpha: 0.28),
                                  AppColors.surface,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: item.accentColor.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: item.accentColor.withValues(alpha: 0.2),
                                  blurRadius: 28,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Icon(
                              item.icon,
                              size: 56,
                              color: item.accentColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: item.accentColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.badge,
                            style: TextStyle(
                              color: item.accentColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.description,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tips Cepat:',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final tip in item.tips)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: item.accentColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          tip,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12.5,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
              child: Row(
                children: [
                  Row(
                    children: List.generate(_slides.length, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.only(right: 6),
                        width: active ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? slide.accentColor
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: slide.accentColor,
                      foregroundColor: slide.accentColor == AppColors.netflixRed
                          ? Colors.white
                          : Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _nextPage,
                    icon: Icon(
                      isLast
                          ? Icons.rocket_launch_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isLast ? 'Mulai Sekarang' : 'Lanjut',
                      style: const TextStyle(fontWeight: FontWeight.w800),
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

class _OnboardingSlide {
  final String badge;
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final List<String> tips;

  const _OnboardingSlide({
    required this.badge,
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.tips,
  });
}
