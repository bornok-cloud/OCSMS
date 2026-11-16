import 'package:flutter/material.dart';

/// Clean black and white monochrome palette.
class AppColors {
  static const cream = Color(0xFFFFFFFF); // Pure white page background
  static const beige = Color(0xFFF5F5F5); // Light grey surface
  static const beigeDark = Color(0xFFE0E0E0); // Medium grey divider / pressed surface
  static const darkBrown = Color(0xFF000000); // Pure black headings and actions
  static const brown = Color(0xFF333333); // Dark grey secondary
  static const brownDeep = Color(0xFF000000); // Deep black
  static const lightBrown = Color(0xFF666666); // Muted grey neutral
  static const accent = Color(0xFF000000); // Black signature accent
  static const accentDark = Color(0xFF000000); // Accessible accent text
  static const success = Color(0xFF000000); // Black/grey success
  static const warning = Color(0xFF333333); // Dark grey warning
  static const danger = Color(0xFF000000); // Black danger
  static const info = Color(0xFF666666); // Muted grey info
  static const cardWhite = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFF666666);
  static const border = Color(0x40000000); // Thin black outline (25% opacity black) for cards and small containers
}

/// Reusable elevation-style shadows for consistent cards/panels.
class AppShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
  static List<BoxShadow> lifted = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.1),
      blurRadius: 22,
      offset: const Offset(0, 8),
    ),
  ];
}

class AppTheme {
  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.darkBrown,
      primary: AppColors.darkBrown,
      secondary: AppColors.accent,
      surface: AppColors.cardWhite,
      error: AppColors.danger,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.cream,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,

      // ---- App bar ----
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.darkBrown,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        shadowColor: Color(0x1F000000),
        titleTextStyle: TextStyle(
          color: AppColors.darkBrown,
          fontWeight: FontWeight.w800,
          fontSize: 19,
        ),
        iconTheme: IconThemeData(color: AppColors.darkBrown),
      ),

      // ---- Cards / surfaces ----
      cardTheme: CardThemeData(
        color: AppColors.cardWhite,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.darkBrown,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.darkBrown,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.cardWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        showDragHandle: true,
      ),

      // ---- Buttons ----
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkBrown,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.darkBrown.withValues(
                alpha: 0.35,
              ),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                fontSize: 13.5,
              ),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.pressed)
                    ? Colors.white.withValues(alpha: 0.15)
                    : states.contains(WidgetState.hovered)
                    ? Colors.white.withValues(alpha: 0.08)
                    : null,
              ),
            ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.darkBrown,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            fontSize: 13.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkBrown,
          side: const BorderSide(color: AppColors.darkBrown, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            fontSize: 13.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.darkBrown,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.darkBrown,
          highlightColor: AppColors.beige,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.cardWhite,
          foregroundColor: AppColors.darkBrown,
          selectedBackgroundColor: AppColors.darkBrown,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.darkBrown,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // ---- Navigation ----
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.cardWhite,
        indicatorColor: AppColors.darkBrown.withValues(alpha: 0.15),
        elevation: 3,
        surfaceTintColor: Colors.transparent,
        height: 64,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.darkBrown
                : AppColors.textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.darkBrown
                : AppColors.textMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.darkBrown,
        indicatorColor: Colors.white.withValues(alpha: 0.2),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        selectedIconTheme: const IconThemeData(color: Colors.white),
        unselectedIconTheme: const IconThemeData(color: Colors.white70),
        selectedLabelTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: const TextStyle(color: Colors.white70),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.darkBrown,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: AppColors.darkBrown.withValues(alpha: 0.15),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.border,
      ),

      // ---- Inputs ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        hintStyle: TextStyle(
          color: AppColors.textMuted.withValues(alpha: 0.7),
          fontSize: 13.5,
        ),
        floatingLabelStyle: const TextStyle(
          color: AppColors.darkBrown,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
        prefixIconColor: AppColors.lightBrown,
        suffixIconColor: AppColors.lightBrown,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBrown, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBrown, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBrown, width: 1.8),
        ),
        errorStyle: const TextStyle(
          color: AppColors.darkBrown,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.darkBrown
              : Colors.transparent,
        ),
        side: const BorderSide(color: AppColors.lightBrown, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.darkBrown
              : AppColors.lightBrown,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.black
              : Colors.grey.shade300,
        ),
        thumbColor: WidgetStateProperty.resolveWith((states) => Colors.white),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.black
              : Colors.grey.shade400,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(2.0),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.darkBrown,
        thumbColor: AppColors.darkBrown,
        inactiveTrackColor: AppColors.beigeDark,
      ),

      // ---- Chips ----
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.beige,
        selectedColor: AppColors.darkBrown,
        disabledColor: AppColors.beige.withValues(alpha: 0.5),
        labelStyle: const TextStyle(
          color: AppColors.darkBrown,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),

      // ---- Lists / misc ----
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: AppColors.darkBrown,
        textColor: AppColors.darkBrown,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.lightBrown.withValues(alpha: 0.1),
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.darkBrown.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.cardWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Color(0x33000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkBrown,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.cardWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.darkBrown,
        linearTrackColor: AppColors.beige,
        circularTrackColor: AppColors.beige,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(AppColors.beige),
        headingTextStyle: const TextStyle(
          color: AppColors.darkBrown,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
        dataTextStyle: const TextStyle(
          color: AppColors.darkBrown,
          fontSize: 13.5,
        ),
        dividerThickness: 0.6,
      ),

      // ---- Type scale ----
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontWeight: FontWeight.w900,
          color: AppColors.darkBrown,
          letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w900,
          color: AppColors.darkBrown,
          letterSpacing: -0.3,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.darkBrown,
          letterSpacing: -0.2,
        ),
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.darkBrown,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.darkBrown,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.darkBrown,
        ),
        titleSmall: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.darkBrown,
        ),
        bodyLarge: TextStyle(color: AppColors.darkBrown, height: 1.45),
        bodyMedium: TextStyle(color: AppColors.darkBrown, height: 1.4),
        bodySmall: TextStyle(color: AppColors.textMuted, height: 1.3),
        labelLarge: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.darkBrown,
        ),
      ),
      dividerColor: AppColors.lightBrown.withValues(alpha: 0.25),
    );
  }
}

String peso(num amount) => '₱${amount.toStringAsFixed(2)}';

String formatDateTime(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final ampm = dt.hour < 12 ? 'AM' : 'PM';
  final minute = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $ampm';
}
