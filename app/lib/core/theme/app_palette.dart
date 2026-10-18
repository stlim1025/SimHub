import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 테마마다 다른 기본 색(배경·표면·테두리·글자) 묶음(docs/14 §7). [ThemeData.extensions]에 실리고,
/// 위젯은 `context.palette`로 읽는다. 강조색·상태색·팀 색처럼 두 테마가 같은 색은 [AppColors]를 그대로 쓴다.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
  });

  /// 어두운 테마(기존 P6 화면 그대로).
  static const dark = AppPalette(
    background: AppColors.background,
    surface: AppColors.surface,
    border: AppColors.border,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
  );

  /// 밝은 테마.
  static const light = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    border: AppColors.lightBorder,
    textPrimary: AppColors.lightTextPrimary,
    textMuted: AppColors.lightTextMuted,
  );

  final Color background;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textMuted;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textMuted,
  }) =>
      AppPalette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textMuted: textMuted ?? this.textMuted,
      );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      border: mix(border, other.border),
      textPrimary: mix(textPrimary, other.textPrimary),
      textMuted: mix(textMuted, other.textMuted),
    );
  }
}

/// `context.palette`: 현재 테마의 [AppPalette]. 앱 테마를 쓰지 않는 곳(일부 위젯 테스트)에서는 기본(어두운) 팔레트.
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
