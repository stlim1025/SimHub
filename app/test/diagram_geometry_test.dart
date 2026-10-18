import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/layout/equal_height.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/features/lap_detail/presentation/car_geometry.dart';
import 'package:simcenter_app/features/lap_detail/presentation/diagram_style.dart';
import 'package:simcenter_app/features/sessions/domain/session_detail_models.dart';
import 'package:simcenter_app/features/sessions/presentation/engine_geometry.dart';
import 'package:simcenter_app/features/sessions/presentation/engine_wear_card.dart';

const double _epsilon = 1e-6;

/// 모든 부품이 단위 정사각형(0~1) 안에 있는지.
void _expectInsideUnit<T>(List<DiagramShape<T>> shapes) {
  for (final shape in shapes) {
    final b = shape.path.getBounds();
    expect(
      b.left >= -_epsilon && b.top >= -_epsilon && b.right <= 1 + _epsilon && b.bottom <= 1 + _epsilon,
      isTrue,
      reason: '${shape.part} $b',
    );
  }
}

/// [a]와 [b]의 경계가 세로 중심선 기준 거울상인지.
void _expectMirrored(Path a, Path b) {
  final ba = a.getBounds();
  final bb = b.getBounds();
  expect(bb.left, closeTo(1 - ba.right, _epsilon));
  expect(bb.right, closeTo(1 - ba.left, _epsilon));
  expect(bb.top, closeTo(ba.top, _epsilon));
  expect(bb.bottom, closeTo(ba.bottom, _epsilon));
}

Path _pathOf<T>(List<DiagramShape<T>> shapes, T part) => shapes.firstWhere((s) => s.part == part).path;

void main() {
  group('엔진 그림(docs/15 §11.3)', () {
    test('부품마다 맞는 마모 값을 25/50/75% 단계 색으로, 값이 없으면 중립 회색', () {
      const wear = EngineWear(ice: 10, turboCharger: 30, mguH: 60, mguK: 75, energyStore: 24.9, gearbox: 50);
      const palette = AppPalette.dark;
      expect(engineColorFor(EnginePart.ice, wear, palette), AppColors.wearLow);
      expect(engineColorFor(EnginePart.turboCharger, wear, palette), AppColors.wearMedium);
      expect(engineColorFor(EnginePart.mguH, wear, palette), AppColors.wearHigh);
      expect(engineColorFor(EnginePart.mguK, wear, palette), AppColors.wearCritical);
      expect(engineColorFor(EnginePart.energyStore, wear, palette), AppColors.wearLow);
      expect(engineColorFor(EnginePart.gearbox, wear, palette), AppColors.wearHigh);
      expect(engineColorFor(EnginePart.controlElectronics, wear, palette), palette.textMuted);
    });

    test('모든 부품이 그림에 있고 단위 좌표 안, 터보·MGU-H 몸통은 좌우 대칭', () {
      final shapes = engineShapes();
      expect(shapes.map((s) => s.part).toSet(), EnginePart.values.toSet());
      _expectInsideUnit(shapes);
      // MGU-H 첫 부품은 배기관, 둘째가 오른쪽 몸통.
      final mguHPod = shapes.where((s) => s.part == EnginePart.mguH).elementAt(1).path;
      _expectMirrored(_pathOf(shapes, EnginePart.turboCharger), mguHPod);
      final block = engineBlockPath().getBounds();
      expect(block.left, closeTo(1 - block.right, _epsilon));
    });
  });

  group('차 그림(docs/15 §2.3)', () {
    test('모든 부품이 그림에 있고 단위 좌표 안', () {
      final shapes = carShapes();
      expect(shapes.map((s) => s.part).toSet(), CarPart.values.toSet());
      _expectInsideUnit(shapes);
    });

    test('좌우 바퀴·앞날개는 거울상, 몸통 부품은 중심선 대칭', () {
      final shapes = carShapes();
      _expectMirrored(_pathOf(shapes, CarPart.tyreFrontLeft), _pathOf(shapes, CarPart.tyreFrontRight));
      _expectMirrored(_pathOf(shapes, CarPart.tyreRearLeft), _pathOf(shapes, CarPart.tyreRearRight));
      _expectMirrored(_pathOf(shapes, CarPart.frontWingLeft), _pathOf(shapes, CarPart.frontWingRight));
      for (final part in [CarPart.floor, CarPart.sidepods, CarPart.engineCover, CarPart.diffuser, CarPart.rearWing]) {
        final b = _pathOf(shapes, part).getBounds();
        expect(b.left, closeTo(1 - b.right, _epsilon), reason: part.name);
      }
      expect(kFrontWheelCenterFactor, lessThan(kRearWheelCenterFactor));
    });
  });

  group('카드 격자(EqualHeightRow · FillColumn)', () {
    Widget host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 416, child: child),
      ),
    );

    testWidgets('한 줄의 칸은 같은 폭·같은 높이, 간격만큼 떨어진다', (t) async {
      const a = Key('a');
      const b = Key('b');
      await t.pumpWidget(
        host(
          const EqualHeightRow(
            gap: 16,
            children: [
              SizedBox(key: a, height: 100),
              SizedBox(key: b, height: 250),
            ],
          ),
        ),
      );

      expect(t.getSize(find.byKey(a)), const Size(200, 250));
      expect(t.getSize(find.byKey(b)), const Size(200, 250));
      expect(t.getTopLeft(find.byKey(b)).dx - t.getTopRight(find.byKey(a)).dx, 16);
    });

    testWidgets('짧은 열은 마지막 카드를 늘려 두 열의 바닥을 맞춘다', (t) async {
      const last = Key('last');
      const tall = Key('tall');
      await t.pumpWidget(
        host(
          const EqualHeightRow(
            gap: 16,
            children: [
              FillColumn(
                gap: 16,
                children: [
                  SizedBox(height: 50),
                  SizedBox(key: last, height: 50),
                ],
              ),
              FillColumn(gap: 16, children: [SizedBox(key: tall, height: 300)]),
            ],
          ),
        ),
      );

      expect(t.getSize(find.byKey(last)).height, 300 - 50 - 16);
      expect(t.getBottomLeft(find.byKey(last)).dy, t.getBottomLeft(find.byKey(tall)).dy);
    });
  });
}
