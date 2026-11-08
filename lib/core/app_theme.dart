import 'package:flutter/material.dart';

/// The app's palette. Values follow the supplied Figma mockups.
@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.chip,
    required this.chipForeground,
    required this.chipBorder,
    required this.chipMuted,
    required this.inputFill,
    required this.inputBorder,
    required this.assistantBubble,
    required this.userBubble,
    required this.composerBorder,
    required this.nav,
    required this.navForeground,
    required this.navMuted,
    required this.navActive,
    required this.navActiveFill,
    required this.navBorder,
    required this.headerBar,
    required this.providerActive,
    required this.providerActiveForeground,
    required this.providerInactive,
    required this.providerInactiveForeground,
    required this.providerInactiveBorder,
    required this.toolCard,
    required this.danger,
    required this.settingsPanel,
    required this.settingsRow,
    required this.divider,
    required this.shadow,
    required this.toggleBackground,
    required this.toggleForeground,
    required this.checkBackground,
    required this.checkForeground,
    required this.mediaOverlay,
  });

  final Color background;
  final Color surface;
  final Color card;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color chip;
  final Color chipForeground;
  final Color chipBorder;
  final Color chipMuted;
  final Color inputFill;
  final Color inputBorder;
  final Color assistantBubble;
  final Color userBubble;
  final Color composerBorder;
  final Color nav;
  final Color navForeground;
  final Color navMuted;
  final Color navActive;
  final Color navActiveFill;
  final Color navBorder;
  final Color headerBar;
  final Color providerActive;
  final Color providerActiveForeground;
  final Color providerInactive;
  final Color providerInactiveForeground;
  final Color providerInactiveBorder;
  final Color toolCard;
  final Color danger;
  final Color settingsPanel;
  final Color settingsRow;
  final Color divider;
  final Color shadow;
  final Color toggleBackground;
  final Color toggleForeground;
  final Color checkBackground;
  final Color checkForeground;
  final Color mediaOverlay;

  static const light = AppPalette(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F7F7),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0x14000000),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF979797),
    textTertiary: Color(0xFF656565),
    chip: Color(0xFFC4C4C4),
    chipForeground: Color(0xFF000000),
    chipBorder: Color(0xFFDDDDDD),
    chipMuted: Color(0xFF9C8E8E),
    inputFill: Color(0xFFEDEDED),
    inputBorder: Color(0xFFBBBBBB),
    assistantBubble: Color(0xFFFAFAFA),
    userBubble: Color(0xFFE8E8E8),
    composerBorder: Color(0xFF171717),
    nav: Color(0xFFF4F4F4),
    navForeground: Color(0xFF000000),
    navMuted: Color(0xFF7A7A7A),
    navActive: Color(0xFF000000),
    navActiveFill: Color(0xFFFFFFFF),
    navBorder: Color(0x80000000),
    headerBar: Color(0xCCFFFFFF),
    providerActive: Color(0xFF000000),
    providerActiveForeground: Color(0xFFFFFFFF),
    providerInactive: Color(0xFFFFFFFF),
    providerInactiveForeground: Color(0xFF9C8E8E),
    providerInactiveBorder: Color(0xFFDDDDDD),
    toolCard: Color(0xFFE4E4E4),
    danger: Color(0xFFDB0000),
    settingsPanel: Color(0xFFF7F7F7),
    settingsRow: Color(0xFFFFFFFF),
    divider: Color(0x14000000),
    shadow: Color(0x1A000000),
    toggleBackground: Color(0xFFFFFFFF),
    toggleForeground: Color(0xFF1C1B1F),
    checkBackground: Color(0xFF000000),
    checkForeground: Color(0xFFFFFFFF),
    mediaOverlay: Color(0x99000000),
  );

  static const dark = AppPalette(
    background: Color(0xFF1A1A1A),
    surface: Color(0xFF202020),
    card: Color(0xFF1E1E1E),
    cardBorder: Color(0xFF484848),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF979797),
    textTertiary: Color(0xFFC3C2C2),
    chip: Color(0xFF454545),
    chipForeground: Color(0xFFFFFFFF),
    chipBorder: Color(0xFF464646),
    chipMuted: Color(0xFFE6E6E6),
    inputFill: Color(0xFF1E1E1E),
    inputBorder: Color(0xFF5B5B5B),
    assistantBubble: Color(0xFF242424),
    userBubble: Color(0xFF333333),
    composerBorder: Color(0xFFBDBDBD),
    nav: Color(0xFF242424),
    navForeground: Color(0xFFFFFFFF),
    navMuted: Color(0xFFB4B4B4),
    navActive: Color(0xFFFFFFFF),
    navActiveFill: Color(0x1AFFFFFF),
    navBorder: Color(0xFF7A7A7A),
    headerBar: Color(0xFF1A1A1A),
    providerActive: Color(0xFFFFFFFF),
    providerActiveForeground: Color(0xFF000000),
    providerInactive: Color(0xFF1E1E1E),
    providerInactiveForeground: Color(0xFFE6E6E6),
    providerInactiveBorder: Color(0xFF464646),
    toolCard: Color(0xFF303030),
    danger: Color(0xFFFF4D4D),
    settingsPanel: Color(0xFF1E1E1E),
    settingsRow: Color(0xFF2A2A2A),
    divider: Color(0x1AFFFFFF),
    shadow: Color(0x33000000),
    toggleBackground: Color(0xFF323232),
    toggleForeground: Color(0xFFFFFFFF),
    checkBackground: Color(0xFFFFFFFF),
    checkForeground: Color(0xFF000000),
    mediaOverlay: Color(0xCC000000),
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

class AppTypography {
  const AppTypography._();

  static const brand = TextStyle(
    fontFamily: 'Inika',
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: -0.2,
  );

  static const screenTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.3,
  );

  static const description = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w300,
    height: 1.3,
  );

  static const cardTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const cardSubtitle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const chip = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.1,
  );

  static const settingsLabel = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w300,
    height: 1.2,
    letterSpacing: -0.3,
  );

  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w300,
    height: 1.4,
  );

  static const chatMeta = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w300,
    height: 1.25,
  );
}

ThemeData buildAppTheme({
  required Brightness brightness,
  required bool useInter,
}) {
  final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final fontFamily = useInter ? 'Inter' : null;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.textPrimary,
    onPrimary: p.background,
    secondary: p.textSecondary,
    onSecondary: p.background,
    error: p.danger,
    onError: Colors.white,
    surface: p.background,
    onSurface: p.textPrimary,
    surfaceContainerHighest: p.surface,
    outline: p.cardBorder,
  );

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: p.background,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: fontFamily,
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    ),
    iconTheme: IconThemeData(color: p.textPrimary),
    splashFactory: InkSparkle.splashFactory,
    dividerColor: p.divider,
    canvasColor: p.background,
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.background,
      modalBackgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xFFEAEAEA)
          : const Color(0xFF161616),
      contentTextStyle: TextStyle(
        color: brightness == Brightness.dark
            ? const Color(0xFF161616)
            : Colors.white,
        fontFamily: fontFamily,
        fontWeight: FontWeight.w400,
        fontSize: 14,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      hintStyle: TextStyle(
        color: p.textSecondary,
        fontWeight: FontWeight.w400,
        fontSize: 14,
      ),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.textPrimary,
      selectionColor: p.textPrimary.withValues(alpha: 0.18),
      selectionHandleColor: p.textPrimary,
    ),
  );
}

/// Responsive horizontal page inset derived from the 430 px reference frame.
double pageInset(double width) {
  return (width * 0.109).clamp(20.0, 47.0);
}

/// Asymmetric content insets from the reference frame (left 47, right 15).
EdgeInsets pageInsets(double width) {
  return EdgeInsets.fromLTRB(
    pageInset(width),
    0,
    (width * 0.035).clamp(12.0, 15.0),
    0,
  );
}
