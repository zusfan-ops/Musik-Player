import 'package:flutter/material.dart';

class AppColors {
  // Warm Cream & Sand Editorial Canvas (inspired by reference design)
  static const Color background = Color(0xFFF6F2ED);
  static const Color surface = Color(0xFFEDE6DD);
  static const Color surfaceElevated = Color(0xFFFAF7F4);
  static const Color surfaceHighlight = Color(0xFFE2D8CC);
  static const Color darkNav = Color(0xFF141312);

  // Terracotta Coral, Deep Petrol Ink & Warm Ochre Accents
  static const Color spotifyGreen = Color(0xFFE8633A);
  static const Color neonCyan = Color(0xFF18222F);
  static const Color neonPurple = Color(0xFFE59A28);
  static const Color netflixRed = Color(0xFFD94A2B);

  // Text Hierarchy
  static const Color textPrimary = Color(0xFF1B1918);
  static const Color textSecondary = Color(0xFF6E675F);
  static const Color textMuted = Color(0xFF9C948B);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFE8633A), Color(0xFFD94A2B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient spotifyHeroGradient = LinearGradient(
    colors: [Color(0xFFE8633A), Color(0xFFD4522D)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppTheme {
  static ThemeData get darkTheme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.spotifyGreen,
        secondary: AppColors.neonCyan,
        tertiary: AppColors.neonPurple,
        surface: AppColors.surface,
        error: AppColors.netflixRed,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
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
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.spotifyGreen,
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkNav,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceElevated,
        modalBackgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.spotifyGreen,
        inactiveTrackColor: AppColors.textMuted.withValues(alpha: 0.28),
        thumbColor: AppColors.spotifyGreen,
        overlayColor: AppColors.spotifyGreen.withValues(alpha: 0.18),
        trackHeight: 4.0,
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
    this.borderRadius = 12,
    this.showGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: AppColors.spotifyGreen.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(size * 0.08),
      child: Image.asset(
        'assets/logo2.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
