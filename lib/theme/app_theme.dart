import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController {
  AppThemeController._();
  static const String _kThemeModeKey = 'app_theme_mode_v1';
  static final ValueNotifier<ThemeMode> modeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kThemeModeKey);
      if (saved == 'dark') {
        modeNotifier.value = ThemeMode.dark;
      } else if (saved == 'system') {
        modeNotifier.value = ThemeMode.system;
      } else {
        modeNotifier.value = ThemeMode.light;
      }
    } catch (_) {}
  }

  static Future<void> setMode(ThemeMode mode) async {
    modeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
      };
      await prefs.setString(_kThemeModeKey, val);
    } catch (_) {}
  }
}

class AppColors {
  // Calm Matte Warm Stone Palette (glare-free, readable, zero AI-slop gradients)
  static const Color background = Color(0xFFE9E4DC);
  static const Color surface = Color(0xFFDFD9CF);
  static const Color surfaceElevated = Color(0xFFF1EDE6);
  static const Color surfaceHighlight = Color(0xFFD2CBC0);
  static const Color darkNav = Color(0xFF17181A);

  // Muted Burnt Terracotta, Deep Slate Ink & Warm Amber Accents
  static const Color spotifyGreen = Color(0xFFC95633);
  static const Color neonCyan = Color(0xFF1E2936);
  static const Color neonPurple = Color(0xFFC28222);
  static const Color netflixRed = Color(0xFFBD3F2A);

  // Text Hierarchy
  static const Color textPrimary = Color(0xFF1A1918);
  static const Color textSecondary = Color(0xFF5D5750);
  static const Color textMuted = Color(0xFF847D74);

  // Dark Mode Palette
  static const Color darkBackground = Color(0xFF111317);
  static const Color darkSurface = Color(0xFF1A1D23);
  static const Color darkElevated = Color(0xFF232730);
  static const Color darkHighlight = Color(0xFF2E333E);
  static const Color darkTextPrimary = Color(0xFFF3F4F6);
  static const Color darkTextSecondary = Color(0xFFA1A7B3);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color bg(BuildContext context) =>
      isDark(context) ? darkBackground : background;

  static Color card(BuildContext context) =>
      isDark(context) ? darkSurface : surface;

  static Color elevated(BuildContext context) =>
      isDark(context) ? darkElevated : surfaceElevated;

  static Color highlight(BuildContext context) =>
      isDark(context) ? darkHighlight : surfaceHighlight;

  static Color text(BuildContext context) =>
      isDark(context) ? darkTextPrimary : textPrimary;

  static Color subtext(BuildContext context) =>
      isDark(context) ? darkTextSecondary : textSecondary;

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFC95633), Color(0xFFB84A29)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient spotifyHeroGradient = LinearGradient(
    colors: [Color(0xFF23272D), Color(0xFF1A1D22)],
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
        onPrimary: Colors.white,
        primaryContainer: AppColors.surfaceHighlight,
        onPrimaryContainer: AppColors.textPrimary,
        secondary: AppColors.neonCyan,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.surfaceHighlight,
        onSecondaryContainer: AppColors.textPrimary,
        tertiary: AppColors.neonPurple,
        onTertiary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textPrimary,
        error: AppColors.netflixRed,
        onError: Colors.white,
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
        checkmarkColor: Colors.white,
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
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

  static ThemeData get trueDarkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    const darkBg = Color(0xFF111317);
    const darkSurface = Color(0xFF1A1D23);
    const darkElevated = Color(0xFF232730);
    const darkHighlight = Color(0xFF2E333E);
    const darkText = Color(0xFFF3F4F6);
    const darkMuted = Color(0xFFA1A7B3);
    return base.copyWith(
      scaffoldBackgroundColor: darkBg,
      cardColor: darkSurface,
      canvasColor: darkSurface,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.spotifyGreen,
        onPrimary: Colors.white,
        primaryContainer: darkHighlight,
        onPrimaryContainer: darkText,
        secondary: AppColors.neonPurple,
        onSecondary: Colors.white,
        secondaryContainer: darkHighlight,
        onSecondaryContainer: darkText,
        tertiary: AppColors.neonPurple,
        onTertiary: Colors.white,
        surface: darkSurface,
        onSurface: darkText,
        onSurfaceVariant: darkText,
        error: AppColors.netflixRed,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: darkText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: darkText),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: darkElevated,
        selectedColor: AppColors.spotifyGreen,
        checkmarkColor: Colors.white,
        labelStyle: const TextStyle(
          color: darkText,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkElevated,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkElevated,
        modalBackgroundColor: darkElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.spotifyGreen,
        inactiveTrackColor: darkMuted.withValues(alpha: 0.28),
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
