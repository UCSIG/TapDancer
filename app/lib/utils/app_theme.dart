import 'package:material_ui/material_ui.dart';

class AppColor {
  // ── Backgrounds — flat, near-black with a faint cool tint ─────────────────
  static const Color backgroundPrimary = Color.fromARGB(255, 19, 21, 27);

  // ── Surfaces — solid, subtly elevated (no glassmorphism) ──────────────────
  static const Color surfacePrimary = Color.fromARGB(103, 23, 23, 23);
  static const Color surfaceSecondary = Color(0xFF1E2128);
  static const Color surfaceTertiary = Color(0xFF2A2E37);

  // ── Accent — a single, confident blue ─────────────────────────────────────
  static const Color primary = Color(0xFF5B8CFF);
  static const Color primaryDark = Color(0xFF3D6BF0);
  static const Color primaryLight = Color(0xFF89AAFF);
  static const Color secondary = primary;
  static const Color tertiary = primaryDark;

  static const Color success = Color(0xFF2BC56E);
  static const Color successDark = Color(0xFF1FA85C);
  static const Color successLight = Color(0xFF5BD894);
  static const Color warning = Color(0xFFF5A524);
  static const Color error = Color.fromARGB(255, 240, 70, 70);
  static const Color info = primary;

  /// Accent per click type, indexed Single / Double / Triple / Long. Used to
  /// color-code bindings in the config overview and editor.
  static const List<Color> clickType = [primary, success, warning, error];

  static const Color textPrimary = Color(0xFFF3F4F7);
  static const Color textSecondary = Color(0xFF9AA1AE);
  static const Color textTertiary = Color(0xFF565D6A);

  // Hairline borders (low-opacity white) — the modern dark-UI separator.
  static const Color border = Color.fromARGB(30, 255, 255, 255);
  static const double borderWidth = 1.5;
  static const Color borderActive = primary;

  static const Color iconColor = textPrimary;

  static const seedColor = primary;

  // Scaffold background (flat).
  static const bgColor = backgroundPrimary;

  // Text
  static const textColor = Color(0xFF3a3f49);

  // Buttons
  static const buttonFgColor = textPrimary;
  static const buttonBgColor = primaryDark;
  static const buttonTextColor = textPrimary;
  static const buttonIconColor = textPrimary;

  // Icon Buttons
  static const iconButtonColor = textPrimary;
  static const iconButtonBgColor = buttonBgColor;

  static const bodyColor = primary;

  // App Bar — blends seamlessly into the background.
  static const appBarBgColor = backgroundPrimary;
  static const appBarIconColor = textPrimary;
  static const appBarHeight = 50.0;
  static const popupMenuBgColor = surfaceSecondary;

  // Bottom Navigation Bar
  static const bottomNavigationBarBgColor = Color.fromARGB(85, 0, 0, 0);
  static const bottomNavigationBarSelectedItemColor = primary;
  static final bottomNavigationBarUnselectedItemColor = textTertiary;

  // Dropdown Menu
  static const dropdownMenuBgColor = popupMenuBgColor;
  static const dropdownMenuTextColor = textPrimary;

  // Containers
  static const containerBorderColors = primary;

  // Window Layout
  static const double windowAspectRation = 16.0 / 9.0;
  static const double windowWidth = 500;
  static const double windowHeightRegularWindows = windowWidth * windowAspectRation + 30;
}

class AppGradients {
  // Subtle, same-hue gradients (no rainbow blue→purple).
  static const LinearGradient primaryButton = LinearGradient(colors: [AppColor.primary, AppColor.primaryDark]);

  static const LinearGradient successButton = LinearGradient(colors: [AppColor.success, AppColor.successDark]);

  static const LinearGradient activeButton = LinearGradient(colors: [AppColor.primary, AppColor.primaryDark]);

  static const LinearGradient assignedButton = LinearGradient(colors: [AppColor.success, AppColor.successDark]);

  static const LinearGradient inactiveButton = LinearGradient(colors: [AppColor.surfaceTertiary, AppColor.surfaceSecondary]);

  static const LinearGradient headerText = LinearGradient(colors: [AppColor.primary, AppColor.primaryLight]);

  static final LinearGradient deviceProgressIndicator = LinearGradient(colors: [AppColor.primary.withValues(alpha: 0.1), AppColor.primary, AppColor.primary.withValues(alpha: 0.1)]);
}

class AppTextStyles {
  static const TextStyle headerLarge = TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColor.textPrimary, letterSpacing: -0.5);

  static const TextStyle headerMedium = TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColor.textPrimary, letterSpacing: -0.3);

  static const TextStyle headerSmall = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColor.textPrimary, letterSpacing: -0.2);

  static const TextStyle bodyLarge = TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColor.textPrimary);

  static const TextStyle bodyMedium = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColor.textPrimary);

  static const TextStyle bodySmall = TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColor.textPrimary);

  static const TextStyle caption = TextStyle(fontSize: 13, color: AppColor.textSecondary);

  static const TextStyle mono = TextStyle(fontSize: 12, color: AppColor.textSecondary, fontFamily: 'monospace');
}

class AppSizing {
  static const double paddingXSmall = 4.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 12.0;
  static const double paddingLarge = 16.0;
  static const double paddingXLarge = 20.0;
  static const double paddingXXLarge = 25.0;

  static const double radiusSmall = 6.0;
  static const double radiusMedium = 8.0;
  static const double radiusLarge = 12.0;
  static const double radiusXLarge = 16.0;
  static const double radiusXXLarge = 20.0;

  static const double iconSmall = 14.0;
  static const double iconMedium = 16.0;
  static const double iconLarge = 20.0;
  static const double iconXLarge = 32.0;

  static const double buttonHeight = 40.0;
}

class AppTheme {
  static ThemeData getAppTheme(BuildContext context) {
    final theme = Theme.of(context);
    return Theme.of(context).copyWith(
      // Base ThemeData.dark() uses Material 3's default *purple* seed, which
      // tints colorScheme.outline (used by text-field/dialog borders) purple.
      // Reseed from the app's blue accent and use neutral grey outlines.
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColor.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppColor.primary,
        surface: AppColor.surfacePrimary,
        outline: AppColor.textTertiary,
        outlineVariant: AppColor.border,
      ),
      // colorScheme.surface is intentionally translucent (layered cards), but
      // dialogs need a solid background or their text is unreadable over the
      // content behind them. Give them an opaque surface explicitly.
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColor.surfaceSecondary,
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColor.appBarBgColor,
        foregroundColor: AppColor.appBarIconColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColor.appBarIconColor),
        actionsIconTheme: IconThemeData(color: AppColor.appBarIconColor),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColor.bottomNavigationBarBgColor,
        selectedItemColor: AppColor.bottomNavigationBarSelectedItemColor,
        unselectedItemColor: AppColor.bottomNavigationBarUnselectedItemColor,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.2),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(theme.textTheme.titleMedium),
          foregroundColor: WidgetStatePropertyAll<Color>(AppColor.buttonFgColor),
          backgroundColor: WidgetStatePropertyAll<Color>(AppColor.buttonBgColor),
          iconColor: WidgetStatePropertyAll<Color>(AppColor.buttonIconColor),
          iconSize: WidgetStatePropertyAll<double>(25),
          visualDensity: VisualDensity(horizontal: -4, vertical: -1),
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizing.radiusLarge),
          )),
        ),
      ),
      scaffoldBackgroundColor: AppColor.bgColor,
    );
  }
}
