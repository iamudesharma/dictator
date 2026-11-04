import 'package:flutter/material.dart';

ThemeData auraTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF697F97),
      brightness: brightness,
      primary: dark ? const Color(0xFFD2DFEC) : const Color(0xFF354C64),
      surface: dark ? const Color(0xFF171719) : const Color(0xFFF9F9FA));
  return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: '.AppleSystemUIFont',
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: dark ? const Color(0xFF303033) : const Color(0xFFDEDEE2),
      textTheme: Typography.material2021(platform: TargetPlatform.macOS)
          .black
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.outlineVariant))),
      switchTheme: SwitchThemeData(
          thumbIcon: WidgetStateProperty.resolveWith((_) => null)),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.inverseSurface,
          contentTextStyle: TextStyle(color: scheme.onInverseSurface)));
}
