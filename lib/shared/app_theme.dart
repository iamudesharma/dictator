import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;

/// Match the external Cupertino controls to the app's external Material theme.
Widget auraCupertinoTheme(BuildContext context, Widget? child) {
  final colors = Theme.of(context).colorScheme;
  return cupertino.CupertinoTheme(
    data: cupertino.CupertinoThemeData(
      brightness: colors.brightness,
      primaryColor: colors.primary,
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

ThemeData auraTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF547D91),
    brightness: brightness,
    primary: dark ? const Color(0xFF9AC7D9) : const Color(0xFF28647A),
    surface: dark ? const Color(0xFF17191C) : const Color(0xFFF8F9FB),
  );
  final text = TextStyle(
    fontFamily: '.AppleSystemUIFont',
    color: scheme.onSurface,
  );
  final button = ButtonStyle(
    textStyle: WidgetStatePropertyAll(
      text.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
  );
  return ThemeData(
    platform: TargetPlatform.macOS,
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: '.AppleSystemUIFont',
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.compact,
    dividerColor: dark ? const Color(0xFF30343A) : const Color(0xFFE2E5E9),
    textTheme: TextTheme(
      displayLarge: text.copyWith(fontSize: 28, fontWeight: FontWeight.w600),
      displayMedium: text.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
      displaySmall: text.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      headlineLarge: text.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      headlineMedium: text.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      headlineSmall: text.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      titleLarge: text.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleMedium: text.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
      titleSmall: text.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
      bodyLarge: text.copyWith(fontSize: 13, height: 1.4),
      bodyMedium: text.copyWith(fontSize: 12, height: 1.4),
      bodySmall: text.copyWith(
        fontSize: 11,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: text.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelMedium: text.copyWith(fontSize: 11, fontWeight: FontWeight.w500),
      labelSmall: text.copyWith(fontSize: 10, fontWeight: FontWeight.w500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark ? const Color(0xFF202329) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: text.copyWith(fontSize: 12, color: scheme.onSurfaceVariant),
      hintStyle: text.copyWith(fontSize: 12, color: scheme.onSurfaceVariant),
      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 32),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .55),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      titleTextStyle: text.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      subtitleTextStyle: text.copyWith(
        fontSize: 11,
        color: scheme.onSurfaceVariant,
      ),
      iconColor: scheme.onSurfaceVariant,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      textColor: scheme.onSurface,
      collapsedTextColor: scheme.onSurface,
      iconColor: scheme.onSurfaceVariant,
      collapsedIconColor: scheme.onSurfaceVariant,
    ),
    textButtonTheme: TextButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button),
    filledButtonTheme: FilledButtonThemeData(style: button),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(iconSize: WidgetStatePropertyAll(17)),
    ),
    chipTheme: ChipThemeData(
      labelStyle: text.copyWith(fontSize: 11),
      side: BorderSide(color: scheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith((_) => null),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
    ),
  );
}
