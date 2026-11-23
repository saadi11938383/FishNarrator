import 'package:flutter/material.dart';

class StudioColors {
  static const Color bg = Color(0xFFF4F6F1);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color subtle = Color(0xFFEDF0E9);
  static const Color line = Color(0xFFDBE1D8);
  static const Color ink = Color(0xFF17251E);
  static const Color muted = Color(0xFF59695E);
  static const Color lime = Color(0xFFC0F586);
  static const Color limeBorder = Color(0xFFA3DC6B);
  static const Color limeInk = Color(0xFF19321C);
  static const Color dark = Color(0xFF172B22);
  static const Color monitorStart = Color(0xFF15241E);
  static const Color monitorMid = Color(0xFF1C3328);
  static const Color monitorEnd = Color(0xFF203B2D);
  static const Color monitorBorder = Color(0xFF263C30);
  static const Color forest = Color(0xFF48683D);
  static const Color forestAccent = Color(0xFF578348);
  static const Color tileBg = Color(0xFFEDF3E8);
  static const Color freeBg = Color(0xFFEEF8E4);
  static const Color freeInk = Color(0xFF416835);
  static const Color dotOk = Color(0xFF83BF60);
  static const Color dotWarn = Color(0xFFB77C25);
  static const Color errorBg = Color(0xFFFBF2E8);
  static const Color errorBorder = Color(0xFFE2CFBD);
  static const Color errorInk = Color(0xFFA1452D);
}

ThemeData buildStudioTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: StudioColors.forest,
      brightness: Brightness.light,
      surface: StudioColors.paper,
    ),
    scaffoldBackgroundColor: StudioColors.bg,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFFCFDFB),
      foregroundColor: StudioColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: StudioColors.line)),
    ),
    cardTheme: CardThemeData(
      color: StudioColors.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: StudioColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFCFDFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCFD8CC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCFD8CC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: StudioColors.forestAccent, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Color(0xFF758176), fontSize: 13),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFFFCFDFB),
      indicatorColor: const Color(0xFFE8EEE4),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? const Color(0xFF263C2B) : StudioColors.muted,
        );
      }),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: StudioColors.forestAccent,
      thumbColor: StudioColors.forest,
      inactiveTrackColor: StudioColors.line,
    ),
    dividerTheme: const DividerThemeData(color: StudioColors.line, thickness: 1),
  );
}
