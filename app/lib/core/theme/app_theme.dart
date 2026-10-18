import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// 앱 테마(Material3). 어두운 남색 배경 + 보라(인디고) 강조색이 기본이고, 같은 구성의 밝은 테마도 있다(docs/14 §7).
/// 색은 [AppColors] 토큰과 [AppPalette]만 쓴다. 어느 테마를 쓸지는 사용자 설정(`themeModeProvider`)이 정한다.
class AppTheme {
  const AppTheme._();

  static const double _cardRadius = 12;
  static const double _controlRadius = 10;
  static const double _buttonHeight = 48;

  /// 어두운 테마(P6부터의 기본 화면).
  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);

  /// 밝은 테마.
  static ThemeData get light => _build(Brightness.light, AppPalette.light);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textMuted,
      outline: palette.border,
      outlineVariant: palette.border,
      error: AppColors.danger,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_controlRadius));

    return base.copyWith(
      extensions: [palette],
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.surface,
      dividerColor: palette.border,
      dividerTheme: DividerThemeData(color: palette.border, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: _cardTheme(palette),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          minimumSize: const Size.fromHeight(_buttonHeight),
          shape: controlShape,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: palette.surface,
          foregroundColor: palette.textMuted,
          selectedBackgroundColor: AppColors.accent,
          selectedForegroundColor: AppColors.onAccent,
          side: BorderSide(color: palette.border),
          shape: controlShape,
        ),
      ),
      inputDecorationTheme: _inputTheme(palette),
    );
  }

  static CardThemeData _cardTheme(AppPalette palette) => CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
          side: BorderSide(color: palette.border),
        ),
      );

  static InputDecorationTheme _inputTheme(AppPalette palette) {
    OutlineInputBorder outline(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
          borderSide: BorderSide(color: color),
        );

    return InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      border: outline(palette.border),
      enabledBorder: outline(palette.border),
      focusedBorder: outline(AppColors.accent),
    );
  }
}
