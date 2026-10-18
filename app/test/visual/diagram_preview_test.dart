// 엔진·차 그림 미리보기 PNG(docs/15 §2.3·§11.3). 눈으로 확인하는 용도라 기본 실행에선 건너뛴다.
// 실행: DIAGRAM_PREVIEW_DIR=<저장소 밖 폴더> flutter test test/visual
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/car_painter.dart';
import 'package:simcenter_app/features/lap_detail/presentation/car_tyres_card.dart';
import 'package:simcenter_app/features/sessions/domain/session_detail_models.dart';
import 'package:simcenter_app/features/sessions/presentation/engine_painter.dart';
import 'package:simcenter_app/features/sessions/presentation/engine_wear_card.dart';

final String? _outDir = Platform.environment['DIAGRAM_PREVIEW_DIR'];
const double _pixelRatio = 2;
const double _pad = 12;

const _engineStates = {
  'fresh': EngineWear(ice: 5, turboCharger: 8, mguH: 3, mguK: 10, energyStore: 2, controlElectronics: 4, gearbox: 6),
  'mixed': EngineWear(
    ice: 12,
    turboCharger: 30,
    mguH: 55,
    mguK: 80,
    energyStore: 20,
    controlElectronics: 60,
    gearbox: 52,
  ),
  'partial': EngineWear(ice: 40, gearbox: 90),
};

const _carStates = {
  'clean': CarSnapshot(
    tyreWearEnd: WheelValues(frontLeft: 5, frontRight: 6, rearLeft: 7, rearRight: 8),
    frontLeftWingDamage: 0,
    frontRightWingDamage: 0,
    rearWingDamage: 0,
    floorDamage: 0,
    diffuserDamage: 0,
    sidepodDamage: 0,
    engineDamage: 0,
  ),
  'damaged': CarSnapshot(
    tyreWearStart: WheelValues(frontLeft: 27, frontRight: 14, rearLeft: 20, rearRight: 76),
    tyreWearEnd: WheelValues(frontLeft: 31, frontRight: 18, rearLeft: 24, rearRight: 80),
    frontLeftWingDamage: 10,
    frontRightWingDamage: 60,
    rearWingDamage: 30,
    floorDamage: 80,
    diffuserDamage: 45,
    sidepodDamage: 20,
    engineDamage: 70,
  ),
  'unknown': CarSnapshot(),
};

Future<void> _capture(WidgetTester tester, String name, Widget child, Size size) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(RepaintBoundary(key: key, child: child));
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// 글꼴 내려받기(GoogleFonts) 없이 팔레트만 실은 테마.
ThemeData _theme(AppPalette palette) => ThemeData(
  brightness: palette == AppPalette.dark ? Brightness.dark : Brightness.light,
  scaffoldBackgroundColor: palette.background,
  cardTheme: CardThemeData(color: palette.surface, margin: EdgeInsets.zero, elevation: 0),
  extensions: [palette],
);

Widget _themed(ThemeData theme, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(_pad), child: child),
  ),
);

Widget _canvas(AppPalette palette, Size size, CustomPainter painter) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(
    color: palette.surface,
    child: Padding(
      padding: const EdgeInsets.all(_pad),
      child: CustomPaint(size: size, painter: painter),
    ),
  ),
);

void main() {
  final skip = _outDir == null ? 'DIAGRAM_PREVIEW_DIR 없음' : null;
  const themes = {'dark': AppPalette.dark, 'light': AppPalette.light};
  Size padded(Size s) => Size(s.width + 2 * _pad, s.height + 2 * _pad);

  testWidgets('엔진 그림 미리보기', skip: skip != null, (t) async {
    Directory(_outDir!).createSync(recursive: true);
    for (final MapEntry(key: theme, value: palette) in themes.entries) {
      for (final MapEntry(key: state, value: wear) in _engineStates.entries) {
        final colors = [for (final part in EnginePart.values) engineColorFor(part, wear, palette)];
        await _capture(
          t,
          'engine_${theme}_$state',
          _canvas(palette, kEngineDiagramSize, EnginePainter(partColors: colors, baseColor: palette.surface)),
          padded(kEngineDiagramSize),
        );
      }
    }
    await _capture(
      t,
      'engine_card_dark',
      _themed(_theme(AppPalette.dark), EngineWearCard(wear: _engineStates['mixed'])),
      const Size(560, 360),
    );
  });

  testWidgets('차 그림 미리보기', skip: skip != null, (t) async {
    Directory(_outDir!).createSync(recursive: true);
    for (final MapEntry(key: theme, value: palette) in themes.entries) {
      for (final MapEntry(key: state, value: car) in _carStates.entries) {
        final colors = {for (final part in CarPart.values) part: carColorFor(part, car, palette)};
        await _capture(
          t,
          'car_${theme}_$state',
          _canvas(
            palette,
            kCarDiagramSize,
            CarPainter(colors: colors, baseColor: palette.surface, cockpitColor: palette.background),
          ),
          padded(kCarDiagramSize),
        );
      }
    }
    for (final MapEntry(key: theme, value: data) in {
      'dark': _theme(AppPalette.dark),
      'light': _theme(AppPalette.light),
    }.entries) {
      await _capture(
        t,
        'car_card_$theme',
        _themed(data, CarTyresCard(car: _carStates['damaged']!)),
        const Size(460, 480),
      );
    }
  });
}
