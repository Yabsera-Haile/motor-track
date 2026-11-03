import 'package:flutter/material.dart';

/// Colours from the design canvas. Status colours always come with a shape
/// or a label, never colour alone.
abstract final class Palette {
  static const ink = Color(0xFF111418);
  static const ink2 = Color(0xFF555C68);
  static const ink3 = Color(0xFF626A78);
  static const ground = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4E7EB);
  static const control = Color(0xFFD5D9DF);
  static const divider = Color(0xFFEEF0F3);

  static const ok = Color(0xFF13774B);
  static const okBg = Color(0xFFE6F4EC);
  static const warn = Color(0xFFB45309);
  static const warnBg = Color(0xFFFEF3E2);
  static const late = Color(0xFFF2A33A);
  static const lateLine = Color(0xFFE08A12);
  static const bad = Color(0xFFB42318);
  static const badBg = Color(0xFFFDECEA);
  static const missFill = Color(0xFFFBD5D1);
  static const missLine = Color(0xFFD92D20);
  static const rest = Color(0xFFE3E6EA);
  static const muteBg = Color(0xFFEEF0F3);
  static const blue = Color(0xFF2F54EB);
  static const switchOff = Color(0xFFC2C8D0);
}

const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.ink,
      primary: Palette.ink,
      onPrimary: Colors.white,
      surface: Palette.surface,
      onSurface: Palette.ink,
      error: Palette.bad,
    ),
    scaffoldBackgroundColor: Palette.ground,
  );
  final text = base.textTheme.apply(bodyColor: Palette.ink, displayColor: Palette.ink);

  final controlBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Palette.control),
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.ground,
      foregroundColor: Palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.ink),
    ),
    cardTheme: CardThemeData(
      color: Palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Palette.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: controlBorder,
      enabledBorder: controlBorder,
      focusedBorder: controlBorder.copyWith(borderSide: const BorderSide(color: Palette.ink, width: 2)),
      errorBorder: controlBorder.copyWith(borderSide: const BorderSide(color: Palette.bad)),
      labelStyle: const TextStyle(color: Palette.ink2),
      helperStyle: const TextStyle(color: Palette.ink2, fontSize: 13),
      helperMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.ink,
        minimumSize: const Size(48, 50),
        side: const BorderSide(color: Palette.control),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.ok : Palette.switchOff,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Palette.surface,
      selectedColor: Palette.ink,
      side: const BorderSide(color: Palette.control),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Palette.ink),
      secondaryLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
      checkmarkColor: Colors.white,
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.surface,
      indicatorColor: Palette.muteBg,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Palette.ink : Palette.ink2,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Palette.surface,
        foregroundColor: Palette.ink2,
        selectedBackgroundColor: Palette.ink,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: Palette.control),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 44),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Palette.divider, space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// The small uppercase label used above sections ("COLLECTED TODAY").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Palette.ink3),
  );
}

/// A number plate chip: "RD 907 F".
class PlateChip extends StatelessWidget {
  const PlateChip(this.plate, {super.key, this.small = false});
  final String plate;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    height: small ? 22 : 24,
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 7),
    decoration: BoxDecoration(
      color: Palette.surface,
      border: Border.all(color: Palette.ink, width: 1.5),
      borderRadius: BorderRadius.circular(6),
    ),
    // widthFactor 1: shrink to the text instead of filling the space given.
    child: Center(
      widthFactor: 1,
      child: Text(
        plate,
        style: TextStyle(fontSize: small ? 11 : 12, fontWeight: FontWeight.w700, letterSpacing: 0.7),
      ),
    ),
  );
}
