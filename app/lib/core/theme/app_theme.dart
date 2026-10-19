import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// 앱 테마(Material3). 어두운 남색 배경 + 보라(인디고) 강조색이 기본이고, 같은 구성의 밝은 테마도 있다(docs/14 §7).
/// 색은 [AppColors] 토큰과 [AppPalette]만 쓴다. 어느 테마를 쓸지는 사용자 설정(`themeModeProvider`)이 정한다.
class AppTheme {
  const AppTheme._();

  static const double _cardRadius = 12;

  // 웹 대시보드 느낌(F1Laps 참고)의 촘촘한 컨트롤 치수 — Material 3 기본(알약·48px·가로 꽉 채움)을 쓰지 않는다.
  static const double _controlRadius = 6;
  static const double _menuRadius = 8;
  static const double _buttonHeight = 36;
  static const double _buttonMinWidth = 64;
  static const double _buttonPaddingX = 14;
  static const double _textButtonHeight = 32;
  static const double _textButtonPaddingX = 8;
  static const double _controlFontSize = 14;
  static const double _menuElevation = 8;
  static const double _menuPaddingY = 4;
  static const double _inputPaddingX = 12;
  static const double _inputPaddingY = 10;
  static const double _selectedSegmentAlpha = 0.14;
  static const double _disabledAlpha = 0.4;

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
      error: palette.danger,
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
          minimumSize: const Size(_buttonMinWidth, _buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: _buttonPaddingX),
          textStyle: _controlTextStyle,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          disabledForegroundColor: palette.textMuted.withValues(alpha: _disabledAlpha),
          minimumSize: const Size(_buttonMinWidth, _buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: _buttonPaddingX),
          textStyle: _controlTextStyle,
          side: BorderSide(color: palette.border),
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.link,
          minimumSize: const Size(0, _textButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: _textButtonPaddingX),
          textStyle: _controlTextStyle,
          shape: controlShape,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: palette.surface,
          foregroundColor: palette.textPrimary,
          selectedBackgroundColor: AppColors.accent.withValues(alpha: _selectedSegmentAlpha),
          selectedForegroundColor: palette.link,
          side: BorderSide(color: palette.border),
          textStyle: _controlTextStyle,
          minimumSize: const Size(0, _buttonHeight),
          shape: controlShape,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: _menuElevation,
        position: PopupMenuPosition.under,
        menuPadding: const EdgeInsets.symmetric(vertical: _menuPaddingY),
        textStyle: TextStyle(fontSize: _controlFontSize, color: palette.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_menuRadius),
          side: BorderSide(color: palette.border),
        ),
      ),
      menuTheme: MenuThemeData(style: _menuStyle(palette)),
      dropdownMenuTheme: DropdownMenuThemeData(menuStyle: _menuStyle(palette)),
      inputDecorationTheme: _inputTheme(palette),
    );
  }

  static const TextStyle _controlTextStyle = TextStyle(fontSize: _controlFontSize, fontWeight: FontWeight.w600);

  static MenuStyle _menuStyle(AppPalette palette) => MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(_menuElevation),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: _menuPaddingY)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_menuRadius),
          side: BorderSide(color: palette.border),
        )),
      );

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
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: _inputPaddingX, vertical: _inputPaddingY),
      fillColor: palette.surface,
      border: outline(palette.border),
      enabledBorder: outline(palette.border),
      focusedBorder: outline(AppColors.accent),
    );
  }
}
