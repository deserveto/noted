import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? AppColors.darkBackground : AppColors.background;
    final surface = dark ? AppColors.darkCard : AppColors.card;
    final text = dark ? AppColors.darkText : AppColors.text;
    final muted = dark ? AppColors.darkMutedText : AppColors.mutedText;
    final border = dark ? AppColors.darkBorder : AppColors.border;
    final sage = dark ? AppColors.darkPrimary : AppColors.primaryDark;
    final soft = dark ? AppColors.darkSearchFill : AppColors.searchFill;
    final scheme = ColorScheme.fromSeed(
        seedColor: sage,
        brightness: brightness,
        primary: sage,
        onPrimary: dark ? bg : Colors.white,
        secondary: AppColors.secondary,
        onSecondary: AppColors.text,
        error: AppColors.error,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: muted,
        outline: border,
        outlineVariant: border,
        surfaceContainerHighest: soft);
    final base = ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: scheme,
        fontFamily: 'DM Sans');
    final tt = base.textTheme
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
            headlineLarge: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w600,
                height: 1.08,
                letterSpacing: -1,
                color: text),
            headlineMedium: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                height: 1.1,
                letterSpacing: -.8,
                color: text),
            titleLarge: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -.3,
                color: text),
            titleMedium: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: text),
            bodyLarge: TextStyle(fontSize: 15, height: 1.55, color: text),
            bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: text),
            bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
            labelLarge: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w500, color: text));
    OutlineInputBorder ib(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c, width: w));
    return base.copyWith(
        scaffoldBackgroundColor: bg,
        canvasColor: bg,
        dividerColor: border,
        textTheme: tt.apply(fontFamily: 'DM Sans'),
        appBarTheme: AppBarTheme(
            backgroundColor: bg,
            foregroundColor: text,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            titleTextStyle: tt.titleMedium?.copyWith(fontFamily: 'DM Sans')),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                backgroundColor: text,
                foregroundColor: bg,
                minimumSize: const Size(48, 48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w500))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
                foregroundColor: text,
                side: BorderSide(color: border),
                minimumSize: const Size(44, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)))),
        iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                foregroundColor: text,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)))),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: sage,
            foregroundColor: dark ? bg : Colors.white,
            elevation: 3,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18))),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: surface,
            hintStyle: TextStyle(color: muted, fontSize: 14),
            labelStyle: TextStyle(color: muted),
            prefixIconColor: muted,
            suffixIconColor: muted,
            border: ib(border),
            enabledBorder: ib(border),
            focusedBorder: ib(sage, 1.5),
            errorBorder: ib(AppColors.error),
            focusedErrorBorder: ib(AppColors.error, 1.5),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
        chipTheme: ChipThemeData(
            backgroundColor: surface,
            selectedColor: text,
            side: BorderSide(color: border),
            shape: const StadiumBorder(),
            labelStyle:
                TextStyle(fontFamily: 'DM Sans', color: muted, fontSize: 13)),
        navigationBarTheme: NavigationBarThemeData(
            height: 72,
            backgroundColor: bg,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            indicatorColor: AppColors.noteColorFor(brightness, 2),
            labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11,
                fontWeight: s.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: s.contains(WidgetState.selected) ? text : muted))),
        bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            showDragHandle: true,
            dragHandleColor: border,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
        dialogTheme: DialogThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
        textSelectionTheme: TextSelectionThemeData(cursorColor: sage, selectionHandleColor: sage, selectionColor: sage.withValues(alpha: .25)),
        snackBarTheme: SnackBarThemeData(backgroundColor: text, behavior: SnackBarBehavior.floating, contentTextStyle: TextStyle(color: bg, fontFamily: 'DM Sans'), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        progressIndicatorTheme: ProgressIndicatorThemeData(color: sage),
        switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.all(Colors.white), trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? sage : border), trackOutlineColor: WidgetStateProperty.all(Colors.transparent)));
  }
}
