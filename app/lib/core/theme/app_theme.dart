import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// 앱 테마(Material3) — Cockpit HUD: 거의 검은 배경 + 앰버 강조색, 좁은 폭의 굵은 글꼴(Barlow Condensed),
/// 오른쪽 위 모서리를 깎은 패널·양끝이 비스듬한 버튼과 탭(SF1000 핸들 화면 느낌). 같은 구성의 밝은 테마도 있다(docs/14 §7).
/// 색은 [AppColors] 토큰과 [AppPalette]만 쓴다. 어느 테마를 쓸지는 사용자 설정(`themeModeProvider`)이 정한다.
class AppTheme {
  const AppTheme._();

  /// 카드 오른쪽 위를 깎는 크기.
  static const double _cardChamfer = 16;

  /// 버튼·탭 양끝을 비스듬히 깎는 크기.
  static const double _controlChamfer = 9;

  // 웹 대시보드 느낌(F1Laps 참고)의 촘촘한 컨트롤 치수 — Material 3 기본(알약·48px·가로 꽉 채움)을 쓰지 않는다.
  static const double _controlRadius = 2;
  static const double _menuChamfer = 10;
  static const double _buttonHeight = 36;
  static const double _buttonMinWidth = 64;
  static const double _buttonPaddingX = 14;
  static const double _textButtonHeight = 32;
  static const double _textButtonPaddingX = 8;
  static const double _controlFontSize = 15;
  static const double _controlLetterSpacing = 0.6;
  static const double _tabLetterSpacing = 0.8;

  /// 좁은 폭 글꼴은 같은 크기에서 작아 보여 본문 전체를 한 단계 키운다.
  static const double _fontSizeDelta = 1;
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
    const controlShape = BeveledRectangleBorder(
      borderRadius: BorderRadius.only(
        topRight: Radius.circular(_controlChamfer),
        bottomLeft: Radius.circular(_controlChamfer),
      ),
    );

    return base.copyWith(
      extensions: [palette],
      // 글자 크기를 키우려면 크기가 있어야 해서, 기본 글자 모양(크기 포함)에 테마 글자색 설정을 덮어 시작한다.
      textTheme: GoogleFonts.barlowCondensedTextTheme(base.typography.englishLike.merge(base.textTheme)).apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
        fontSizeDelta: _fontSizeDelta,
      ),
      tabBarTheme: TabBarThemeData(
        indicator: const ShapeDecoration(color: AppColors.accent, shape: controlShape),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: AppColors.onAccent,
        unselectedLabelColor: palette.textMuted,
        labelStyle: const TextStyle(fontSize: _controlFontSize, fontWeight: FontWeight.w700, letterSpacing: _tabLetterSpacing),
        unselectedLabelStyle: const TextStyle(fontSize: _controlFontSize, fontWeight: FontWeight.w600, letterSpacing: _tabLetterSpacing),
        dividerColor: palette.border,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
      ),
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.surface,
      // 웹 화면처럼: 누를 때 번지는 물결·회색 누름 덩어리(모바일 터치 효과)는 없애고, 마우스를 올렸을 때의 옅은 색만 남긴다.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
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
        shape: BeveledRectangleBorder(
          borderRadius: const BorderRadius.only(topRight: Radius.circular(_menuChamfer)),
          side: BorderSide(color: palette.border),
        ),
      ),
      menuTheme: MenuThemeData(style: _menuStyle(palette)),
      dropdownMenuTheme: DropdownMenuThemeData(menuStyle: _menuStyle(palette)),
      inputDecorationTheme: _inputTheme(palette),
    );
  }

  static const TextStyle _controlTextStyle =
      TextStyle(fontSize: _controlFontSize, fontWeight: FontWeight.w700, letterSpacing: _controlLetterSpacing);

  static MenuStyle _menuStyle(AppPalette palette) => MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(_menuElevation),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: _menuPaddingY)),
        shape: WidgetStatePropertyAll(BeveledRectangleBorder(
          borderRadius: const BorderRadius.only(topRight: Radius.circular(_menuChamfer)),
          side: BorderSide(color: palette.border),
        )),
      );

  static CardThemeData _cardTheme(AppPalette palette) => CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        // 어두운 테마는 표면 색만으로 배경과 갈리고, 밝은 테마는 흰 표면이라 얇은 테두리를 둔다.
        shape: BeveledRectangleBorder(
          borderRadius: const BorderRadius.only(topRight: Radius.circular(_cardChamfer)),
          side: palette.background == AppColors.background ? BorderSide.none : BorderSide(color: palette.border),
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
