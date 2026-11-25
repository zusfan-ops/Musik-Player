import 'package:flutter/material.dart';

class AppColors {
  // Deep Netflix Obsidian Canvas
  static const Color background = Color(0xFF090B10);
  static const Color surface = Color(0xFF121620);
  static const Color surfaceElevated = Color(0xFF191F2E);
  static const Color surfaceHighlight = Color(0xFF232B3E);

  // Brand Accents (Spotify Emerald + Netflix/Vinyl Crimson Red from logo2.png + Neon Accents)
  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonPurple = Color(0xFFA855F7);
  static const Color netflixRed = Color(0xFFE50914);

  // Text Hierarchy
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFE50914), Color(0xFF9333EA), Color(0xFF1DB954)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient spotifyHeroGradient = LinearGradient(
    colors: [Color(0xFF2B1219), Color(0xFF121624), Color(0xFF090B10)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppTheme {
  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.spotifyGreen,
        secondary: AppColors.neonCyan,
        tertiary: AppColors.neonPurple,
        surface: AppColors.surface,
        error: AppColors.netflixRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.spotifyGreen,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
        thumbColor: Colors.white,
        overlayColor: AppColors.spotifyGreen.withValues(alpha: 0.2),
        trackHeight: 3.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
    );
  }
}

/// Reusable Logo Widget rendering `logo2.png` on a crisp contrast badge so both the red vinyl and black note shine.
class AppLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool showGlow;

  const AppLogo({
    super.key,
    this.size = 44,
    double? borderRadius,
    this.showGlow = false,
  }) : borderRadius = borderRadius ?? (size * 0.24);

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (size * dpr).round().clamp(64, 1024);

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: AppColors.netflixRed.withValues(alpha: 0.38),
                  blurRadius: size * 0.35,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: AppColors.spotifyGreen.withValues(alpha: 0.18),
                  blurRadius: size * 0.45,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius * 0.8),
        child: Image.asset(
          'assets/logo2.png',
          width: size,
          height: size,
          cacheWidth: decodeWidth,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: Icon(
              Icons.album_rounded,
              color: AppColors.netflixRed,
              size: size * 0.65,
            ),
          ),
        ),
      ),
    );
  }
}
