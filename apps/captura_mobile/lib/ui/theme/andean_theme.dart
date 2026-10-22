import 'package:flutter/material.dart';

/// Andean Architectural Reserve Design Tokens
/// Source: stitch_roomforge_client_app_ux_ui/andean_architectural_reserve/DESIGN.md
class AndeanColors {
  const AndeanColors._();

  // Brand & Accents
  static const primary = Color(0xFF032521); // #032521
  static const primaryBrand = Color(0xFF1B3B36); // #1B3B36 Deep Forest Green
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF1B3B36);
  static const onPrimaryContainer = Color(0xFF84A59E);
  static const inversePrimary = Color(0xFFABCEC6);

  static const secondary = Color(0xFF38675D); // #38675D Subtle Sage Green
  static const secondaryAccent = Color(0xFF4E7D73);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFBBEDE0);
  static const onSecondaryContainer = Color(0xFF3E6D63);

  static const tertiary = Color(0xFF00261E);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFF003E33);
  static const onTertiaryContainer = Color(0xFF67AC99);

  // Surfaces & Canvas (Archival Linen / Limestone)
  static const surface = Color(0xFFF2FCF8);
  static const surfaceBright = Color(0xFFF2FCF8);
  static const surfaceDim = Color(0xFFD2DCD9);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFECF6F2);
  static const surfaceContainer = Color(0xFFE6F0EC);
  static const surfaceContainerHigh = Color(0xFFE0EAE7);
  static const surfaceContainerHighest = Color(0xFFDBE5E1);

  // Text & Foregrounds
  static const onSurface = Color(0xFF141D1B);
  static const onSurfaceVariant = Color(0xFF414846);
  static const slateGraphite = Color(0xFF1A2321);
  static const mutedMineral = Color(0xFF5E6D68);
  static const inverseSurface = Color(0xFF293230);
  static const inverseOnSurface = Color(0xFFE9F3EF);

  // Outlines & Dividers
  static const outline = Color(0xFF717976);
  static const outlineVariant = Color(0xFFC1C8C5);
  static const surfaceTint = Color(0xFF44645F);
  static const border = Color(0xFFE3E7E2);
  static const divider = Color(0xFFE5EAE6);

  // Fixed Tokens
  static const primaryFixed = Color(0xFFC7EAE2);
  static const primaryFixedDim = Color(0xFFABCEC6);
  static const onPrimaryFixed = Color(0xFF00201C);
  static const onPrimaryFixedVariant = Color(0xFF2D4C47);
  static const secondaryFixed = Color(0xFFBBEDE0);
  static const secondaryFixedDim = Color(0xFF9FD0C5);
  static const onSecondaryFixed = Color(0xFF00201B);
  static const onSecondaryFixedVariant = Color(0xFF1E4E46);
  static const tertiaryFixed = Color(0xFFAAF1DC);
  static const tertiaryFixedDim = Color(0xFF8ED4C0);
  static const onTertiaryFixed = Color(0xFF002019);
  static const onTertiaryFixedVariant = Color(0xFF005143);

  // Semantic & Operational States
  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
  static const criticalText = Color(0xFF991B1B);
  static const criticalBg = Color(0xFFFEE2E2);

  static const warningText = Color(0xFFB45309);
  static const warningBg = Color(0xFFFEF3C7);

  static const successText = Color(0xFF166534);
  static const successBg = Color(0xFFDCFCE7);

  static const infoText = Color(0xFF1E40AF);
  static const infoBg = Color(0xFFDBEAFE);

  static const demoBadgeText = Color(0xFF6B21A8);
  static const demoBadgeBg = Color(0xFFF3E8FF);
}

/// Typographic scale according to Andean Architectural Reserve DESIGN.md
class AndeanTypography {
  const AndeanTypography._();

  static const fontFamilySerif = 'Newsreader';
  static const fontFamilySans = 'Plus Jakarta Sans';
  static const serifFallbacks = ['Georgia', 'serif'];
  static const sansFallbacks = ['Roboto', 'Arial', 'sans-serif'];

  // Headlines (Modern Editorial Serif)
  static const headlineXl = TextStyle(
    fontFamily: fontFamilySerif,
    fontFamilyFallback: serifFallbacks,
    fontSize: 36,
    height: 44 / 36,
    letterSpacing: -0.72,
    fontWeight: FontWeight.w500,
    color: AndeanColors.onSurface,
  );

  static const headlineLg = TextStyle(
    fontFamily: fontFamilySerif,
    fontFamilyFallback: serifFallbacks,
    fontSize: 28,
    height: 36 / 28,
    letterSpacing: -0.28,
    fontWeight: FontWeight.w500,
    color: AndeanColors.onSurface,
  );

  static const headlineMd = TextStyle(
    fontFamily: fontFamilySerif,
    fontFamilyFallback: serifFallbacks,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    color: AndeanColors.onSurface,
  );

  static const headlineSm = TextStyle(
    fontFamily: fontFamilySerif,
    fontFamilyFallback: serifFallbacks,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    color: AndeanColors.onSurface,
  );

  // Body (Plus Jakarta Sans)
  static const bodyLg = TextStyle(
    fontFamily: fontFamilySans,
    fontFamilyFallback: sansFallbacks,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: AndeanColors.onSurface,
  );

  static const bodyMd = TextStyle(
    fontFamily: fontFamilySans,
    fontFamilyFallback: sansFallbacks,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: AndeanColors.onSurface,
  );

  static const bodySm = TextStyle(
    fontFamily: fontFamilySans,
    fontFamilyFallback: sansFallbacks,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    color: AndeanColors.onSurfaceVariant,
  );

  // Labels
  static const labelLg = TextStyle(
    fontFamily: fontFamilySans,
    fontFamilyFallback: sansFallbacks,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0.14,
    fontWeight: FontWeight.w600,
    color: AndeanColors.onSurface,
  );

  static const labelMd = TextStyle(
    fontFamily: fontFamilySans,
    fontFamilyFallback: sansFallbacks,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.24,
    fontWeight: FontWeight.w600,
    color: AndeanColors.onSurface,
  );

  static const labelSm = TextStyle(
    fontFamily: fontFamilySans,
    fontFamilyFallback: sansFallbacks,
    fontSize: 11,
    height: 14 / 11,
    letterSpacing: 0.44,
    fontWeight: FontWeight.w700,
    color: AndeanColors.onSurfaceVariant,
  );

  static const monoData = TextStyle(
    fontFamily: fontFamilySans,
    fontFamilyFallback: sansFallbacks,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: -0.12,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AndeanColors.onSurface,
  );
}

/// Complete Andean Architectural Reserve ThemeData
ThemeData andeanTheme() {
  const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AndeanColors.primary,
    onPrimary: AndeanColors.onPrimary,
    primaryContainer: AndeanColors.primaryContainer,
    onPrimaryContainer: AndeanColors.onPrimaryContainer,
    inversePrimary: AndeanColors.inversePrimary,
    secondary: AndeanColors.secondary,
    onSecondary: AndeanColors.onSecondary,
    secondaryContainer: AndeanColors.secondaryContainer,
    onSecondaryContainer: AndeanColors.onSecondaryContainer,
    tertiary: AndeanColors.tertiary,
    onTertiary: AndeanColors.onTertiary,
    tertiaryContainer: AndeanColors.tertiaryContainer,
    onTertiaryContainer: AndeanColors.onTertiaryContainer,
    error: AndeanColors.error,
    onError: AndeanColors.onError,
    errorContainer: AndeanColors.errorContainer,
    onErrorContainer: AndeanColors.onErrorContainer,
    surface: AndeanColors.surface,
    onSurface: AndeanColors.onSurface,
    onSurfaceVariant: AndeanColors.onSurfaceVariant,
    outline: AndeanColors.outline,
    outlineVariant: AndeanColors.outlineVariant,
    shadow: Color.fromRGBO(27, 59, 54, 0.06),
    surfaceTint: AndeanColors.surfaceTint,
    inverseSurface: AndeanColors.inverseSurface,
    onInverseSurface: AndeanColors.inverseOnSurface,
    surfaceContainerLowest: AndeanColors.surfaceContainerLowest,
    surfaceContainerLow: AndeanColors.surfaceContainerLow,
    surfaceContainer: AndeanColors.surfaceContainer,
    surfaceContainerHigh: AndeanColors.surfaceContainerHigh,
    surfaceContainerHighest: AndeanColors.surfaceContainerHighest,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AndeanColors.surface,
    textTheme: const TextTheme(
      headlineLarge: AndeanTypography.headlineLg,
      headlineMedium: AndeanTypography.headlineMd,
      headlineSmall: AndeanTypography.headlineSm,
      titleLarge: AndeanTypography.headlineSm,
      titleMedium: AndeanTypography.labelLg,
      titleSmall: AndeanTypography.labelMd,
      bodyLarge: AndeanTypography.bodyLg,
      bodyMedium: AndeanTypography.bodyMd,
      bodySmall: AndeanTypography.bodySm,
      labelLarge: AndeanTypography.labelLg,
      labelMedium: AndeanTypography.labelMd,
      labelSmall: AndeanTypography.labelSm,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AndeanColors.surface,
      foregroundColor: AndeanColors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: AndeanTypography.headlineSm,
    ),
    cardTheme: CardThemeData(
      color: AndeanColors.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AndeanColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AndeanColors.primaryContainer,
        foregroundColor: AndeanColors.onPrimary,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AndeanTypography.labelLg,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AndeanColors.primaryContainer,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(
          color: AndeanColors.primaryContainer,
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AndeanTypography.labelLg,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AndeanColors.secondary,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AndeanTypography.labelMd,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AndeanColors.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AndeanColors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AndeanColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AndeanColors.secondary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AndeanColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AndeanColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: AndeanTypography.bodyMd.copyWith(
        color: AndeanColors.onSurfaceVariant,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AndeanColors.surface,
      indicatorColor: AndeanColors.secondaryFixed,
      elevation: 0,
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(
            color: AndeanColors.primaryContainer,
            size: 24,
          );
        }
        return const IconThemeData(color: AndeanColors.mutedMineral, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AndeanTypography.labelSm.copyWith(
            color: AndeanColors.primaryContainer,
            fontWeight: FontWeight.bold,
          );
        }
        return AndeanTypography.labelSm.copyWith(
          color: AndeanColors.mutedMineral,
        );
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AndeanColors.primaryContainer;
          }
          return AndeanColors.surfaceContainerHigh;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AndeanColors.onPrimary;
          }
          return AndeanColors.onSurfaceVariant;
        }),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AndeanColors.surfaceContainer,
      labelStyle: AndeanTypography.labelSm,
      shape: StadiumBorder(
        side: BorderSide(color: AndeanColors.border, width: 1),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AndeanColors.surfaceContainerLowest,
      modalBackgroundColor: AndeanColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
