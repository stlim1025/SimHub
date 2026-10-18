import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 테마마다 다른 색 묶음(docs/14 §7): 배경·표면·테두리·글자, 그리고 글자로 쓰는 상태색(오류·정상)과 시상대 금·은·동,
/// 표 머리줄·링크 글자·비교 랩 선(docs/15 §2). [ThemeData.extensions]에 실리고, 위젯은 `context.palette`로 읽는다.
/// 강조색·팀 색·배경으로만 쓰는 상태색(예: 초록 저장 버튼)처럼 두 테마가 같은 색은 [AppColors]를 그대로 쓴다.
/// 밝은 테마의 글자색은 밝은 표면 대비 약 4.5:1 이상이다.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.danger,
    required this.success,
    required this.podiumGold,
    required this.podiumSilver,
    required this.podiumBronze,
    required this.tableHeader,
    required this.link,
    required this.comparison,
  });

  /// 어두운 테마(기존 P6 화면 그대로).
  static const dark = AppPalette(
    background: AppColors.background,
    surface: AppColors.surface,
    border: AppColors.border,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
    danger: AppColors.danger,
    success: AppColors.success,
    podiumGold: AppColors.podiumGold,
    podiumSilver: AppColors.podiumSilver,
    podiumBronze: AppColors.podiumBronze,
    tableHeader: AppColors.tableHeader,
    link: AppColors.link,
    comparison: AppColors.comparisonLap,
  );

  /// 밝은 테마.
  static const light = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    border: AppColors.lightBorder,
    textPrimary: AppColors.lightTextPrimary,
    textMuted: AppColors.lightTextMuted,
    danger: AppColors.lightDanger,
    success: AppColors.lightSuccess,
    podiumGold: AppColors.lightPodiumGold,
    podiumSilver: AppColors.lightPodiumSilver,
    podiumBronze: AppColors.lightPodiumBronze,
    tableHeader: AppColors.lightTableHeader,
    link: AppColors.lightLink,
    comparison: AppColors.lightComparisonLap,
  );

  final Color background;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textMuted;

  /// 오류·무효 글자(ColorScheme.error도 이 색).
  final Color danger;

  /// 정상·실시간 표시(글자·아이콘·점).
  final Color success;

  /// 시상대 1·2·3위 글자(docs/12 §8.5).
  final Color podiumGold;
  final Color podiumSilver;
  final Color podiumBronze;

  /// 촘촘한 표의 머리줄 배경(표면보다 살짝 어둡다, docs/15 §2.1).
  final Color tableHeader;

  /// 눌러서 여는 값(랩타임 등)의 글자. 강조색 계열이면서 표면 대비 4.5:1 이상.
  final Color link;

  /// 텔레메트리 비교 랩(내 최고 랩) 선 — 청록(docs/15 §2.3). 이 랩은 강조색.
  final Color comparison;

  /// 순위 → 시상대 글자색(1·2·3위), 그 외 null.
  Color? podiumFor(int? place) => switch (place) {
        1 => podiumGold,
        2 => podiumSilver,
        3 => podiumBronze,
        _ => null,
      };

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textMuted,
    Color? danger,
    Color? success,
    Color? podiumGold,
    Color? podiumSilver,
    Color? podiumBronze,
    Color? tableHeader,
    Color? link,
    Color? comparison,
  }) =>
      AppPalette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textMuted: textMuted ?? this.textMuted,
        danger: danger ?? this.danger,
        success: success ?? this.success,
        podiumGold: podiumGold ?? this.podiumGold,
        podiumSilver: podiumSilver ?? this.podiumSilver,
        podiumBronze: podiumBronze ?? this.podiumBronze,
        tableHeader: tableHeader ?? this.tableHeader,
        link: link ?? this.link,
        comparison: comparison ?? this.comparison,
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
      danger: mix(danger, other.danger),
      success: mix(success, other.success),
      podiumGold: mix(podiumGold, other.podiumGold),
      podiumSilver: mix(podiumSilver, other.podiumSilver),
      podiumBronze: mix(podiumBronze, other.podiumBronze),
      tableHeader: mix(tableHeader, other.tableHeader),
      link: mix(link, other.link),
      comparison: mix(comparison, other.comparison),
    );
  }
}

/// `context.palette`: 현재 테마의 [AppPalette]. 앱 테마를 쓰지 않는 곳(일부 위젯 테스트)에서는 기본(어두운) 팔레트.
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
