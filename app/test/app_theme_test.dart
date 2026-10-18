import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';

/// 밝은 표면 위 글자가 맞춰야 하는 대비(WCAG AA 본문).
const double _minTextContrast = 4.5;

/// AppTheme은 GoogleFonts(Inter)를 쓴다. 테스트에는 글꼴 파일·네트워크가 없으므로 내려받기를 끄고,
/// 그 때문에 비동기로 나는 글꼴 로딩 실패만 이 영역에서 삼킨다(이 테스트는 색·구성만 본다). 다른 오류는 그대로 실패시킨다.
Future<ThemeData> _build(ThemeData Function() theme) {
  GoogleFonts.config.allowRuntimeFetching = false;
  final result = Completer<ThemeData>();
  runZonedGuarded(
    () => result.complete(theme()),
    (error, stack) {
      if (!error.toString().contains('allowRuntimeFetching') && !result.isCompleted) {
        result.completeError(error, stack);
      }
    },
    zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
  );
  return result.future;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (light, dark) = la > lb ? (la, lb) : (lb, la);
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('어두운 테마는 기존 화면 그대로다(색 토큰·구성 고정)', () async {
    final theme = await _build(() => AppTheme.dark);

    expect(theme.brightness, Brightness.dark);
    expect(theme.extension<AppPalette>(), same(AppPalette.dark));
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.canvasColor, AppColors.surface);
    expect(theme.dividerColor, AppColors.border);
    expect(theme.colorScheme.primary, AppColors.accent);
    expect(theme.colorScheme.onPrimary, AppColors.onAccent);
    expect(theme.colorScheme.surface, AppColors.surface);
    expect(theme.colorScheme.onSurface, AppColors.textPrimary);
    expect(theme.colorScheme.onSurfaceVariant, AppColors.textMuted);
    expect(theme.colorScheme.outline, AppColors.border);
    expect(theme.colorScheme.error, AppColors.danger);
    expect(theme.cardTheme.color, AppColors.surface);
    expect((theme.cardTheme.shape! as RoundedRectangleBorder).side.color, AppColors.border);
    expect(theme.appBarTheme.backgroundColor, AppColors.surface);
    expect(theme.inputDecorationTheme.fillColor, AppColors.surface);
    expect(theme.textTheme.bodyMedium?.color, AppColors.textPrimary);

    // 어두운 팔레트의 상태·시상대 색은 기존 토큰 그대로다.
    expect(AppPalette.dark.danger, AppColors.danger);
    expect(AppPalette.dark.success, AppColors.success);
    expect(AppPalette.dark.podiumFor(1), AppColors.podiumGold);
    expect(AppPalette.dark.podiumFor(2), AppColors.podiumSilver);
    expect(AppPalette.dark.podiumFor(3), AppColors.podiumBronze);
    expect(AppPalette.dark.podiumFor(4), isNull);
  });

  test('밝은 테마는 밝은 팔레트를 싣는다', () async {
    final theme = await _build(() => AppTheme.light);

    expect(theme.brightness, Brightness.light);
    expect(theme.extension<AppPalette>(), same(AppPalette.light));
    expect(theme.scaffoldBackgroundColor, AppColors.lightBackground);
    expect(theme.colorScheme.primary, AppColors.accent);
    expect(theme.colorScheme.surface, AppColors.lightSurface);
    expect(theme.colorScheme.error, AppColors.lightDanger);
    expect(theme.textTheme.bodyMedium?.color, AppColors.lightTextPrimary);
  });

  test('링크 글자(랩타임)는 두 테마의 표면·배경·표 머리줄 위에서 4.5:1 이상이다', () {
    for (final palette in [AppPalette.dark, AppPalette.light]) {
      for (final background in [palette.surface, palette.background, palette.tableHeader]) {
        expect(_contrast(palette.link, background), greaterThanOrEqualTo(_minTextContrast));
      }
    }
  });

  test('그래프 선(이 랩 강조색·비교 랩 청록)은 두 테마의 표면 위에서 3:1 이상이다', () {
    const minGraphicContrast = 3.0;
    for (final palette in [AppPalette.dark, AppPalette.light]) {
      expect(_contrast(AppColors.accent, palette.surface), greaterThanOrEqualTo(minGraphicContrast));
      expect(_contrast(palette.comparison, palette.surface), greaterThanOrEqualTo(minGraphicContrast));
    }
  });

  test('밝은 팔레트의 글자색은 밝은 배경·표면 위에서 4.5:1 이상이다', () {
    const palette = AppPalette.light;
    final textColors = {
      'textPrimary': palette.textPrimary,
      'textMuted': palette.textMuted,
      'danger': palette.danger,
      'success': palette.success,
      'podiumGold': palette.podiumGold,
      'podiumSilver': palette.podiumSilver,
      'podiumBronze': palette.podiumBronze,
      'link': palette.link,
    };

    for (final MapEntry(key: name, value: color) in textColors.entries) {
      for (final background in [palette.surface, palette.background]) {
        expect(_contrast(color, background), greaterThanOrEqualTo(_minTextContrast), reason: name);
      }
    }
  });
}
