import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/car_painter.dart';
import 'package:simcenter_app/features/lap_detail/presentation/car_detail_cards.dart';
import 'package:simcenter_app/features/lap_detail/presentation/car_tyres_card.dart';
import 'package:simcenter_app/features/lap_detail/presentation/lap_info_card.dart';
import 'package:simcenter_app/features/lap_detail/presentation/lap_time_cards.dart';
import 'package:simcenter_app/features/sessions/presentation/tyre_stints_view.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

Future<void> _pump(WidgetTester tester, LapDetail detail) =>
    pumpLapDetail(tester, detailRepo: FakeLapDetailRepository(details: {'l1': detail}));

/// [label] 줄(상세 목록)의 값 쪽에 [value] 글자가 있는지.
Finder _rowValue(String label, String value) =>
    find.descendant(of: find.byKey(ValueKey('detail-row-$label')), matching: find.text(value));

CarPainter _carPainter(WidgetTester tester) =>
    tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((p) => p.painter).whereType<CarPainter>().single;

void main() {
  testWidgets('넓은 화면: Car & Tyres는 Lap Time·Comparison과, Damage는 Lap Details 쪽과 같은 줄 높이로 맞춘다', (t) async {
    await _pump(t, sampleDetail());

    final comparison = t.getRect(find.byType(ComparisonCard));
    final carTyres = t.getRect(find.byType(CarTyresCard));
    final lapInfo = t.getRect(find.byType(LapInfoCard));
    final damage = t.getRect(find.byType(DamageCard));
    expect(carTyres.left, greaterThan(comparison.right)); // 두 열
    expect(carTyres.bottom, moreOrLessEquals(comparison.bottom));
    expect(damage.top, moreOrLessEquals(lapInfo.top));
  });

  group('Lap Time · Comparison', () {
    testWidgets('Lap Time은 링크 색 큰 랩타임과 섹터 3개', (t) async {
      await _pump(t, sampleDetail());

      final total = find.byKey(const ValueKey('lap-time-total'));
      expect(t.widget<Text>(total).data, '1:38.448');
      expect(t.widget<Text>(total).style?.color, t.element(total).palette.link);
      for (final sector in ['0:31.000', '0:33.448', '0:34.000']) {
        expect(find.text(sector), findsWidgets, reason: sector);
      }
    });

    testWidgets('Comparison 표는 내 최고 랩 / 이 랩 / Delta × TOTAL · SEC 1~3, 빠르면 초록 −, 느리면 빨강 +', (t) async {
      await _pump(t, sampleDetail());

      for (final header in ['TOTAL', 'SEC 1', 'SEC 2', 'SEC 3']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('내 최고 랩'), findsOneWidget);
      expect(find.text('이 랩'), findsOneWidget);
      expect(find.text('Delta'), findsOneWidget);
      expect(find.text('1:38.000'), findsWidgets);
      final context = t.element(find.text('Delta'));
      Color? colorOf(String text) => t.widget<Text>(find.text(text)).style?.color;
      expect(colorOf('+0.448'), context.palette.danger);
      expect(colorOf('+0.500'), context.palette.danger);
      expect(colorOf('+0.148'), context.palette.danger);
      expect(colorOf('-0.200'), context.palette.success);
    });

    testWidgets('이 랩이 내 최고면 표 대신 "이 랩이 내 최고 기록"', (t) async {
      await _pump(t, sampleDetail(comparison: sampleComparison(id: 'l1')));

      expect(find.text('이 랩이 내 최고 기록'), findsOneWidget);
      expect(find.text('Delta'), findsNothing);
    });
  });

  group('Lap Details 목록', () {
    testWidgets('Track · Team · Game Mode(모드 · 세션) · Lap · Lap Valid · Lap ID · Date', (t) async {
      await _pump(t, sampleDetail());

      expect(_rowValue('Track', 'Jeddah'), findsOneWidget);
      expect(_rowValue('Team', 'Ferrari'), findsOneWidget);
      // D-51: Game Mode 줄은 모드와 세션을 함께(Session 줄은 따로 두지 않는다).
      expect(_rowValue('Game Mode', 'Driver Career · Time Trial'), findsOneWidget);
      expect(find.text('Session'), findsNothing);
      expect(_rowValue('Lap', '5'), findsOneWidget);
      expect(_rowValue('Lap Valid', 'Valid'), findsOneWidget);
      expect(_rowValue('Lap ID', 'l1'), findsOneWidget);
      expect(_rowValue('Date', DateFormat('yyyy-MM-dd HH:mm:ss').format(sampleSetAt.toLocal())), findsOneWidget);
    });

    testWidgets('무효 랩은 빨간 ✕ Invalid, 모르는 값은 -', (t) async {
      final lap = lapOf('l1', 'Jeddah', 98448, isValid: false);
      await _pump(t, sampleDetail(lap: lap, sessionId: null));

      expect(_rowValue('Lap Valid', 'Invalid'), findsOneWidget);
      expect(_rowValue('Team', '-'), findsOneWidget);
      expect(_rowValue('Game Mode', 'Time Trial'), findsOneWidget); // 모드를 모르면 세션만
      expect(_rowValue('Lap', '-'), findsOneWidget);
      expect(find.text('세션 보기'), findsNothing);
    });

    testWidgets('Lap ID 복사 버튼은 전체 Id를 클립보드에 넣는다', (t) async {
      String? clipboardText;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      const longId = '0192f0aa-1111-7000-8000-000000000001';
      await pumpLapDetail(
        t,
        detailRepo: FakeLapDetailRepository(
          details: {longId: sampleDetail(lap: sampleLap(id: longId))},
        ),
        location: '/laps/$longId',
      );
      expect(_rowValue('Lap ID', '0192f0aa'), findsOneWidget);

      await t.tap(find.byTooltip('랩 ID 복사'));
      await t.pumpAndSettle();

      expect(clipboardText, longId);
      expect(find.text('랩 ID를 복사했어요'), findsOneWidget);
    });

    testWidgets('세션이 연결돼 있으면 세션 보기 → /sessions/:sessionId', (t) async {
      final router = await pumpLapDetail(t, detailRepo: FakeLapDetailRepository(details: {'l1': sampleDetail()}));

      await t.tap(find.text('세션 보기'));
      await t.pumpAndSettle();

      expect(locationOf(router), '/sessions/s1');
    });
  });

  group('Car & Tyres', () {
    testWidgets('바퀴는 마모 단계(25/50/75%)로, 앞날개 L/R은 손상으로 칠한다', (t) async {
      await _pump(t, sampleDetail());

      final colors = _carPainter(t).colors;
      expect(
        [
          CarPart.tyreFrontLeft,
          CarPart.tyreFrontRight,
          CarPart.tyreRearLeft,
          CarPart.tyreRearRight,
        ].map((p) => colors[p]),
        [AppColors.wearMedium, AppColors.wearLow, AppColors.wearLow, AppColors.wearCritical],
      );
      expect(colors[CarPart.frontWingLeft], AppColors.wearLow);
      expect(colors[CarPart.frontWingRight], AppColors.wearHigh);
    });

    testWidgets('값이 없는 부품(노즈·서스펜션·섀시)은 중립 회색, 조종석은 배경색', (t) async {
      await _pump(t, sampleDetail());

      final painter = _carPainter(t);
      final palette = t.element(find.byType(CustomPaint).first).palette;
      for (final part in [CarPart.nose, CarPart.suspension, CarPart.chassis]) {
        expect(painter.colors[part], palette.textMuted, reason: part.name);
      }
      expect(painter.cockpitColor, palette.background);
    });

    test('carColorFor: 부품마다 맞는 손상 값을 25/50/75% 단계 색으로', () {
      const car = CarSnapshot(
        sidepodDamage: 10,
        floorDamage: 30,
        diffuserDamage: 60,
        engineDamage: 80,
        rearWingDamage: 0,
        tyreWearEnd: WheelValues(rearLeft: 49, rearRight: 50, frontLeft: 24.9, frontRight: 75),
      );
      const palette = AppPalette.dark;
      expect(carColorFor(CarPart.sidepods, car, palette), AppColors.wearLow);
      expect(carColorFor(CarPart.floor, car, palette), AppColors.wearMedium);
      expect(carColorFor(CarPart.diffuser, car, palette), AppColors.wearHigh);
      expect(carColorFor(CarPart.engineCover, car, palette), AppColors.wearCritical);
      expect(carColorFor(CarPart.rearWing, car, palette), AppColors.wearLow);
      expect(carColorFor(CarPart.tyreFrontLeft, car, palette), AppColors.wearLow);
      expect(carColorFor(CarPart.tyreRearLeft, car, palette), AppColors.wearMedium);
      expect(carColorFor(CarPart.tyreRearRight, car, palette), AppColors.wearHigh);
      expect(carColorFor(CarPart.tyreFrontRight, car, palette), AppColors.wearCritical);
      expect(carColorFor(CarPart.frontWingLeft, car, palette), palette.textMuted);
    });

    testWidgets('바퀴 옆 마모 % 배지와 기울임 증가분', (t) async {
      await _pump(t, sampleDetail());

      for (final (wheel, wear) in [('fl', '31%'), ('fr', '18%'), ('rl', '24%'), ('rr', '80%')]) {
        expect(
          find.descendant(of: find.byKey(ValueKey('wear-badge-$wheel')), matching: find.text(wear)),
          findsOneWidget,
          reason: wheel,
        );
      }
      final delta = find.descendant(of: find.byKey(const ValueKey('wear-badge-rr')), matching: find.text('+66.0%'));
      expect(t.widget<Text>(delta).style?.fontStyle, FontStyle.italic);
      expect(find.text('+4.0%'), findsNWidgets(3));
    });

    testWidgets('컴파운드 원과 이름(실제 컴파운드)·타이어 나이', (t) async {
      await _pump(t, sampleDetail());

      expect(find.byType(TyreCompoundCircle), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('Soft (C3) · 3랩째'), findsOneWidget);
    });

    testWidgets('마모 시작 값이 없으면 증가분을 보이지 않는다', (t) async {
      await _pump(
        t,
        sampleDetail(
          car: const CarSnapshot(tyreWearEnd: WheelValues(frontLeft: 10, frontRight: 10, rearLeft: 10, rearRight: 10)),
        ),
      );

      expect(find.text('10%'), findsNWidgets(4));
      final wearDeltas = find.descendant(
        of: find.byType(CarTyresCard),
        matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data?.startsWith('+') ?? false) && (w.data?.endsWith('%') ?? false),
        ),
      );
      expect(wearDeltas, findsNothing);
    });
  });

  group('Damage · Conditions · Fuel · ERS', () {
    testWidgets('손상은 0이면 -, 바퀴 값은 FL / FR / RL / RR', (t) async {
      await _pump(t, sampleDetail());

      expect(_rowValue('Front Wing (L/R)', '- / 60%'), findsOneWidget);
      expect(_rowValue('Rear Wing', '-'), findsOneWidget);
      expect(_rowValue('Floor', '-'), findsOneWidget);
      expect(_rowValue('Diffuser', '-'), findsOneWidget);
      expect(_rowValue('Sidepod', '20%'), findsOneWidget);
      expect(_rowValue('Gear Box', '10%'), findsOneWidget);
      expect(_rowValue('Engine', '30%'), findsOneWidget);
      expect(_rowValue('Tyre Wear', '31% / 18% / 24% / 80%'), findsOneWidget);
      expect(_rowValue('Brake Damage', '- / - / - / 5%'), findsOneWidget);
    });

    testWidgets('날씨·기온·비 예보, 연료 사용·남은 양·남은 랩, ERS 사용·남은 %(4 MJ 기준)', (t) async {
      await _pump(t, sampleDetail());

      expect(_rowValue('Weather', 'Clear'), findsOneWidget);
      expect(_rowValue('Air temperature', '21°C'), findsOneWidget);
      expect(_rowValue('Track temperature', '31°C'), findsOneWidget);
      expect(_rowValue('Rain forecast', '4%'), findsOneWidget);
      expect(_rowValue('Fuel used this lap', '1.70 kg'), findsOneWidget);
      expect(_rowValue('Fuel remaining', '22.70 kg'), findsOneWidget);
      expect(_rowValue('Laps remaining', '13.1'), findsOneWidget);
      expect(_rowValue('ERS used this lap', '12.7%'), findsOneWidget);
      expect(_rowValue('ERS remaining', '24.7%'), findsOneWidget);
    });

    testWidgets('차량 스냅샷이 없으면 차·손상·연료·ERS 대신 안내 한 장(날씨는 있으면 보인다)', (t) async {
      await _pump(t, sampleDetail(car: null));

      expect(find.text('이 랩에는 차량 데이터가 없어요'), findsOneWidget);
      expect(find.text('Car & Tyres'), findsNothing);
      expect(find.text('Damage'), findsNothing);
      expect(find.text('Fuel'), findsNothing);
      expect(find.text('ERS'), findsNothing);
      expect(find.text('Conditions'), findsOneWidget);
    });

    testWidgets('날씨 정보도 없으면 Conditions 카드를 숨긴다', (t) async {
      await _pump(t, sampleDetail(car: null, conditions: null));

      expect(find.text('Conditions'), findsNothing);
      expect(find.text('이 랩에는 차량 데이터가 없어요'), findsOneWidget);
    });
  });
}
